/// The Render transition animation per [A-020] and FEAT-014.
///
/// Snapshot-based Core Animation approach: captures the current text view state,
/// applies new rendering, then animates per-element layers from source to
/// destination positions using CASpringAnimation (~400ms, damping 0.8, response 0.4).
/// Instruments via os_signpost on `com.easymarkdown.render`.
///
/// Supports source→rich and rich→source transitions, rapid toggle cancellation,
/// empty/1-line documents, and file-open animation trigger.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import QuartzCore
#endif
import EMParser

// MARK: - Signpost Instrumentation

private let renderLog = OSLog(subsystem: "com.easymarkdown.render", category: .pointsOfInterest)

/// Signpost-based animation timing measurement per [A-058].
public struct RenderTransitionSignpost {

    private static let signpostID = OSSignpostID(log: renderLog)

    /// Mark the start of the render transition animation.
    public static func beginTransition() {
        os_signpost(.begin, log: renderLog, name: "TheRenderTransition", signpostID: signpostID)
    }

    /// Mark the end of the render transition animation.
    public static func endTransition() {
        os_signpost(.end, log: renderLog, name: "TheRenderTransition", signpostID: signpostID)
    }

    /// Mark the start of snapshot capture.
    public static func beginSnapshot() {
        os_signpost(.begin, log: renderLog, name: "SnapshotCapture", signpostID: signpostID)
    }

    /// Mark the end of snapshot capture.
    public static func endSnapshot() {
        os_signpost(.end, log: renderLog, name: "SnapshotCapture", signpostID: signpostID)
    }
}

// MARK: - Animation Configuration

/// Configuration for The Render transition animation per [A-020].
public struct RenderTransitionConfig: Sendable {
    /// Spring animation damping ratio (0..1). Default: 0.8 per [A-020].
    public let dampingRatio: CGFloat
    /// Spring animation response time in seconds. Default: 0.4 per [A-020].
    public let response: CGFloat
    /// Reduced Motion crossfade duration. Default: 0.2s per [D-A11Y-3].
    public let reducedMotionDuration: CGFloat

    /// Default configuration per [A-020].
    public static let standard = RenderTransitionConfig(
        dampingRatio: 0.8,
        response: 0.4,
        reducedMotionDuration: 0.2
    )

    public init(dampingRatio: CGFloat, response: CGFloat, reducedMotionDuration: CGFloat) {
        self.dampingRatio = dampingRatio
        self.response = response
        self.reducedMotionDuration = reducedMotionDuration
    }
}

// MARK: - Frame Rate Metrics

/// Frame rate metrics collected during an animation run.
public struct FrameRateMetrics: Sendable, CustomStringConvertible {
    /// Total animation duration in seconds.
    public let totalDuration: Double
    /// Number of frames rendered during the animation.
    public let frameCount: Int
    /// Individual frame intervals in seconds.
    public let frameIntervals: [Double]
    /// Device model identifier.
    public let deviceModel: String
    /// Number of lines in the test document.
    public let documentLineCount: Int
    /// Whether reduced motion was used.
    public let reducedMotion: Bool

    /// Average frames per second.
    public var averageFPS: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(frameCount) / totalDuration
    }

    /// Minimum instantaneous FPS (from the longest frame interval).
    public var minFPS: Double {
        guard let maxInterval = frameIntervals.max(), maxInterval > 0 else { return 0 }
        return 1.0 / maxInterval
    }

    /// Number of dropped frames (intervals > 16.67ms for 60fps, or > 8.33ms for 120fps).
    public func droppedFrames(targetFPS: Double) -> Int {
        let targetInterval = 1.0 / targetFPS
        return frameIntervals.filter { $0 > targetInterval * 1.5 }.count
    }

    /// Whether the animation meets the target frame rate.
    public func meetsTarget(fps: Double) -> Bool {
        averageFPS >= fps * 0.95 // Allow 5% tolerance
    }

    public var description: String {
        """
        Frame Rate Metrics (\(documentLineCount) lines, \(deviceModel)\(reducedMotion ? ", Reduced Motion" : ""))
        ─────────────────────────────────────────
        Duration:       \(String(format: "%.1f", totalDuration * 1000)) ms
        Frame count:    \(frameCount)
        Average FPS:    \(String(format: "%.1f", averageFPS))
        Min FPS:        \(String(format: "%.1f", minFPS))
        Dropped @120:   \(droppedFrames(targetFPS: 120))
        Dropped @60:    \(droppedFrames(targetFPS: 60))
        """
    }
}

// MARK: - Element Transition Descriptor

/// Describes an individual element transition within The Render animation.
/// Each element (heading marker, bold marker, etc.) has its own source and
/// destination state that the animation interpolates between.
public struct ElementTransition {
    /// The type of markdown element being transitioned.
    public enum ElementType: String, Sendable {
        case headingMarker     // # markers → scaled heading
        case boldMarker        // ** markers → bold text
        case italicMarker      // * markers → italic text
        case listMarker        // - markers → styled bullet
        case codeFence         // ``` → code block background
        case linkSyntax        // [text](url) → styled link
        case blockquoteMarker  // > → visual left border
    }

    /// The element type.
    public let type: ElementType
    /// Source frame (position before transition).
    public let sourceFrame: CGRect
    /// Destination frame (position after transition).
    public let destinationFrame: CGRect
    /// The snapshot layer for this element.
    public let snapshotLayer: CALayer
}

// MARK: - Transition Direction

/// Direction of The Render transition per FEAT-014.
public enum TransitionDirection: Sendable {
    /// Source view → Rich view (syntax chars shrink/dissolve).
    case sourceToRich
    /// Rich view → Source view (syntax chars appear/grow).
    case richToSource
}

// MARK: - Syntax Marker Descriptor

/// Describes a syntax marker's type and text range for element extraction.
public struct SyntaxMarkerDescriptor {
    /// The element type this marker represents.
    public let type: ElementTransition.ElementType
    /// The NSRange of the syntax characters in the text storage.
    public let range: NSRange
}

// MARK: - Render Element Extractor

/// Extracts syntax marker descriptors from a markdown AST for The Render animation.
/// Walks the AST and identifies all syntax characters (e.g., `#`, `**`, `- `, `` ``` ``)
/// that need animated transitions.
struct RenderElementExtractor {

    /// Extracts all syntax marker descriptors from the given AST.
    ///
    /// - Parameters:
    ///   - ast: The parsed markdown AST.
    ///   - sourceText: The raw markdown text.
    /// - Returns: Array of syntax marker descriptors with their text ranges.
    static func extract(from ast: MarkdownAST, sourceText: String) -> [SyntaxMarkerDescriptor] {
        guard !sourceText.isEmpty else { return [] }

        let lineOffsets = computeLineOffsets(in: sourceText)
        var markers: [SyntaxMarkerDescriptor] = []

        for block in ast.blocks {
            extractFromNode(block, sourceText: sourceText, lineOffsets: lineOffsets, markers: &markers)
        }

        return markers
    }

    // MARK: - AST Walking

    private static func extractFromNode(
        _ node: MarkdownNode,
        sourceText: String,
        lineOffsets: [Int],
        markers: inout [SyntaxMarkerDescriptor]
    ) {
        guard let range = node.range,
              let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) else {
            for child in node.children {
                extractFromNode(child, sourceText: sourceText, lineOffsets: lineOffsets, markers: &markers)
            }
            return
        }

        switch node.type {
        case .heading:
            if let prefixRange = matchPrefix("^#{1,6}\\s", in: nsRange, text: sourceText) {
                markers.append(SyntaxMarkerDescriptor(type: .headingMarker, range: prefixRange))
            }

        case .listItem:
            if let prefixRange = matchPrefix("^\\s*(?:[*\\-+]|\\d+[.)]) ", in: nsRange, text: sourceText) {
                markers.append(SyntaxMarkerDescriptor(type: .listMarker, range: prefixRange))
            }

        case .blockQuote:
            extractBlockquoteMarkers(nsRange: nsRange, sourceText: sourceText, markers: &markers)

        case .codeBlock:
            extractCodeFenceMarkers(nsRange: nsRange, sourceText: sourceText, markers: &markers)

        case .strong:
            if nsRange.length > 4 {
                markers.append(SyntaxMarkerDescriptor(
                    type: .boldMarker,
                    range: NSRange(location: nsRange.location, length: 2)
                ))
                markers.append(SyntaxMarkerDescriptor(
                    type: .boldMarker,
                    range: NSRange(location: nsRange.location + nsRange.length - 2, length: 2)
                ))
            }

        case .emphasis:
            if nsRange.length > 2 {
                markers.append(SyntaxMarkerDescriptor(
                    type: .italicMarker,
                    range: NSRange(location: nsRange.location, length: 1)
                ))
                markers.append(SyntaxMarkerDescriptor(
                    type: .italicMarker,
                    range: NSRange(location: nsRange.location + nsRange.length - 1, length: 1)
                ))
            }

        case .link:
            extractLinkSyntax(nsRange: nsRange, sourceText: sourceText, markers: &markers)

        default:
            break
        }

        for child in node.children {
            extractFromNode(child, sourceText: sourceText, lineOffsets: lineOffsets, markers: &markers)
        }
    }

    // MARK: - Element-Specific Extraction

    private static func matchPrefix(_ pattern: String, in nsRange: NSRange, text: String) -> NSRange? {
        let nsText = text as NSString
        let substring = nsText.substring(with: nsRange)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: substring,
                range: NSRange(location: 0, length: substring.utf16.count)
              ) else {
            return nil
        }
        return NSRange(location: nsRange.location + match.range.location, length: match.range.length)
    }

    private static func extractBlockquoteMarkers(
        nsRange: NSRange,
        sourceText: String,
        markers: inout [SyntaxMarkerDescriptor]
    ) {
        let nsText = sourceText as NSString
        let text = nsText.substring(with: nsRange)
        guard let regex = try? NSRegularExpression(
            pattern: "^\\s*>\\s?",
            options: .anchorsMatchLines
        ) else { return }

        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        for match in matches {
            markers.append(SyntaxMarkerDescriptor(
                type: .blockquoteMarker,
                range: NSRange(
                    location: nsRange.location + match.range.location,
                    length: match.range.length
                )
            ))
        }
    }

    private static func extractCodeFenceMarkers(
        nsRange: NSRange,
        sourceText: String,
        markers: inout [SyntaxMarkerDescriptor]
    ) {
        let nsText = sourceText as NSString
        let text = nsText.substring(with: nsRange)
        let lines = text.components(separatedBy: "\n")

        if let first = lines.first,
           first.hasPrefix("```") || first.hasPrefix("~~~") {
            markers.append(SyntaxMarkerDescriptor(
                type: .codeFence,
                range: NSRange(location: nsRange.location, length: first.utf16.count)
            ))
        }

        if lines.count > 1,
           let last = lines.last, !last.isEmpty,
           last.hasPrefix("```") || last.hasPrefix("~~~") {
            let lastOffset = nsRange.location + nsRange.length - last.utf16.count
            markers.append(SyntaxMarkerDescriptor(
                type: .codeFence,
                range: NSRange(location: lastOffset, length: last.utf16.count)
            ))
        }
    }

    private static func extractLinkSyntax(
        nsRange: NSRange,
        sourceText: String,
        markers: inout [SyntaxMarkerDescriptor]
    ) {
        let nsText = sourceText as NSString
        let text = nsText.substring(with: nsRange) as NSString

        guard text.hasPrefix("[") else { return }

        // Opening "["
        markers.append(SyntaxMarkerDescriptor(
            type: .linkSyntax,
            range: NSRange(location: nsRange.location, length: 1)
        ))

        // Find "](url)" suffix
        let closeBracketRange = text.range(of: "](")
        if closeBracketRange.location != NSNotFound {
            let suffixLength = nsRange.length - closeBracketRange.location
            if suffixLength > 0 {
                markers.append(SyntaxMarkerDescriptor(
                    type: .linkSyntax,
                    range: NSRange(
                        location: nsRange.location + closeBracketRange.location,
                        length: suffixLength
                    )
                ))
            }
        }
    }

    // MARK: - Range Conversion

    private static func computeLineOffsets(in text: String) -> [Int] {
        var offsets: [Int] = [0]
        var utf16Offset = 0
        for char in text {
            let charWidth = String(char).utf16.count
            utf16Offset += charWidth
            if char == "\n" {
                offsets.append(utf16Offset)
            }
        }
        return offsets
    }

    private static func nsRange(
        from sourceRange: SourceRange,
        in text: String,
        lineOffsets: [Int]
    ) -> NSRange? {
        let startLine = sourceRange.start.line - 1
        let endLine = sourceRange.end.line - 1

        guard startLine >= 0, startLine < lineOffsets.count,
              endLine >= 0, endLine < lineOffsets.count else {
            return nil
        }

        let startOffset = lineOffsets[startLine] + max(0, sourceRange.start.column - 1)
        let endOffset = lineOffsets[endLine] + max(0, sourceRange.end.column - 1)
        let length = endOffset - startOffset

        guard length >= 0, startOffset >= 0, endOffset <= text.utf16.count else {
            return nil
        }

        return NSRange(location: startOffset, length: length)
    }
}

// MARK: - Spring Parameter Computation

/// Computes CASpringAnimation parameters from response/damping config.
private func springParameters(config: RenderTransitionConfig) -> (mass: CGFloat, stiffness: CGFloat, damping: CGFloat) {
    let mass: CGFloat = 1.0
    let stiffness = pow(2.0 * .pi / config.response, 2) * mass
    let damping = 4.0 * .pi * config.dampingRatio * mass / config.response
    return (mass, stiffness, damping)
}

#if canImport(UIKit)

// MARK: - Render Transition Animator (iOS)

/// Orchestrates The Render transition animation using snapshot-based Core Animation per FEAT-014.
///
/// The production animation works by:
/// 1. Extracting syntax marker positions from the current layout
/// 2. Capturing a full snapshot of the text view
/// 3. Applying new rendering (source↔rich attribute switch)
/// 4. Computing destination positions from the new layout
/// 5. Animating per-element snapshot clips + full-view crossfade with CASpringAnimation
/// 6. On completion (or cancellation), removing overlay layers to show the live text view
@MainActor
public final class RenderTransitionAnimator {

    private let config: RenderTransitionConfig
    private var displayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private var animationStartTime: CFTimeInterval = 0

    /// The most recent frame rate metrics from an animation run.
    public private(set) var lastFrameMetrics: FrameRateMetrics?

    /// Whether a transition animation is currently in progress.
    public private(set) var isAnimating: Bool = false

    /// Active overlay layers (for cancellation on rapid toggle per FEAT-014 AC-10).
    private var activeOverlayLayers: [CALayer] = []

    /// Reference to the text view being animated (for scroll lock/unlock).
    private weak var animatingTextView: UITextView?

    /// Creates a transition animator with the given configuration.
    ///
    /// - Parameter config: Animation parameters. Defaults to [A-020] standard values.
    public init(config: RenderTransitionConfig = .standard) {
        self.config = config
    }

    // MARK: - Production Transition per FEAT-014

    /// Performs The Render transition on a real text view.
    ///
    /// Captures the current view state, applies new rendering via the provided
    /// closure, then animates syntax elements from old to new positions.
    /// Handles Reduced Motion, rapid toggle cancellation, and empty documents.
    ///
    /// - Parameters:
    ///   - textView: The text view being transitioned.
    ///   - markers: Syntax marker descriptors extracted from the AST.
    ///   - applyRendering: Closure that switches the text view's rendering mode.
    ///   - direction: Whether transitioning source→rich or rich→source.
    ///   - completion: Called when the animation finishes or is cancelled.
    public func performTransition(
        textView: UITextView,
        markers: [SyntaxMarkerDescriptor],
        applyRendering: () -> Void,
        direction: TransitionDirection,
        completion: @escaping () -> Void
    ) {
        // Cancel any in-flight animation per FEAT-014 AC-10
        if isAnimating {
            cancelAnimation()
        }

        // Empty documents: instant switch per FEAT-014 AC-9
        guard !markers.isEmpty else {
            applyRendering()
            completion()
            return
        }

        let reducedMotion = UIAccessibility.isReduceMotionEnabled

        isAnimating = true
        animatingTextView = textView
        textView.isScrollEnabled = false
        RenderTransitionSignpost.beginTransition()
        RenderTransitionSignpost.beginSnapshot()

        // 1. Get source rects from current layout
        let sourceRects = markers.map { rectForRange($0.range, in: textView) }

        // 2. Capture snapshot of current visual state (used as full overlay crossfade)
        let preChangeSnapshot = captureSnapshot(of: textView)

        RenderTransitionSignpost.endSnapshot()

        // 3. Apply new rendering (attribute switch)
        applyRendering()
        textView.layoutIfNeeded()

        // 4. Get destination rects from new layout
        let destRects = markers.map { rectForRange($0.range, in: textView) }

        // 5. For reverse animation (rich→source), capture post-change snapshot
        //    so element clips show the visible syntax markers per FEAT-014 AC-7.
        let elementClipSnapshot: CGImage?
        let clipSourceRects: [CGRect?]
        if direction == .richToSource {
            elementClipSnapshot = captureSnapshot(of: textView)
            clipSourceRects = destRects // Use new (source) positions for clipping
        } else {
            elementClipSnapshot = preChangeSnapshot
            clipSourceRects = sourceRects // Use old (source) positions for clipping
        }

        // 6. Build per-element transitions with snapshot clips
        let viewSize = textView.bounds.size
        let contentOffset = textView.contentOffset
        let visibleRect = CGRect(origin: contentOffset, size: viewSize)

        var elements: [ElementTransition] = []

        for i in 0..<markers.count {
            guard let srcContent = sourceRects[i], let dstContent = destRects[i],
                  visibleRect.intersects(srcContent) || visibleRect.intersects(dstContent) else {
                continue
            }

            // Convert content coordinates to layer coordinates
            let src = srcContent.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
            let dst = dstContent.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)

            // Ensure collapsed markers have minimum size for animation visibility
            let safeDst = CGRect(
                x: dst.minX, y: dst.minY,
                width: max(dst.width, 0.5), height: max(dst.height, src.height * 0.1)
            )

            let layer = CALayer()
            if let clipImage = elementClipSnapshot,
               let clipRect = clipSourceRects[i] {
                let clipLayer = clipRect.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
                layer.contents = clipImage
                layer.contentsRect = CGRect(
                    x: max(0, clipLayer.minX / viewSize.width),
                    y: max(0, clipLayer.minY / viewSize.height),
                    width: min(1, max(clipLayer.width, 1) / viewSize.width),
                    height: min(1, max(clipLayer.height, 1) / viewSize.height)
                )
            } else {
                layer.backgroundColor = UIColor.label.withAlphaComponent(0.3).cgColor
                layer.cornerRadius = 2
            }

            let sourceFrame = direction == .sourceToRich ? src : safeDst
            let destFrame = direction == .sourceToRich ? safeDst : src

            elements.append(ElementTransition(
                type: markers[i].type,
                sourceFrame: sourceFrame,
                destinationFrame: destFrame,
                snapshotLayer: layer
            ))
        }

        // 6. Add full-view snapshot overlay for smooth crossfade base
        let fullOverlay = CALayer()
        if let image = preChangeSnapshot {
            fullOverlay.contents = image
        }
        fullOverlay.frame = CGRect(origin: .zero, size: viewSize)
        textView.layer.addSublayer(fullOverlay)

        // 7. Start frame tracking and animate
        startFrameTracking()
        let lineCount = (textView.text ?? "").filter({ $0 == "\n" }).count + 1

        if reducedMotion {
            activeOverlayLayers = [fullOverlay]
            animateReducedMotionTransition(
                fullOverlay: fullOverlay,
                lineCount: lineCount,
                completion: completion
            )
        } else {
            let elementLayers = elements.map { element -> CALayer in
                let layer = element.snapshotLayer
                layer.frame = element.sourceFrame
                textView.layer.addSublayer(layer)
                return layer
            }
            activeOverlayLayers = [fullOverlay] + elementLayers

            animateSpringTransition(
                fullOverlay: fullOverlay,
                elements: elements,
                elementLayers: elementLayers,
                direction: direction,
                lineCount: lineCount,
                completion: completion
            )
        }
    }

    /// Cancels any in-flight animation immediately per FEAT-014 AC-10.
    /// Removes all overlay layers and restores the text view to its live state.
    public func cancelAnimation() {
        guard isAnimating else { return }
        isAnimating = false

        for layer in activeOverlayLayers {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
        activeOverlayLayers = []

        animatingTextView?.isScrollEnabled = true
        animatingTextView = nil

        displayLink?.invalidate()
        displayLink = nil
        RenderTransitionSignpost.endTransition()
    }

    // MARK: - Production Spring Animation

    private func animateSpringTransition(
        fullOverlay: CALayer,
        elements: [ElementTransition],
        elementLayers: [CALayer],
        direction: TransitionDirection,
        lineCount: Int,
        completion: @escaping () -> Void
    ) {
        let (mass, stiffness, damping) = springParameters(config: config)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.finishAnimation(lineCount: lineCount, reducedMotion: false)
            completion()
        }

        // Full overlay crossfade
        let overlayFade = CASpringAnimation(keyPath: "opacity")
        overlayFade.fromValue = 1.0
        overlayFade.toValue = 0.0
        overlayFade.mass = mass
        overlayFade.stiffness = stiffness
        overlayFade.damping = damping
        overlayFade.initialVelocity = 0
        fullOverlay.add(overlayFade, forKey: "opacity")
        fullOverlay.opacity = 0.0

        // Per-element animations
        for (index, element) in elements.enumerated() {
            let layer = elementLayers[index]

            // Position
            let posAnim = CASpringAnimation(keyPath: "position")
            posAnim.fromValue = NSValue(cgPoint: CGPoint(
                x: element.sourceFrame.midX, y: element.sourceFrame.midY
            ))
            posAnim.toValue = NSValue(cgPoint: CGPoint(
                x: element.destinationFrame.midX, y: element.destinationFrame.midY
            ))
            posAnim.mass = mass
            posAnim.stiffness = stiffness
            posAnim.damping = damping
            posAnim.initialVelocity = 0

            // Bounds
            let sizeAnim = CASpringAnimation(keyPath: "bounds.size")
            sizeAnim.fromValue = NSValue(cgSize: element.sourceFrame.size)
            sizeAnim.toValue = NSValue(cgSize: element.destinationFrame.size)
            sizeAnim.mass = mass
            sizeAnim.stiffness = stiffness
            sizeAnim.damping = damping
            sizeAnim.initialVelocity = 0

            // Opacity: syntax markers dissolve forward, appear reverse
            switch element.type {
            case .headingMarker, .boldMarker, .italicMarker, .codeFence, .linkSyntax:
                let opacityAnim = CASpringAnimation(keyPath: "opacity")
                let (fromVal, toVal): (Float, Float) = direction == .sourceToRich
                    ? (1.0, 0.0) : (0.0, 1.0)
                opacityAnim.fromValue = fromVal
                opacityAnim.toValue = toVal
                opacityAnim.mass = mass
                opacityAnim.stiffness = stiffness
                opacityAnim.damping = damping
                opacityAnim.initialVelocity = 0
                layer.add(opacityAnim, forKey: "opacity")
                layer.opacity = toVal

            case .listMarker, .blockquoteMarker:
                // Morph in place (position + style), no opacity change
                break
            }

            layer.add(posAnim, forKey: "position")
            layer.add(sizeAnim, forKey: "bounds")
            layer.position = CGPoint(
                x: element.destinationFrame.midX,
                y: element.destinationFrame.midY
            )
            layer.bounds.size = element.destinationFrame.size
        }

        CATransaction.commit()
    }

    // MARK: - Production Reduced Motion

    private func animateReducedMotionTransition(
        fullOverlay: CALayer,
        lineCount: Int,
        completion: @escaping () -> Void
    ) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.finishAnimation(lineCount: lineCount, reducedMotion: true)
            completion()
        }

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = config.reducedMotionDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fullOverlay.add(fadeOut, forKey: "opacity")
        fullOverlay.opacity = 0.0

        CATransaction.commit()
    }

    // MARK: - Animation Lifecycle

    private func finishAnimation(lineCount: Int, reducedMotion: Bool) {
        guard isAnimating else { return }

        for layer in activeOverlayLayers {
            layer.removeFromSuperlayer()
        }
        activeOverlayLayers = []

        animatingTextView?.isScrollEnabled = true
        animatingTextView = nil

        lastFrameMetrics = stopFrameTracking(
            documentLineCount: lineCount,
            reducedMotion: reducedMotion
        )
        isAnimating = false
        RenderTransitionSignpost.endTransition()
    }

    // MARK: - Helpers

    private func rectForRange(_ range: NSRange, in textView: UITextView) -> CGRect? {
        guard range.length > 0,
              let start = textView.position(
                from: textView.beginningOfDocument, offset: range.location
              ),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else {
            return nil
        }
        let rect = textView.firstRect(for: textRange)
        guard !rect.isNull, !rect.isInfinite else { return nil }
        return rect
    }

    private func captureSnapshot(of textView: UIView) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: textView.bounds.size)
        let image = renderer.image { _ in
            textView.layer.render(in: UIGraphicsGetCurrentContext()!)
        }
        return image.cgImage
    }

    // MARK: - Benchmark Animation (from SPIKE-004)

    /// Performs The Render animation with synthetic elements for benchmarking.
    ///
    /// - Parameters:
    ///   - containerView: The view to animate within.
    ///   - elements: Element transitions describing source→destination positions.
    ///   - reducedMotion: If true, uses a 200ms crossfade instead of spring animation.
    ///   - completion: Called when the animation finishes.
    public func animate(
        in containerView: UIView,
        elements: [ElementTransition],
        reducedMotion: Bool,
        completion: @escaping (FrameRateMetrics) -> Void
    ) {
        RenderTransitionSignpost.beginTransition()
        startFrameTracking()

        let overlayLayers: [CALayer] = elements.map { element in
            let layer = element.snapshotLayer
            layer.frame = element.sourceFrame
            containerView.layer.addSublayer(layer)
            return layer
        }

        let (mass, stiffness, damping) = springParameters(config: config)

        if reducedMotion {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self else { return }
                for layer in overlayLayers { layer.removeFromSuperlayer() }
                let metrics = self.stopFrameTracking(documentLineCount: 0, reducedMotion: true)
                RenderTransitionSignpost.endTransition()
                completion(metrics)
            }
            for layer in overlayLayers {
                let fadeOut = CABasicAnimation(keyPath: "opacity")
                fadeOut.fromValue = 1.0
                fadeOut.toValue = 0.0
                fadeOut.duration = config.reducedMotionDuration
                fadeOut.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(fadeOut, forKey: "opacity")
                layer.opacity = 0.0
            }
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self else { return }
                for layer in overlayLayers { layer.removeFromSuperlayer() }
                let metrics = self.stopFrameTracking(documentLineCount: 0, reducedMotion: false)
                RenderTransitionSignpost.endTransition()
                completion(metrics)
            }

            for (index, element) in elements.enumerated() {
                let layer = overlayLayers[index]

                let positionAnim = CASpringAnimation(keyPath: "position")
                positionAnim.fromValue = NSValue(cgPoint: CGPoint(
                    x: element.sourceFrame.midX, y: element.sourceFrame.midY
                ))
                positionAnim.toValue = NSValue(cgPoint: CGPoint(
                    x: element.destinationFrame.midX, y: element.destinationFrame.midY
                ))
                positionAnim.mass = mass
                positionAnim.stiffness = stiffness
                positionAnim.damping = damping
                positionAnim.initialVelocity = 0

                let boundsAnim = CASpringAnimation(keyPath: "bounds.size")
                boundsAnim.fromValue = NSValue(cgSize: element.sourceFrame.size)
                boundsAnim.toValue = NSValue(cgSize: element.destinationFrame.size)
                boundsAnim.mass = mass
                boundsAnim.stiffness = stiffness
                boundsAnim.damping = damping
                boundsAnim.initialVelocity = 0

                switch element.type {
                case .headingMarker, .boldMarker, .italicMarker, .codeFence, .linkSyntax:
                    let opacityAnim = CASpringAnimation(keyPath: "opacity")
                    opacityAnim.fromValue = 1.0
                    opacityAnim.toValue = 0.0
                    opacityAnim.mass = mass
                    opacityAnim.stiffness = stiffness
                    opacityAnim.damping = damping
                    opacityAnim.initialVelocity = 0
                    layer.add(opacityAnim, forKey: "opacity")
                    layer.opacity = 0.0

                case .listMarker, .blockquoteMarker:
                    break
                }

                layer.add(positionAnim, forKey: "position")
                layer.add(boundsAnim, forKey: "bounds")
                layer.position = CGPoint(
                    x: element.destinationFrame.midX,
                    y: element.destinationFrame.midY
                )
                layer.bounds.size = element.destinationFrame.size
            }

            CATransaction.commit()
        }
    }

    // MARK: - Frame Tracking via CADisplayLink

    private func startFrameTracking() {
        frameTimestamps.removeAll()
        frameTimestamps.reserveCapacity(200)
        animationStartTime = CACurrentMediaTime()

        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60, maximum: 120, preferred: 120
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopFrameTracking(documentLineCount: Int, reducedMotion: Bool) -> FrameRateMetrics {
        displayLink?.invalidate()
        displayLink = nil

        let endTime = CACurrentMediaTime()
        let totalDuration = endTime - animationStartTime

        var intervals: [Double] = []
        for i in 1..<frameTimestamps.count {
            intervals.append(frameTimestamps[i] - frameTimestamps[i - 1])
        }

        return FrameRateMetrics(
            totalDuration: totalDuration,
            frameCount: frameTimestamps.count,
            frameIntervals: intervals,
            deviceModel: deviceModelIdentifier(),
            documentLineCount: documentLineCount,
            reducedMotion: reducedMotion
        )
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        frameTimestamps.append(link.timestamp)
    }

    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - Benchmark Runner

/// Runs The Render animation benchmark with varying document sizes.
@MainActor
public final class RenderTransitionBenchmark {

    public static let defaultDocumentSizes = [10, 100, 1000]

    private let animator: RenderTransitionAnimator

    public init(config: RenderTransitionConfig = .standard) {
        self.animator = RenderTransitionAnimator(config: config)
    }

    public func runBenchmark(
        in containerView: UIView,
        lineCount: Int,
        reducedMotion: Bool = false
    ) async -> FrameRateMetrics {
        let elements = generateSyntheticElements(
            lineCount: lineCount,
            containerWidth: containerView.bounds.width
        )

        return await withCheckedContinuation { continuation in
            animator.animate(
                in: containerView,
                elements: elements,
                reducedMotion: reducedMotion
            ) { metrics in
                let patched = FrameRateMetrics(
                    totalDuration: metrics.totalDuration,
                    frameCount: metrics.frameCount,
                    frameIntervals: metrics.frameIntervals,
                    deviceModel: metrics.deviceModel,
                    documentLineCount: lineCount,
                    reducedMotion: reducedMotion
                )
                continuation.resume(returning: patched)
            }
        }
    }

    private func generateSyntheticElements(
        lineCount: Int,
        containerWidth: CGFloat
    ) -> [ElementTransition] {
        var elements: [ElementTransition] = []
        let lineHeight: CGFloat = 22.0
        let headingHeight: CGFloat = 32.0

        RenderTransitionSignpost.beginSnapshot()

        let headingCount = max(1, lineCount / 10)
        for i in 0..<headingCount {
            let yPosition = CGFloat(i * 10) * lineHeight
            let sourceFrame = CGRect(x: 16, y: yPosition, width: 24, height: lineHeight)
            let destFrame = CGRect(x: 16, y: yPosition, width: containerWidth - 32, height: headingHeight)

            let layer = CALayer()
            layer.backgroundColor = UIColor.label.cgColor
            layer.cornerRadius = 2

            elements.append(ElementTransition(
                type: .headingMarker,
                sourceFrame: sourceFrame,
                destinationFrame: destFrame,
                snapshotLayer: layer
            ))
        }

        let boldCount = max(1, lineCount / 5)
        for i in 0..<boldCount {
            let yPosition = CGFloat(i * 5) * lineHeight + lineHeight * 0.5
            let sourceFrame = CGRect(x: 40, y: yPosition, width: 16, height: lineHeight)
            let destFrame = CGRect(x: 40, y: yPosition, width: 16, height: lineHeight)

            let layer = CALayer()
            layer.backgroundColor = UIColor.secondaryLabel.cgColor
            layer.cornerRadius = 1

            elements.append(ElementTransition(
                type: .boldMarker,
                sourceFrame: sourceFrame,
                destinationFrame: destFrame,
                snapshotLayer: layer
            ))
        }

        let listCount = max(1, lineCount * 15 / 100)
        for i in 0..<listCount {
            let yPosition = CGFloat(i * 7) * lineHeight + lineHeight * 3
            let sourceFrame = CGRect(x: 16, y: yPosition, width: 12, height: lineHeight)
            let destFrame = CGRect(x: 20, y: yPosition + 2, width: 8, height: 8)

            let layer = CALayer()
            layer.backgroundColor = UIColor.tertiaryLabel.cgColor
            layer.cornerRadius = 4

            elements.append(ElementTransition(
                type: .listMarker,
                sourceFrame: sourceFrame,
                destinationFrame: destFrame,
                snapshotLayer: layer
            ))
        }

        RenderTransitionSignpost.endSnapshot()

        return elements
    }
}

// MARK: - Benchmark View Controller

/// Standalone view controller for running SPIKE-004 animation benchmarks.
public final class RenderBenchmarkViewController: UIViewController {

    private var containerView: UIView!
    private var resultsLabel: UILabel!
    private var runButton: UIButton!
    private var activityIndicator: UIActivityIndicatorView!
    private let documentSizes = RenderTransitionBenchmark.defaultDocumentSizes

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "SPIKE-004: The Render Animation"
        view.backgroundColor = .systemBackground

        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .secondarySystemBackground
        containerView.clipsToBounds = true
        view.addSubview(containerView)

        resultsLabel = UILabel()
        resultsLabel.translatesAutoresizingMaskIntoConstraints = false
        resultsLabel.numberOfLines = 0
        resultsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        resultsLabel.textColor = .secondaryLabel
        view.addSubview(resultsLabel)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        runButton = UIButton(type: .system)
        runButton.translatesAutoresizingMaskIntoConstraints = false
        runButton.setTitle("Run Benchmark (10, 100, 1000 lines)", for: .normal)
        runButton.addTarget(self, action: #selector(runBenchmarkTapped), for: .touchUpInside)
        view.addSubview(runButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            containerView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),

            runButton.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 16),
            runButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            activityIndicator.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            activityIndicator.leadingAnchor.constraint(equalTo: runButton.trailingAnchor, constant: 8),

            resultsLabel.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 16),
            resultsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resultsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resultsLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    @objc private func runBenchmarkTapped() {
        runButton.isEnabled = false
        activityIndicator.startAnimating()
        resultsLabel.text = "Running benchmarks..."

        Task { @MainActor in
            let benchmark = RenderTransitionBenchmark()
            var resultLines: [String] = []

            for size in documentSizes {
                let metrics = await benchmark.runBenchmark(
                    in: containerView,
                    lineCount: size
                )
                resultLines.append(metrics.description)
                resultLines.append("")
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            let reducedMetrics = await benchmark.runBenchmark(
                in: containerView,
                lineCount: 100,
                reducedMotion: true
            )
            resultLines.append(reducedMetrics.description)

            resultsLabel.text = resultLines.joined(separator: "\n")
            runButton.isEnabled = true
            activityIndicator.stopAnimating()

            let logger = Logger(subsystem: "com.easymarkdown.render", category: "benchmark")
            for line in resultLines {
                logger.info("\(line)")
            }
        }
    }
}

#elseif canImport(AppKit)

// MARK: - Render Transition Animator (macOS)

/// macOS implementation of The Render transition animator per FEAT-014.
///
/// Uses Core Animation (shared with iOS) for the animation pipeline.
@MainActor
public final class RenderTransitionAnimator {

    private let config: RenderTransitionConfig

    /// The most recent frame rate metrics from an animation run.
    public private(set) var lastFrameMetrics: FrameRateMetrics?

    /// Whether a transition animation is currently in progress.
    public private(set) var isAnimating: Bool = false

    /// Active overlay layers for cancellation.
    private var activeOverlayLayers: [CALayer] = []

    /// Creates a transition animator with the given configuration.
    public init(config: RenderTransitionConfig = .standard) {
        self.config = config
    }

    // MARK: - Production Transition per FEAT-014

    /// Performs The Render transition on a real text view (macOS).
    public func performTransition(
        textView: NSTextView,
        markers: [SyntaxMarkerDescriptor],
        applyRendering: () -> Void,
        direction: TransitionDirection,
        completion: @escaping () -> Void
    ) {
        if isAnimating { cancelAnimation() }

        guard !markers.isEmpty else {
            applyRendering()
            completion()
            return
        }

        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        isAnimating = true
        textView.wantsLayer = true
        guard let hostLayer = textView.layer else {
            applyRendering()
            isAnimating = false
            completion()
            return
        }

        RenderTransitionSignpost.beginTransition()
        RenderTransitionSignpost.beginSnapshot()

        // 1. Get source rects
        let sourceRects = markers.map { rectForRange($0.range, in: textView) }

        // 2. Capture snapshot
        let snapshotImage = captureSnapshot(of: textView)

        RenderTransitionSignpost.endSnapshot()

        // 3. Apply new rendering
        applyRendering()
        textView.layoutManager?.ensureLayout(forCharacterRange: NSRange(
            location: 0,
            length: (textView.string as NSString).length
        ))

        // 4. Get destination rects
        let destRects = markers.map { rectForRange($0.range, in: textView) }

        // 5. For reverse animation (rich→source), capture post-change snapshot
        //    so element clips show the visible syntax markers per FEAT-014 AC-7.
        let elementClipSnapshot: CGImage?
        let clipSourceRects: [CGRect?]
        if direction == .richToSource {
            elementClipSnapshot = captureSnapshot(of: textView)
            clipSourceRects = destRects // Use new (source) positions for clipping
        } else {
            elementClipSnapshot = snapshotImage
            clipSourceRects = sourceRects // Use old (source) positions for clipping
        }

        // 6. Build elements
        let viewSize = textView.bounds.size
        let visibleRect = textView.visibleRect

        var elements: [ElementTransition] = []

        for i in 0..<markers.count {
            guard let src = sourceRects[i], let dst = destRects[i],
                  visibleRect.intersects(src) || visibleRect.intersects(dst) else {
                continue
            }

            // Convert to layer coordinates (flip Y for AppKit)
            let layerSrc = CGRect(
                x: src.minX - visibleRect.minX,
                y: viewSize.height - (src.minY - visibleRect.minY) - src.height,
                width: src.width, height: src.height
            )
            let safeDst = CGRect(
                x: dst.minX - visibleRect.minX,
                y: viewSize.height - (dst.minY - visibleRect.minY) - max(dst.height, src.height * 0.1),
                width: max(dst.width, 0.5),
                height: max(dst.height, src.height * 0.1)
            )

            let layer = CALayer()
            if let clipImage = elementClipSnapshot,
               let clipRect = clipSourceRects[i] {
                // Use clip snapshot rects for contentsRect
                layer.contents = clipImage
                layer.contentsRect = CGRect(
                    x: max(0, (clipRect.minX - visibleRect.minX) / viewSize.width),
                    y: max(0, (clipRect.minY - visibleRect.minY) / viewSize.height),
                    width: min(1, max(clipRect.width, 1) / viewSize.width),
                    height: min(1, max(clipRect.height, 1) / viewSize.height)
                )
            } else {
                layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.3).cgColor
                layer.cornerRadius = 2
            }

            let sourceFrame = direction == .sourceToRich ? layerSrc : safeDst
            let destFrame = direction == .sourceToRich ? safeDst : layerSrc

            elements.append(ElementTransition(
                type: markers[i].type,
                sourceFrame: sourceFrame,
                destinationFrame: destFrame,
                snapshotLayer: layer
            ))
        }

        // 6. Full overlay
        let fullOverlay = CALayer()
        if let image = snapshotImage {
            fullOverlay.contents = image
        }
        fullOverlay.frame = CGRect(origin: .zero, size: viewSize)
        hostLayer.addSublayer(fullOverlay)

        let lineCount = textView.string.filter({ $0 == "\n" }).count + 1

        if reducedMotion {
            activeOverlayLayers = [fullOverlay]
            let startTime = CACurrentMediaTime()

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                self?.finishMacOSAnimation(
                    startTime: startTime, lineCount: lineCount, reducedMotion: true
                )
                completion()
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = config.reducedMotionDuration
            fullOverlay.add(fade, forKey: "opacity")
            fullOverlay.opacity = 0.0
            CATransaction.commit()
        } else {
            let elementLayers = elements.map { element -> CALayer in
                let layer = element.snapshotLayer
                layer.frame = element.sourceFrame
                hostLayer.addSublayer(layer)
                return layer
            }
            activeOverlayLayers = [fullOverlay] + elementLayers

            let startTime = CACurrentMediaTime()
            let (mass, stiffness, damping) = springParameters(config: config)

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                self?.finishMacOSAnimation(
                    startTime: startTime, lineCount: lineCount, reducedMotion: false
                )
                completion()
            }

            // Full overlay fade
            let overlayFade = CASpringAnimation(keyPath: "opacity")
            overlayFade.fromValue = 1.0
            overlayFade.toValue = 0.0
            overlayFade.mass = mass
            overlayFade.stiffness = stiffness
            overlayFade.damping = damping
            overlayFade.initialVelocity = 0
            fullOverlay.add(overlayFade, forKey: "opacity")
            fullOverlay.opacity = 0.0

            for (index, element) in elements.enumerated() {
                let layer = elementLayers[index]

                let posAnim = CASpringAnimation(keyPath: "position")
                posAnim.fromValue = NSValue(point: NSPoint(
                    x: element.sourceFrame.midX, y: element.sourceFrame.midY
                ))
                posAnim.toValue = NSValue(point: NSPoint(
                    x: element.destinationFrame.midX, y: element.destinationFrame.midY
                ))
                posAnim.mass = mass
                posAnim.stiffness = stiffness
                posAnim.damping = damping
                posAnim.initialVelocity = 0

                let sizeAnim = CASpringAnimation(keyPath: "bounds.size")
                sizeAnim.fromValue = NSValue(size: element.sourceFrame.size)
                sizeAnim.toValue = NSValue(size: element.destinationFrame.size)
                sizeAnim.mass = mass
                sizeAnim.stiffness = stiffness
                sizeAnim.damping = damping
                sizeAnim.initialVelocity = 0

                switch element.type {
                case .headingMarker, .boldMarker, .italicMarker, .codeFence, .linkSyntax:
                    let opacityAnim = CASpringAnimation(keyPath: "opacity")
                    let (fromVal, toVal): (Float, Float) = direction == .sourceToRich
                        ? (1.0, 0.0) : (0.0, 1.0)
                    opacityAnim.fromValue = fromVal
                    opacityAnim.toValue = toVal
                    opacityAnim.mass = mass
                    opacityAnim.stiffness = stiffness
                    opacityAnim.damping = damping
                    opacityAnim.initialVelocity = 0
                    layer.add(opacityAnim, forKey: "opacity")
                    layer.opacity = toVal
                case .listMarker, .blockquoteMarker:
                    break
                }

                layer.add(posAnim, forKey: "position")
                layer.add(sizeAnim, forKey: "bounds")
                layer.position = CGPoint(
                    x: element.destinationFrame.midX,
                    y: element.destinationFrame.midY
                )
                layer.bounds.size = element.destinationFrame.size
            }

            CATransaction.commit()
        }
    }

    /// Cancels any in-flight animation.
    public func cancelAnimation() {
        guard isAnimating else { return }
        isAnimating = false

        for layer in activeOverlayLayers {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
        activeOverlayLayers = []
        RenderTransitionSignpost.endTransition()
    }

    private func finishMacOSAnimation(startTime: CFTimeInterval, lineCount: Int, reducedMotion: Bool) {
        guard isAnimating else { return }

        for layer in activeOverlayLayers {
            layer.removeFromSuperlayer()
        }
        activeOverlayLayers = []

        let endTime = CACurrentMediaTime()
        lastFrameMetrics = FrameRateMetrics(
            totalDuration: endTime - startTime,
            frameCount: 0,
            frameIntervals: [],
            deviceModel: "macOS",
            documentLineCount: lineCount,
            reducedMotion: reducedMotion
        )
        isAnimating = false
        RenderTransitionSignpost.endTransition()
    }

    // MARK: - Helpers

    private func rectForRange(_ range: NSRange, in textView: NSTextView) -> CGRect? {
        guard range.length > 0, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        var glyphRange = NSRange()
        layoutManager.characterRange(
            forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: &glyphRange),
            actualGlyphRange: nil
        )
        let rect = layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
            in: textContainer
        )
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0 else { return nil }
        let origin = textView.textContainerOrigin
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    private func captureSnapshot(of textView: NSView) -> CGImage? {
        guard let bitmapRep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            return nil
        }
        textView.cacheDisplay(in: textView.bounds, to: bitmapRep)
        return bitmapRep.cgImage
    }

    // MARK: - Benchmark Animation

    /// Performs The Render animation with synthetic elements for benchmarking.
    public func animate(
        in containerView: NSView,
        elements: [ElementTransition],
        reducedMotion: Bool,
        completion: @escaping (FrameRateMetrics) -> Void
    ) {
        guard let hostLayer = containerView.layer else {
            containerView.wantsLayer = true
            animate(in: containerView, elements: elements, reducedMotion: reducedMotion, completion: completion)
            return
        }

        RenderTransitionSignpost.beginTransition()
        let startTime = CACurrentMediaTime()

        let overlayLayers: [CALayer] = elements.map { element in
            let layer = element.snapshotLayer
            layer.frame = element.sourceFrame
            hostLayer.addSublayer(layer)
            return layer
        }

        let (mass, stiffness, damping) = springParameters(config: config)

        if reducedMotion {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                for layer in overlayLayers { layer.removeFromSuperlayer() }
                let endTime = CACurrentMediaTime()
                let metrics = FrameRateMetrics(
                    totalDuration: endTime - startTime, frameCount: 0, frameIntervals: [],
                    deviceModel: "macOS", documentLineCount: 0, reducedMotion: true
                )
                RenderTransitionSignpost.endTransition()
                completion(metrics)
            }
            for layer in overlayLayers {
                let fadeOut = CABasicAnimation(keyPath: "opacity")
                fadeOut.fromValue = 1.0
                fadeOut.toValue = 0.0
                fadeOut.duration = config.reducedMotionDuration
                layer.add(fadeOut, forKey: "opacity")
                layer.opacity = 0.0
            }
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                for layer in overlayLayers { layer.removeFromSuperlayer() }
                let endTime = CACurrentMediaTime()
                let metrics = FrameRateMetrics(
                    totalDuration: endTime - startTime, frameCount: 0, frameIntervals: [],
                    deviceModel: "macOS", documentLineCount: 0, reducedMotion: false
                )
                RenderTransitionSignpost.endTransition()
                completion(metrics)
            }

            for (index, element) in elements.enumerated() {
                let layer = overlayLayers[index]

                let posAnim = CASpringAnimation(keyPath: "position")
                posAnim.fromValue = NSValue(point: NSPoint(
                    x: element.sourceFrame.midX, y: element.sourceFrame.midY
                ))
                posAnim.toValue = NSValue(point: NSPoint(
                    x: element.destinationFrame.midX, y: element.destinationFrame.midY
                ))
                posAnim.mass = mass
                posAnim.stiffness = stiffness
                posAnim.damping = damping
                posAnim.initialVelocity = 0

                let sizeAnim = CASpringAnimation(keyPath: "bounds.size")
                sizeAnim.fromValue = NSValue(size: element.sourceFrame.size)
                sizeAnim.toValue = NSValue(size: element.destinationFrame.size)
                sizeAnim.mass = mass
                sizeAnim.stiffness = stiffness
                sizeAnim.damping = damping
                sizeAnim.initialVelocity = 0

                switch element.type {
                case .headingMarker, .boldMarker, .italicMarker, .codeFence, .linkSyntax:
                    let opacityAnim = CASpringAnimation(keyPath: "opacity")
                    opacityAnim.fromValue = 1.0
                    opacityAnim.toValue = 0.0
                    opacityAnim.mass = mass
                    opacityAnim.stiffness = stiffness
                    opacityAnim.damping = damping
                    opacityAnim.initialVelocity = 0
                    layer.add(opacityAnim, forKey: "opacity")
                    layer.opacity = 0.0
                case .listMarker, .blockquoteMarker:
                    break
                }

                layer.add(posAnim, forKey: "position")
                layer.add(sizeAnim, forKey: "bounds")
                layer.position = CGPoint(
                    x: element.destinationFrame.midX,
                    y: element.destinationFrame.midY
                )
                layer.bounds.size = element.destinationFrame.size
            }

            CATransaction.commit()
        }
    }
}

#endif
