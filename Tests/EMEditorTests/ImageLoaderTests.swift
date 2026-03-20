import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMCore

@MainActor
@Suite("ImageLoader")
struct ImageLoaderTests {

    // MARK: - Path Resolution

    @Test("Resolves relative path against document URL")
    func resolveRelativePath() {
        let docURL = URL(fileURLWithPath: "/Users/test/Documents/notes/README.md")
        let result = ImageLoader.resolveImageURL(source: "./images/diagram.png", documentURL: docURL)

        #expect(result != nil)
        #expect(result?.path.contains("notes/images/diagram.png") == true)
    }

    @Test("Resolves relative path without ./ prefix")
    func resolveRelativePathNoDot() {
        let docURL = URL(fileURLWithPath: "/Users/test/doc.md")
        let result = ImageLoader.resolveImageURL(source: "images/photo.jpg", documentURL: docURL)

        #expect(result != nil)
        #expect(result?.lastPathComponent == "photo.jpg")
    }

    @Test("Resolves parent directory path (..) correctly")
    func resolveParentPath() {
        let docURL = URL(fileURLWithPath: "/Users/test/docs/sub/file.md")
        let result = ImageLoader.resolveImageURL(source: "../images/logo.png", documentURL: docURL)

        #expect(result != nil)
        // After standardization, "../" should resolve correctly
        #expect(result?.path.contains("docs/images/logo.png") == true)
    }

    @Test("Returns nil for relative path without document URL")
    func resolveRelativeNoDocURL() {
        let result = ImageLoader.resolveImageURL(source: "image.png", documentURL: nil)
        #expect(result == nil, "Relative path without document URL should return nil")
    }

    @Test("Returns nil for empty source")
    func resolveEmptySource() {
        let docURL = URL(fileURLWithPath: "/Users/test/doc.md")
        let result = ImageLoader.resolveImageURL(source: "", documentURL: docURL)
        #expect(result == nil, "Empty source should return nil")
    }

    @Test("HTTP URL passes through as-is")
    func resolveHTTPURL() {
        let result = ImageLoader.resolveImageURL(source: "https://example.com/image.png", documentURL: nil)
        #expect(result != nil)
        #expect(result?.absoluteString == "https://example.com/image.png")
    }

    @Test("File URL passes through as-is")
    func resolveFileURL() {
        let result = ImageLoader.resolveImageURL(source: "file:///tmp/image.png", documentURL: nil)
        #expect(result != nil)
        #expect(result?.path == "/tmp/image.png")
    }

    // MARK: - Display Size Calculation

    @Test("Image smaller than maxWidth keeps original size")
    func displaySizeSmallImage() {
        let size = ImageLoader.displaySize(
            for: CGSize(width: 200, height: 100),
            maxWidth: 600
        )
        #expect(size.width == 200)
        #expect(size.height == 100)
    }

    @Test("Image wider than maxWidth scales down preserving aspect ratio")
    func displaySizeScaleDown() {
        let size = ImageLoader.displaySize(
            for: CGSize(width: 1200, height: 600),
            maxWidth: 600
        )
        #expect(size.width == 600)
        #expect(size.height == 300, "Aspect ratio must be preserved")
    }

    @Test("Display size handles zero-dimension image gracefully")
    func displaySizeZeroDimension() {
        let size = ImageLoader.displaySize(
            for: CGSize(width: 0, height: 0),
            maxWidth: 600
        )
        // Should return a reasonable default, not crash
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    // MARK: - Cache

    @Test("Cache returns nil for uncached URL")
    func cacheReturnsNil() {
        let loader = ImageLoader()
        let url = URL(string: "https://example.com/test.png")!
        let result = loader.cachedImage(for: url)
        #expect(result == nil, "Uncached URL should return nil")
    }

    @Test("Broken image can be cached and retrieved")
    func cacheBrokenImage() {
        let loader = ImageLoader()
        let url = URL(string: "https://example.com/broken.png")!

        loader.cacheBrokenImage(for: url)

        let result = loader.cachedImage(for: url)
        #expect(result != nil, "Broken image should be cached")
        if case .failure = result {
            // Expected
        } else {
            Issue.record("Cached broken image should be .failure")
        }
    }

    // MARK: - Placeholder

    @Test("Broken image placeholder is non-empty")
    func brokenImagePlaceholder() {
        let placeholder = ImageLoader.brokenImagePlaceholder()
        #expect(placeholder.size.width > 0, "Placeholder should have non-zero width")
        #expect(placeholder.size.height > 0, "Placeholder should have non-zero height")
    }

    // MARK: - Downsampling

    @Test("Downsample returns nil for invalid data")
    func downsampleInvalidData() {
        let data = "not an image".data(using: .utf8)!
        let result = ImageLoader.downsampleImage(data: data, maxDimension: 2048, maxWidth: 600)
        #expect(result == nil, "Invalid image data should return nil")
    }

    @Test("Downsample handles valid PNG data")
    func downsampleValidPNG() {
        // Create a small test image programmatically
        let size = CGSize(width: 10, height: 10)
        #if canImport(UIKit)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let testImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let data = testImage?.pngData() else {
            Issue.record("Failed to create test PNG data")
            return
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create test PNG data")
            return
        }
        #endif

        let result = ImageLoader.downsampleImage(data: data, maxDimension: 2048, maxWidth: 600)
        #expect(result != nil, "Valid PNG data should produce an image")
        #expect(result!.size.width > 0)
        #expect(result!.size.height > 0)
    }

    // MARK: - ImageTextAttachment

    @Test("ImageTextAttachment has correct bounds")
    func attachmentBounds() {
        let size = CGSize(width: 100, height: 50)
        #if canImport(UIKit)
        let image = UIImage()
        #elseif canImport(AppKit)
        let image = NSImage()
        #endif

        let attachment = ImageTextAttachment(image: image, displaySize: size)

        let bounds = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 600, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )

        #expect(bounds.width == 100, "Attachment width should match display size")
        #expect(bounds.height == 50, "Attachment height should match display size")
    }

    @Test("ImageTextAttachment scales down when wider than container")
    func attachmentScalesDown() {
        let size = CGSize(width: 800, height: 400)
        #if canImport(UIKit)
        let image = UIImage()
        #elseif canImport(AppKit)
        let image = NSImage()
        #endif

        let attachment = ImageTextAttachment(image: image, displaySize: size)

        let containerWidth: CGFloat = 400
        let bounds = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: containerWidth, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )

        #expect(bounds.width == containerWidth, "Attachment should scale to container width")
        #expect(bounds.height == 200, "Attachment should preserve aspect ratio when scaling")
    }
}
