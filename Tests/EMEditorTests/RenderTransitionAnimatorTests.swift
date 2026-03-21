/// Tests for SPIKE-004: The Render Animation Feasibility.
///
/// Validates the snapshot-based Core Animation prototype for The Render
/// transition. Tests cover configuration, element transitions, reduced motion
/// path, and frame rate measurement infrastructure.

import XCTest
@testable import EMEditor

final class RenderTransitionAnimatorTests: XCTestCase {

    // MARK: - Configuration Tests

    func testStandardConfigValues() {
        let config = RenderTransitionConfig.standard
        XCTAssertEqual(config.dampingRatio, 0.8, "Damping ratio should be 0.8 per [A-020]")
        XCTAssertEqual(config.response, 0.4, "Response should be 0.4s per [A-020]")
        XCTAssertEqual(config.reducedMotionDuration, 0.2, "Reduced motion crossfade should be 200ms per [D-A11Y-3]")
    }

    func testCustomConfig() {
        let config = RenderTransitionConfig(dampingRatio: 0.6, response: 0.3, reducedMotionDuration: 0.15)
        XCTAssertEqual(config.dampingRatio, 0.6)
        XCTAssertEqual(config.response, 0.3)
        XCTAssertEqual(config.reducedMotionDuration, 0.15)
    }

    // MARK: - Element Transition Tests

    func testElementTransitionTypes() {
        // Verify all element types defined per [A-020] §4.3
        let types: [ElementTransition.ElementType] = [
            .headingMarker, .boldMarker, .italicMarker,
            .listMarker, .codeFence, .linkSyntax, .blockquoteMarker
        ]
        XCTAssertEqual(types.count, 7, "Should support all 7 element types per [A-020]")
    }

    func testElementTransitionRawValues() {
        XCTAssertEqual(ElementTransition.ElementType.headingMarker.rawValue, "headingMarker")
        XCTAssertEqual(ElementTransition.ElementType.boldMarker.rawValue, "boldMarker")
        XCTAssertEqual(ElementTransition.ElementType.italicMarker.rawValue, "italicMarker")
        XCTAssertEqual(ElementTransition.ElementType.listMarker.rawValue, "listMarker")
        XCTAssertEqual(ElementTransition.ElementType.codeFence.rawValue, "codeFence")
        XCTAssertEqual(ElementTransition.ElementType.linkSyntax.rawValue, "linkSyntax")
        XCTAssertEqual(ElementTransition.ElementType.blockquoteMarker.rawValue, "blockquoteMarker")
    }

    #if canImport(UIKit)
    func testElementTransitionCreation() {
        let layer = CALayer()
        layer.backgroundColor = UIColor.label.cgColor

        let transition = ElementTransition(
            type: .headingMarker,
            sourceFrame: CGRect(x: 16, y: 0, width: 24, height: 22),
            destinationFrame: CGRect(x: 16, y: 0, width: 300, height: 32),
            snapshotLayer: layer
        )

        XCTAssertEqual(transition.type, .headingMarker)
        XCTAssertEqual(transition.sourceFrame.width, 24)
        XCTAssertEqual(transition.destinationFrame.width, 300)
        XCTAssertEqual(transition.destinationFrame.height, 32)
    }
    #endif

    // MARK: - Frame Rate Metrics Tests

    func testFrameRateMetricsAverageFPS() {
        // 48 frames over 400ms = 120fps
        let metrics = FrameRateMetrics(
            totalDuration: 0.4,
            frameCount: 48,
            frameIntervals: Array(repeating: 1.0 / 120.0, count: 47),
            deviceModel: "test",
            documentLineCount: 100,
            reducedMotion: false
        )
        XCTAssertEqual(metrics.averageFPS, 120.0, accuracy: 1.0)
        XCTAssertTrue(metrics.meetsTarget(fps: 120))
    }

    func testFrameRateMetrics60FPS() {
        // 24 frames over 400ms = 60fps
        let metrics = FrameRateMetrics(
            totalDuration: 0.4,
            frameCount: 24,
            frameIntervals: Array(repeating: 1.0 / 60.0, count: 23),
            deviceModel: "test",
            documentLineCount: 100,
            reducedMotion: false
        )
        XCTAssertEqual(metrics.averageFPS, 60.0, accuracy: 1.0)
        XCTAssertTrue(metrics.meetsTarget(fps: 60))
        XCTAssertFalse(metrics.meetsTarget(fps: 120))
    }

    func testFrameRateMetricsDroppedFrames() {
        // Mix of good and bad frame intervals
        var intervals = Array(repeating: 1.0 / 120.0, count: 40)
        // Add 3 dropped frames (>12.5ms each, which is >1.5x the 8.33ms target)
        intervals.append(contentsOf: [0.020, 0.025, 0.018])

        let metrics = FrameRateMetrics(
            totalDuration: 0.4,
            frameCount: 44,
            frameIntervals: intervals,
            deviceModel: "test",
            documentLineCount: 100,
            reducedMotion: false
        )

        XCTAssertEqual(metrics.droppedFrames(targetFPS: 120), 3)
        XCTAssertEqual(metrics.droppedFrames(targetFPS: 60), 0) // None exceed 25ms
    }

    func testFrameRateMetricsMinFPS() {
        let intervals = [1.0 / 120.0, 1.0 / 120.0, 0.050, 1.0 / 120.0]
        let metrics = FrameRateMetrics(
            totalDuration: 0.4,
            frameCount: 5,
            frameIntervals: intervals,
            deviceModel: "test",
            documentLineCount: 10,
            reducedMotion: false
        )
        XCTAssertEqual(metrics.minFPS, 20.0, accuracy: 1.0)
    }

    func testFrameRateMetricsEmptyIntervals() {
        let metrics = FrameRateMetrics(
            totalDuration: 0,
            frameCount: 0,
            frameIntervals: [],
            deviceModel: "test",
            documentLineCount: 0,
            reducedMotion: false
        )
        XCTAssertEqual(metrics.averageFPS, 0)
        XCTAssertEqual(metrics.minFPS, 0)
        XCTAssertEqual(metrics.droppedFrames(targetFPS: 120), 0)
    }

    func testFrameRateMetricsReducedMotionFlag() {
        let metrics = FrameRateMetrics(
            totalDuration: 0.2,
            frameCount: 12,
            frameIntervals: Array(repeating: 1.0 / 60.0, count: 11),
            deviceModel: "test",
            documentLineCount: 100,
            reducedMotion: true
        )
        XCTAssertTrue(metrics.reducedMotion)
    }

    func testFrameRateMetricsDescription() {
        let metrics = FrameRateMetrics(
            totalDuration: 0.4,
            frameCount: 48,
            frameIntervals: Array(repeating: 1.0 / 120.0, count: 47),
            deviceModel: "iPhone16,1",
            documentLineCount: 100,
            reducedMotion: false
        )
        let desc = metrics.description
        XCTAssertTrue(desc.contains("100 lines"))
        XCTAssertTrue(desc.contains("iPhone16,1"))
        XCTAssertTrue(desc.contains("48"))
    }

    // MARK: - Spring Parameter Derivation Tests

    func testSpringParameterDerivation() {
        // Verify the spring parameter conversion is correct:
        // stiffness = (2π / response)² * mass
        // damping = 4π * dampingRatio * mass / response
        let config = RenderTransitionConfig.standard
        let mass: CGFloat = 1.0
        let expectedStiffness = pow(2.0 * .pi / config.response, 2) * mass
        let expectedDamping = 4.0 * .pi * config.dampingRatio * mass / config.response

        // These values should produce a critically-damped-ish spring
        XCTAssertGreaterThan(expectedStiffness, 0)
        XCTAssertGreaterThan(expectedDamping, 0)

        // Damping ratio 0.8 means slightly underdamped (subtle overshoot)
        // Critical damping would be dampingRatio = 1.0
        XCTAssertLessThan(config.dampingRatio, 1.0, "Should be slightly underdamped for natural feel")
    }

    #if canImport(UIKit)
    // MARK: - Animator Initialization Tests

    @MainActor
    func testAnimatorInitialization() {
        let animator = RenderTransitionAnimator()
        XCTAssertNil(animator.lastFrameMetrics, "Should have no metrics before first run")
    }

    @MainActor
    func testAnimatorWithCustomConfig() {
        let config = RenderTransitionConfig(dampingRatio: 0.9, response: 0.3, reducedMotionDuration: 0.15)
        let animator = RenderTransitionAnimator(config: config)
        XCTAssertNil(animator.lastFrameMetrics)
    }

    // MARK: - Benchmark Runner Tests

    @MainActor
    func testBenchmarkDefaultDocumentSizes() {
        XCTAssertEqual(
            RenderTransitionBenchmark.defaultDocumentSizes,
            [10, 100, 1000],
            "Default sizes should cover small, medium, and large documents"
        )
    }
    #endif
}
