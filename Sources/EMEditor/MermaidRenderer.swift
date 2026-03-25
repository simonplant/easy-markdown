/// Mermaid diagram rendering prototype for SPIKE-006 per [A-006].
///
/// Renders Mermaid diagrams using mermaid.js in an offscreen WKWebView,
/// captures SVG output, converts to cached PlatformImage. Uses content hash
/// + theme ID for cache keying. Invalidates cache on theme change.
///
/// This is a spike prototype to validate the approach and measure memory impact.

import Foundation
import WebKit
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import CryptoKit

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "mermaid")

// MARK: - Mermaid Theme

/// Theme variant for Mermaid rendering, maps to mermaid.js built-in themes.
public enum MermaidTheme: String, Sendable {
    case light = "default"
    case dark = "dark"
}

// MARK: - Mermaid Render Result

/// Result of a Mermaid render operation.
/// `@unchecked Sendable` because PlatformImage is thread-safe for reading once created.
public enum MermaidRenderResult: @unchecked Sendable {
    case success(PlatformImage, CGSize)
    case failure(String)
}

// MARK: - Cache Entry

private final class MermaidCacheEntry: NSObject {
    let result: MermaidRenderResult
    let memoryCost: Int

    init(result: MermaidRenderResult, memoryCost: Int) {
        self.result = result
        self.memoryCost = memoryCost
    }
}

// MARK: - WKWebView Lifecycle Strategy

/// Strategy for managing the offscreen WKWebView lifecycle per SPIKE-006.
public enum WebViewLifecycle: Sendable {
    /// Create a new WKWebView for each render, destroy after capture.
    case createDestroy
    /// Reuse a single WKWebView across renders.
    case reuse
}

// MARK: - Mermaid Renderer

/// Renders Mermaid diagrams via offscreen WKWebView and caches results.
///
/// Usage:
/// ```swift
/// let renderer = MermaidRenderer()
/// let result = await renderer.render(mermaidSource: "graph TD; A-->B;", theme: .light)
/// ```
@MainActor
public final class MermaidRenderer {

    /// Cache for rendered diagram images. Thread-safe via NSCache.
    /// 30MB cost limit — diagrams are typically smaller than photos.
    private let cache: NSCache<NSString, MermaidCacheEntry>

    /// Reusable WKWebView (when using .reuse lifecycle).
    private var webView: WKWebView?

    /// The lifecycle strategy for the offscreen WKWebView.
    public let lifecycle: WebViewLifecycle

    /// Tracks in-flight renders to avoid duplicate work.
    private var inFlightKeys: Set<String> = []

    /// Callback invoked when a diagram finishes rendering.
    public var onDiagramRendered: ((String) -> Void)?

    /// Memory tracking for SPIKE-006 benchmarks.
    public private(set) var renderCount: Int = 0
    public private(set) var cacheHitCount: Int = 0
    public private(set) var cacheMissCount: Int = 0

    /// Loads the bundled mermaid.min.js source from Bundle.module.
    private static let mermaidJSSource: String = {
        guard let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js") else {
            logger.error("mermaid.min.js not found in bundle resources")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.error("Failed to read mermaid.min.js: \(error.localizedDescription)")
            return ""
        }
    }()

    /// The HTML template with mermaid.js for rendering diagrams.
    private static let htmlTemplate: String = {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { margin: 0; padding: 0; background: transparent; }
            #container { display: inline-block; }
            .mermaid svg { max-width: 100%; }
        </style>
        <script>\(mermaidJSSource)</script>
        </head>
        <body>
        <div id="container">
            <pre class="mermaid" id="diagram">MERMAID_CONTENT</pre>
        </div>
        <script>
            async function renderDiagram(theme) {
                mermaid.initialize({
                    startOnLoad: false,
                    theme: theme,
                    securityLevel: 'strict',
                    flowchart: { useMaxWidth: true },
                    sequence: { useMaxWidth: true }
                });
                try {
                    const { svg } = await mermaid.render('rendered', document.getElementById('diagram').textContent);
                    document.getElementById('container').innerHTML = svg;
                    // Return dimensions
                    const svgEl = document.querySelector('svg');
                    if (svgEl) {
                        const rect = svgEl.getBoundingClientRect();
                        return JSON.stringify({
                            success: true,
                            width: rect.width,
                            height: rect.height
                        });
                    }
                    return JSON.stringify({ success: true, width: 400, height: 300 });
                } catch (e) {
                    return JSON.stringify({ success: false, error: e.message });
                }
            }
        </script>
        </body>
        </html>
        """
    }()

    public init(lifecycle: WebViewLifecycle = .reuse, cacheLimitMB: Int = 30) {
        self.lifecycle = lifecycle
        cache = NSCache<NSString, MermaidCacheEntry>()
        cache.name = "com.easymarkdown.mermaid"
        cache.totalCostLimit = cacheLimitMB * 1024 * 1024

        if lifecycle == .reuse {
            webView = Self.createWebView()
        }
    }

    // MARK: - Public API

    /// Renders a Mermaid diagram and returns the result.
    ///
    /// - Parameters:
    ///   - mermaidSource: The raw Mermaid diagram source code.
    ///   - theme: The theme variant for rendering.
    ///   - scale: The scale factor for rasterization (e.g., 2.0 for Retina).
    /// - Returns: The render result with image and size, or failure with error message.
    public func render(
        mermaidSource: String,
        theme: MermaidTheme,
        scale: CGFloat = 2.0
    ) async -> MermaidRenderResult {
        renderCount += 1

        let cacheKey = Self.cacheKeyString(content: mermaidSource, theme: theme)

        // Check cache
        if let entry = cache.object(forKey: cacheKey as NSString) {
            cacheHitCount += 1
            logger.debug("Mermaid cache hit for key: \(cacheKey.prefix(16))")
            return entry.result
        }

        cacheMissCount += 1

        // Deduplicate in-flight renders
        guard !inFlightKeys.contains(cacheKey) else {
            logger.debug("Mermaid render already in-flight: \(cacheKey.prefix(16))")
            return .failure("Render already in progress")
        }
        inFlightKeys.insert(cacheKey)

        defer { inFlightKeys.remove(cacheKey) }

        // Render via WKWebView
        let result = await renderInWebView(
            mermaidSource: mermaidSource,
            theme: theme,
            scale: scale
        )

        // Cache successful results
        if case .success(let image, _) = result {
            let cost = Self.estimateMemoryCost(image)
            let entry = MermaidCacheEntry(result: result, memoryCost: cost)
            cache.setObject(entry, forKey: cacheKey as NSString, cost: cost)
            logger.debug("Mermaid cached: \(cacheKey.prefix(16)), cost: \(cost) bytes")
        }

        onDiagramRendered?(cacheKey)
        return result
    }

    /// Returns a cached render result if available.
    public func cachedResult(for mermaidSource: String, theme: MermaidTheme) -> MermaidRenderResult? {
        let cacheKey = Self.cacheKeyString(content: mermaidSource, theme: theme)
        return cache.object(forKey: cacheKey as NSString)?.result
    }

    /// Invalidates all cached renders. Called on theme change.
    public func invalidateCache() {
        cache.removeAllObjects()
        logger.info("Mermaid cache invalidated")
    }

    /// Invalidates cached renders for a specific content string (both themes).
    public func invalidate(content: String) {
        for theme in [MermaidTheme.light, .dark] {
            let key = Self.cacheKeyString(content: content, theme: theme)
            cache.removeObject(forKey: key as NSString)
        }
    }

    /// Resets benchmark counters.
    public func resetBenchmarkCounters() {
        renderCount = 0
        cacheHitCount = 0
        cacheMissCount = 0
    }

    // MARK: - Process Termination Recovery

    /// Handles WKWebView content process termination by clearing the web view
    /// so the next render() call recreates it via createWebView().
    private func handleProcessTermination() {
        webView = nil
        logger.info("MermaidRenderer: webView cleared after process termination")
    }

    /// Simulates a WKWebView content process termination for testing.
    /// Sets webView to nil so the next render() recreates it.
    internal func simulateWebContentProcessTermination() {
        handleProcessTermination()
    }

    // MARK: - Internal Rendering

    private func renderInWebView(
        mermaidSource: String,
        theme: MermaidTheme,
        scale: CGFloat
    ) async -> MermaidRenderResult {
        let wv: WKWebView
        switch lifecycle {
        case .reuse:
            wv = webView ?? Self.createWebView()
            if webView == nil { webView = wv }
        case .createDestroy:
            wv = Self.createWebView()
        }

        // Escape content for HTML embedding
        let escaped = mermaidSource
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = Self.htmlTemplate.replacingOccurrences(of: "MERMAID_CONTENT", with: escaped)

        // Load HTML and wait for completion
        do {
            let loaded = await loadHTML(html, in: wv)
            guard loaded else {
                return .failure("Failed to load HTML in WKWebView")
            }

            // Call renderDiagram with theme
            let jsResult = try await wv.evaluateJavaScript(
                "renderDiagram('\(theme.rawValue)')"
            ) as? String ?? ""

            guard let data = jsResult.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool else {
                return .failure("Invalid render response")
            }

            if !success {
                let error = json["error"] as? String ?? "Unknown mermaid error"
                logger.warning("Mermaid render error: \(error)")
                return .failure(error)
            }

            let width = json["width"] as? CGFloat ?? 400
            _ = json["height"] as? CGFloat ?? 300

            // Capture the rendered SVG as an image
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: Double(width * scale))

            let image = try await wv.takeSnapshot(configuration: config)

            #if canImport(UIKit)
            let size = CGSize(width: image.size.width, height: image.size.height)
            #elseif canImport(AppKit)
            let size = image.size
            #endif

            if lifecycle == .createDestroy {
                // Let the web view be deallocated
            }

            return .success(image, size)
        } catch {
            logger.warning("Mermaid render failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    /// Loads HTML into the web view and waits for navigation to complete.
    private func loadHTML(_ html: String, in webView: WKWebView) async -> Bool {
        return await withCheckedContinuation { continuation in
            let delegate = NavigationDelegate { success in
                continuation.resume(returning: success)
            }
            delegate.onProcessTerminated = { [weak self] in
                self?.handleProcessTermination()
            }
            // Store delegate to keep it alive
            objc_setAssociatedObject(webView, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
            webView.navigationDelegate = delegate
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private static var delegateKey: UInt8 = 0

    // MARK: - WebView Factory

    private static func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        // Suppress media autoplay
        config.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #elseif canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    // MARK: - Cache Key Generation

    static func cacheKeyString(content: String, theme: MermaidTheme) -> String {
        let input = "\(theme.rawValue):\(content)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Memory Cost

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

    // MARK: - Memory Measurement (SPIKE-006)

    /// Measures the current memory footprint for benchmarking.
    /// Returns resident memory in bytes via `task_info`.
    public static func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

// MARK: - Navigation Delegate

/// Simple delegate to track WKWebView navigation completion.
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private let completion: (Bool) -> Void
    private var hasCompleted = false
    var onProcessTerminated: (() -> Void)?

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.warning("WKWebView content process terminated — will recreate on next render")
        onProcessTerminated?()
    }
}
