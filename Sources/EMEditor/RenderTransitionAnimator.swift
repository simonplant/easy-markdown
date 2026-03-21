/// SPIKE-004: The Render Animation Feasibility Prototype per [A-020].
///
/// Validates the snapshot-based Core Animation approach for The Render
/// (source-to-rich text transition). Captures layer snapshots, computes
/// target positions, and animates with CASpringAnimation (~400ms, damping 0.8,
/// response 0.4). Instruments via os_signpost on `com.easymarkdown.spike004`.
///
/// Usage: instantiate `RenderTransitionAnimator` with source and destination
/// views, call `animate(completion:)`, then read `lastFrameMetrics`.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import QuartzCore
#endif

// MARK: - Signpost Instrumentation

private let spikeLog = OSLog(subsystem: "com.easymarkdown.spike004", category: .pointsOfInterest)

/// Signpost-based animation timing measurement for SPIKE-004.
public struct RenderTransitionSignpost {

    private static let signpostID = OSSignpostID(log: spikeLog)

    /// Mark the start of the render transition animation.
    public static func beginTransition() {
        os_signpost(.begin, log: spikeLog, name: "TheRenderTransition", signpostID: signpostID)
    }

    /// Mark the end of the render transition animation.
    public static func endTransition() {
        os_signpost(.end, log: spikeLog, name: "TheRenderTransition", signpostID: signpostID)
    }

    /// Mark the start of snapshot capture.
    public static func beginSnapshot() {
        os_signpost(.begin, log: spikeLog, name: "SnapshotCapture", signpostID: signpostID)
    }

    /// Mark the end of snapshot capture.
    public static func endSnapshot() {
        os_signpost(.end, log: spikeLog, name: "SnapshotCapture", signpostID: signpostID)
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
    /// Source frame (position of the syntax characters in source view).
    public let sourceFrame: CGRect
    /// Destination frame (position in rich/rendered view).
    public let destinationFrame: CGRect
    /// The snapshot layer for this element.
    public let snapshotLayer: CALayer
}

#if canImport(UIKit)

// MARK: - Render Transition Animator (iOS)

/// Orchestrates The Render transition animation using snapshot-based Core Animation.
///
/// The animation works by:
/// 1. Capturing the current view state as snapshot layers
/// 2. Computing target positions for each element in the destination layout
/// 3. Animating between source and destination using CASpringAnimation
/// 4. On completion, removing snapshot layers and showing the live view
@MainActor
public final class RenderTransitionAnimator {

    private let config: RenderTransitionConfig
    private var displayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private var animationStartTime: CFTimeInterval = 0

    /// The most recent frame rate metrics from an animation run.
    public private(set) var lastFrameMetrics: FrameRateMetrics?

    /// Creates a transition animator with the given configuration.
    ///
    /// - Parameter config: Animation parameters. Defaults to [A-020] standard values.
    public init(config: RenderTransitionConfig = .standard) {
        self.config = config
    }

    /// Performs The Render transition animation on the given container view.
    ///
    /// This is the primary spike prototype method. It creates synthetic element
    /// layers representing markdown syntax characters and animates them to their
    /// rendered positions using CASpringAnimation.
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

        if reducedMotion {
            animateReducedMotion(
                in: containerView,
                elements: elements,
                completion: completion
            )
        } else {
            animateSpring(
                in: containerView,
                elements: elements,
                completion: completion
            )
        }
    }

    /// Performs the full spring animation per [A-020].
    private func animateSpring(
        in containerView: UIView,
        elements: [ElementTransition],
        completion: @escaping (FrameRateMetrics) -> Void
    ) {
        let overlayLayers: [CALayer] = elements.map { element in
            let layer = element.snapshotLayer
            layer.frame = element.sourceFrame
            containerView.layer.addSublayer(layer)
            return layer
        }

        // Convert response/damping to CASpringAnimation parameters.
        // CASpringAnimation uses mass/stiffness/damping, so we derive them
        // from the response (natural period) and damping ratio.
        let mass: CGFloat = 1.0
        let stiffness = pow(2.0 * .pi / config.response, 2) * mass
        let damping = 4.0 * .pi * config.dampingRatio * mass / config.response

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            // Remove overlay layers
            for layer in overlayLayers {
                layer.removeFromSuperlayer()
            }
            let metrics = self.stopFrameTracking(
                documentLineCount: 0,
                reducedMotion: false
            )
            RenderTransitionSignpost.endTransition()
            completion(metrics)
        }

        for (index, element) in elements.enumerated() {
            let layer = overlayLayers[index]

            // Position animation
            let positionAnim = CASpringAnimation(keyPath: "position")
            positionAnim.fromValue = NSValue(cgPoint: CGPoint(
                x: element.sourceFrame.midX,
                y: element.sourceFrame.midY
            ))
            positionAnim.toValue = NSValue(cgPoint: CGPoint(
                x: element.destinationFrame.midX,
                y: element.destinationFrame.midY
            ))
            positionAnim.mass = mass
            positionAnim.stiffness = stiffness
            positionAnim.damping = damping
            positionAnim.initialVelocity = 0

            // Size animation
            let boundsAnim = CASpringAnimation(keyPath: "bounds.size")
            boundsAnim.fromValue = NSValue(cgSize: element.sourceFrame.size)
            boundsAnim.toValue = NSValue(cgSize: element.destinationFrame.size)
            boundsAnim.mass = mass
            boundsAnim.stiffness = stiffness
            boundsAnim.damping = damping
            boundsAnim.initialVelocity = 0

            // Opacity animation for syntax markers (they fade out)
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
                // These morph in place (position + style), no opacity change
                break
            }

            layer.add(positionAnim, forKey: "position")
            layer.add(boundsAnim, forKey: "bounds")

            // Set final values (Core Animation shows final state after animation)
            layer.position = CGPoint(
                x: element.destinationFrame.midX,
                y: element.destinationFrame.midY
            )
            layer.bounds.size = element.destinationFrame.size
        }

        CATransaction.commit()
    }

    /// Performs the Reduced Motion alternative: 200ms crossfade per [D-A11Y-3].
    private func animateReducedMotion(
        in containerView: UIView,
        elements: [ElementTransition],
        completion: @escaping (FrameRateMetrics) -> Void
    ) {
        let overlayLayers: [CALayer] = elements.map { element in
            let layer = element.snapshotLayer
            layer.frame = element.sourceFrame
            containerView.layer.addSublayer(layer)
            return layer
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            for layer in overlayLayers {
                layer.removeFromSuperlayer()
            }
            let metrics = self.stopFrameTracking(
                documentLineCount: 0,
                reducedMotion: true
            )
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
    }

    // MARK: - Frame Tracking via CADisplayLink

    private func startFrameTracking() {
        frameTimestamps.removeAll()
        frameTimestamps.reserveCapacity(200) // ~400ms @ 120fps ≈ 48 frames + headroom
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

        // Compute frame intervals from consecutive timestamps
        var intervals: [Double] = []
        for i in 1..<frameTimestamps.count {
            intervals.append(frameTimestamps[i] - frameTimestamps[i - 1])
        }

        let metrics = FrameRateMetrics(
            totalDuration: totalDuration,
            frameCount: frameTimestamps.count,
            frameIntervals: intervals,
            deviceModel: deviceModelIdentifier(),
            documentLineCount: documentLineCount,
            reducedMotion: reducedMotion
        )

        lastFrameMetrics = metrics
        return metrics
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        frameTimestamps.append(link.timestamp)
    }

    /// Returns the device model identifier.
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
///
/// Creates synthetic element transitions that simulate heading and bold marker
/// animations, measures frame rate via CADisplayLink, and reports metrics for
/// each document size.
@MainActor
public final class RenderTransitionBenchmark {

    /// Document sizes to benchmark (number of lines).
    public static let defaultDocumentSizes = [10, 100, 1000]

    private let animator: RenderTransitionAnimator

    /// Creates a benchmark runner.
    public init(config: RenderTransitionConfig = .standard) {
        self.animator = RenderTransitionAnimator(config: config)
    }

    /// Runs the benchmark for a given document size, returning frame rate metrics.
    ///
    /// - Parameters:
    ///   - containerView: The view to animate within.
    ///   - lineCount: Number of lines in the simulated document.
    ///   - reducedMotion: Whether to test the reduced motion path.
    /// - Returns: Frame rate metrics for the animation run.
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
                // Patch the line count into the metrics since the animator
                // doesn't know about document context.
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

    /// Generates synthetic element transitions simulating a document.
    ///
    /// For the spike, we create heading markers (# → scaled heading) and
    /// bold markers (** → bold text) distributed through the document.
    /// This exercises the animation pipeline with realistic layer counts.
    private func generateSyntheticElements(
        lineCount: Int,
        containerWidth: CGFloat
    ) -> [ElementTransition] {
        var elements: [ElementTransition] = []
        let lineHeight: CGFloat = 22.0
        let headingHeight: CGFloat = 32.0

        RenderTransitionSignpost.beginSnapshot()

        // Generate heading transitions (~10% of lines are headings)
        let headingCount = max(1, lineCount / 10)
        for i in 0..<headingCount {
            let yPosition = CGFloat(i * 10) * lineHeight

            // Source: "# " marker (small text)
            let sourceFrame = CGRect(x: 16, y: yPosition, width: 24, height: lineHeight)
            // Destination: scaled heading position
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

        // Generate bold marker transitions (~20% of lines have bold text)
        let boldCount = max(1, lineCount / 5)
        for i in 0..<boldCount {
            let yPosition = CGFloat(i * 5) * lineHeight + lineHeight * 0.5

            // Source: "**" marker
            let sourceFrame = CGRect(x: 40, y: yPosition, width: 16, height: lineHeight)
            // Destination: bold text in place (marker dissolves)
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

        // Generate list marker transitions (~15% of lines are list items)
        let listCount = max(1, lineCount * 15 / 100)
        for i in 0..<listCount {
            let yPosition = CGFloat(i * 7) * lineHeight + lineHeight * 3

            // Source: "- " text marker
            let sourceFrame = CGRect(x: 16, y: yPosition, width: 12, height: lineHeight)
            // Destination: styled bullet (position shifts slightly)
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
///
/// Presents a container view and buttons to run benchmarks at different document
/// sizes. Results are displayed inline and logged via os_signpost for Instruments.
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

            // Run for each document size (spring animation)
            for size in documentSizes {
                let metrics = await benchmark.runBenchmark(
                    in: containerView,
                    lineCount: size
                )
                resultLines.append(metrics.description)
                resultLines.append("")

                // Brief pause between runs to let the GPU settle
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            // Run reduced motion test with 100-line document
            let reducedMetrics = await benchmark.runBenchmark(
                in: containerView,
                lineCount: 100,
                reducedMotion: true
            )
            resultLines.append(reducedMetrics.description)

            resultsLabel.text = resultLines.joined(separator: "\n")
            runButton.isEnabled = true
            activityIndicator.stopAnimating()

            let logger = Logger(subsystem: "com.easymarkdown.spike004", category: "results")
            for line in resultLines {
                logger.info("\(line)")
            }
        }
    }
}

#elseif canImport(AppKit)

// MARK: - Render Transition Animator (macOS)

/// macOS implementation of The Render transition animator.
///
/// Uses Core Animation (shared with iOS) for the animation pipeline.
/// Frame tracking uses CVDisplayLink instead of CADisplayLink.
@MainActor
public final class RenderTransitionAnimator {

    private let config: RenderTransitionConfig

    /// The most recent frame rate metrics from an animation run.
    public private(set) var lastFrameMetrics: FrameRateMetrics?

    /// Creates a transition animator with the given configuration.
    public init(config: RenderTransitionConfig = .standard) {
        self.config = config
    }

    /// Performs The Render transition animation on the given view's layer.
    ///
    /// - Parameters:
    ///   - containerView: The view to animate within (must be layer-backed).
    ///   - elements: Element transitions describing source→destination positions.
    ///   - reducedMotion: If true, uses a 200ms crossfade.
    ///   - completion: Called when the animation finishes.
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

        if reducedMotion {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                for layer in overlayLayers { layer.removeFromSuperlayer() }
                let endTime = CACurrentMediaTime()
                let metrics = FrameRateMetrics(
                    totalDuration: endTime - startTime,
                    frameCount: 0,
                    frameIntervals: [],
                    deviceModel: "macOS",
                    documentLineCount: 0,
                    reducedMotion: true
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
            let mass: CGFloat = 1.0
            let stiffness = pow(2.0 * .pi / config.response, 2) * mass
            let damping = 4.0 * .pi * config.dampingRatio * mass / config.response

            CATransaction.begin()
            CATransaction.setCompletionBlock {
                for layer in overlayLayers { layer.removeFromSuperlayer() }
                let endTime = CACurrentMediaTime()
                let metrics = FrameRateMetrics(
                    totalDuration: endTime - startTime,
                    frameCount: 0,
                    frameIntervals: [],
                    deviceModel: "macOS",
                    documentLineCount: 0,
                    reducedMotion: false
                )
                RenderTransitionSignpost.endTransition()
                completion(metrics)
            }

            for (index, element) in elements.enumerated() {
                let layer = overlayLayers[index]

                let positionAnim = CASpringAnimation(keyPath: "position")
                positionAnim.fromValue = NSValue(point: NSPoint(
                    x: element.sourceFrame.midX,
                    y: element.sourceFrame.midY
                ))
                positionAnim.toValue = NSValue(point: NSPoint(
                    x: element.destinationFrame.midX,
                    y: element.destinationFrame.midY
                ))
                positionAnim.mass = mass
                positionAnim.stiffness = stiffness
                positionAnim.damping = damping
                positionAnim.initialVelocity = 0

                let boundsAnim = CASpringAnimation(keyPath: "bounds.size")
                boundsAnim.fromValue = NSValue(size: element.sourceFrame.size)
                boundsAnim.toValue = NSValue(size: element.destinationFrame.size)
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

    /// Returns the device model identifier.
    private func deviceModelIdentifier() -> String {
        "macOS"
    }
}

#endif
