/// Image loading pipeline for inline markdown images per [A-053].
///
/// Handles path resolution, async loading, downsampling of large images,
/// GIF first-frame extraction, and caching with a 50MB cost limit.
/// Thread-safe: loading runs on background threads, cache is NSCache (thread-safe).

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "imageloader")

// MARK: - Image Load Result

/// Result of an image load operation.
/// `@unchecked Sendable` because `PlatformImage` (UIImage/NSImage) is thread-safe
/// for reading once created, but does not formally conform to `Sendable`.
public enum ImageLoadResult: @unchecked Sendable {
    /// Image loaded successfully with its display size.
    case success(PlatformImage, CGSize)
    /// Image failed to load.
    case failure
}

// MARK: - Platform Image Alias

#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

// MARK: - Image Loader

/// Loads, caches, and downsamples images for inline rendering per [A-053].
///
/// Usage:
/// ```swift
/// let loader = ImageLoader()
/// if let result = loader.cachedImage(for: resolvedURL) {
///     // Use cached image synchronously
/// } else {
///     // Load asynchronously
///     let result = await loader.loadImage(from: resolvedURL, maxWidth: 600)
/// }
/// ```
/// Note: Not `@MainActor` to allow synchronous access from MarkdownRenderer's
/// private methods. In practice, all calls originate from `render()` which is
/// `@MainActor`, so mutable state access is safe. Async callbacks dispatch
/// to MainActor explicitly.
public final class ImageLoader {

    /// Maximum dimension (width or height) before downsampling.
    /// Images larger than this in either dimension are downsampled on load
    /// to prevent memory spikes per AC-4.
    static let maxDimension: CGFloat = 2048

    /// Cache for loaded images. Thread-safe via NSCache.
    /// 50MB cost limit per [A-053].
    private let cache: NSCache<NSURL, CacheEntry>

    /// Tracks in-flight loads to avoid duplicate work.
    private var inFlightURLs: Set<URL> = []

    /// Stores handles to in-flight loading tasks so they can be cancelled on dealloc.
    private var tasks: [URL: Task<Void, Never>] = [:]

    /// Callback invoked when an image finishes loading, so the renderer
    /// can trigger a re-render. Called on the main actor.
    public var onImageLoaded: ((URL) -> Void)?

    deinit {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    public init() {
        cache = NSCache<NSURL, CacheEntry>()
        cache.name = "com.easymarkdown.imageloader"
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB per [A-053]
    }

    // MARK: - Path Resolution

    /// Resolves an image source string from markdown against a document URL.
    ///
    /// - Parameters:
    ///   - source: The image source from the markdown `![alt](source)`.
    ///   - documentURL: The URL of the current document file.
    /// - Returns: A resolved file URL, or nil if resolution fails.
    public static func resolveImageURL(source: String, documentURL: URL?) -> URL? {
        // Empty source
        guard !source.isEmpty else { return nil }

        // Absolute URL (http/https) — return as-is
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return URL(string: source)
        }

        // File URL
        if source.hasPrefix("file://") {
            return URL(string: source)
        }

        // Relative path — resolve against document directory
        guard let docURL = documentURL else { return nil }
        let directory = docURL.deletingLastPathComponent()
        let resolved = directory.appendingPathComponent(source).standardized
        return resolved
    }

    // MARK: - Cache Access

    /// Returns a cached image synchronously, or nil if not cached.
    public func cachedImage(for url: URL) -> ImageLoadResult? {
        guard let entry = cache.object(forKey: url as NSURL) else { return nil }
        return entry.result
    }

    /// Records a broken image in the cache so we don't retry repeatedly.
    public func cacheBrokenImage(for url: URL) {
        let entry = CacheEntry(result: .failure)
        cache.setObject(entry, forKey: url as NSURL, cost: 0)
    }

    // MARK: - Async Loading

    /// Loads an image asynchronously, caches it, and notifies via `onImageLoaded`.
    ///
    /// - Parameters:
    ///   - url: The resolved URL to load from.
    ///   - maxWidth: The maximum display width for scaling.
    public func loadImageIfNeeded(from url: URL, maxWidth: CGFloat) {
        // Already cached
        if cache.object(forKey: url as NSURL) != nil { return }

        // Already loading
        guard !inFlightURLs.contains(url) else { return }
        inFlightURLs.insert(url)

        let task = Task.detached { [weak self] in
            let result = await Self.loadAndProcess(url: url, maxWidth: maxWidth)
            guard let self else { return }

            await MainActor.run { [self] in
                self.inFlightURLs.remove(url)
                self.tasks.removeValue(forKey: url)

                let entry: CacheEntry
                switch result {
                case .success(let image, let size):
                    let cost = Self.estimateMemoryCost(image)
                    entry = CacheEntry(result: .success(image, size))
                    self.cache.setObject(entry, forKey: url as NSURL, cost: cost)
                case .failure:
                    entry = CacheEntry(result: .failure)
                    self.cache.setObject(entry, forKey: url as NSURL, cost: 0)
                }

                self.onImageLoaded?(url)
            }
        }
        tasks[url] = task
    }

    /// Loads and processes an image on a background thread.
    private static func loadAndProcess(url: URL, maxWidth: CGFloat) async -> ImageLoadResult {
        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (downloadedData, response) = try await URLSession.shared.data(from: url)
                // Validate HTTP response
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    logger.warning("HTTP \(httpResponse.statusCode) loading image: \(url.absoluteString)")
                    return .failure
                }
                data = downloadedData
            }

            guard !data.isEmpty else {
                logger.warning("Empty data for image: \(url.absoluteString)")
                return .failure
            }

            // Use CGImageSource for efficient loading, downsampling, and GIF first-frame
            guard let image = downsampleImage(
                data: data,
                maxDimension: maxDimension,
                maxWidth: maxWidth
            ) else {
                logger.warning("Failed to decode image: \(url.absoluteString)")
                return .failure
            }

            let size = CGSize(width: image.size.width, height: image.size.height)
            return .success(image, size)
        } catch {
            logger.warning("Failed to load image: \(url.absoluteString) — \(error.localizedDescription)")
            return .failure
        }
    }

    // MARK: - Downsampling

    /// Downsamples an image using CGImageSource for memory efficiency per AC-4.
    /// For GIFs, extracts the first frame only per AC-5.
    ///
    /// - Parameters:
    ///   - data: Raw image data.
    ///   - maxDimension: Maximum pixel dimension (width or height).
    ///   - maxWidth: Maximum display width for content-fit scaling.
    /// - Returns: A downsampled platform image, or nil on failure.
    public static func downsampleImage(
        data: Data,
        maxDimension: CGFloat,
        maxWidth: CGFloat
    ) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        // Get original dimensions
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            // Fallback: try to create image without downsampling
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            #if canImport(UIKit)
            return UIImage(cgImage: cgImage)
            #elseif canImport(AppKit)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            #endif
        }

        // Determine the effective max dimension: min of maxDimension and maxWidth
        let effectiveMax = min(maxDimension, max(maxWidth, 100))

        // Only downsample if image exceeds limits
        let needsDownsample = pixelWidth > effectiveMax || pixelHeight > effectiveMax

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: needsDownsample ? effectiveMax : max(pixelWidth, pixelHeight)
        ]

        // Index 0 = first frame (handles GIF first-frame per AC-5)
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    // MARK: - Memory Cost Estimation

    /// Estimates the in-memory cost of an image in bytes for NSCache cost tracking.
    private static func estimateMemoryCost(_ image: PlatformImage) -> Int {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else {
            return Int(image.size.width * image.size.height * 4)
        }
        return cgImage.bytesPerRow * cgImage.height
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Int(image.size.width * image.size.height * 4)
        }
        return cgImage.bytesPerRow * cgImage.height
        #endif
    }

    // MARK: - Placeholder

    /// Creates a placeholder image for broken/missing images per AC-3.
    public static func brokenImagePlaceholder(size: CGSize = CGSize(width: 40, height: 40)) -> PlatformImage {
        #if canImport(UIKit)
        let config = UIImage.SymbolConfiguration(pointSize: size.height * 0.6, weight: .light)
        return UIImage(systemName: "photo.badge.exclamationmark", withConfiguration: config)
            ?? UIImage(systemName: "exclamationmark.triangle", withConfiguration: config)
            ?? UIImage()
        #elseif canImport(AppKit)
        return NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: "Broken image")
            ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Broken image")
            ?? NSImage()
        #endif
    }

    /// Computes the display size for an image that fits within `maxWidth`
    /// while preserving aspect ratio per AC-2.
    public static func displaySize(
        for imageSize: CGSize,
        maxWidth: CGFloat
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxWidth * 0.6)
        }

        if imageSize.width <= maxWidth {
            return imageSize
        }

        let scale = maxWidth / imageSize.width
        return CGSize(
            width: maxWidth,
            height: imageSize.height * scale
        )
    }
}

// MARK: - Cache Entry

/// Wrapper for NSCache (requires reference type).
private final class CacheEntry: NSObject {
    let result: ImageLoadResult

    init(result: ImageLoadResult) {
        self.result = result
    }
}

// MARK: - NSTextAttachment for Images

/// Custom text attachment for rendering inline images per [A-053].
///
/// Used by the renderer to insert image attachments into the attributed string.
/// Handles both loaded images and broken-image placeholders.
public final class ImageTextAttachment: NSTextAttachment {

    /// The display bounds for this attachment.
    private let displayBounds: CGRect

    /// Creates an image text attachment with proper bounds.
    ///
    /// - Parameters:
    ///   - image: The image to display.
    ///   - displaySize: The size to render at (aspect-ratio-preserved).
    public init(image: PlatformImage, displaySize: CGSize) {
        self.displayBounds = CGRect(origin: .zero, size: displaySize)
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    /// Decodes from archive. Returns nil per [A-048] (no fatalError in production).
    required init?(coder: NSCoder) {
        self.displayBounds = .zero
        super.init(coder: coder)
    }

    #if canImport(UIKit)
    override public func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        // Scale to fit the text container width if needed
        let maxWidth = lineFrag.width
        if displayBounds.width > maxWidth, maxWidth > 0 {
            let scale = maxWidth / displayBounds.width
            return CGRect(
                x: 0, y: 0,
                width: maxWidth,
                height: displayBounds.height * scale
            )
        }
        return displayBounds
    }
    #elseif canImport(AppKit)
    override public func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let maxWidth = lineFrag.width
        if displayBounds.width > maxWidth, maxWidth > 0 {
            let scale = maxWidth / displayBounds.width
            return NSRect(
                x: 0, y: 0,
                width: maxWidth,
                height: displayBounds.height * scale
            )
        }
        return displayBounds
    }
    #endif
}
