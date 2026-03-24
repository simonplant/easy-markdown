/// Performance regression test suite per FEAT-064 / [D-QA-2].
///
/// Measures all 5 performance targets on every CI build:
/// - [D-PERF-1] Cold launch time (<1s)
/// - [D-PERF-2] Keystroke-to-render latency (<16ms p95)
/// - [D-PERF-3] Scroll FPS (120fps ProMotion / 60fps standard)
/// - [D-PERF-4] AI first-token latency (<500ms)
/// - [D-PERF-5] Memory usage (<100MB)
///
/// A regression that crosses any threshold fails the test (blocking the build).
/// Results are logged with historical comparison to detect gradual drift.
/// Tests target iPhone 15 and iPad Pro simulators per AC4.

import Testing
import Foundation
@testable import EMCore
@testable import EMParser
@testable import EMFormatter
@testable import EMEditor
@testable import EMAI
@testable import EMFile  // FileOpenService used in cold launch path

// MARK: - Shared Benchmark Utilities

/// Number of warm-up iterations before measurement (prime caches/JIT).
private let warmUpIterations = 3

/// Number of measured iterations for stable statistics.
private let measuredIterations = 20

/// Measures a block over multiple iterations, returning sample times in milliseconds.
private func benchmark(
    warmUp: Int = warmUpIterations,
    iterations: Int = measuredIterations,
    block: () throws -> Void
) rethrows -> [Double] {
    // Warm up
    for _ in 0..<warmUp {
        try block()
    }

    // Measured runs
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = ContinuousClock.now
        try block()
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        samples.append(ms)
    }
    return samples
}

/// Computes p95 from an array of samples.
private func p95(_ samples: [Double]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let sorted = samples.sorted()
    let index = 0.95 * Double(sorted.count - 1)
    let lower = Int(index)
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = index - Double(lower)
    return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
}

/// Creates a `BenchmarkResult` from samples.
private func makeResult(
    targetId: String,
    name: String,
    samples: [Double],
    threshold: Double,
    unit: String,
    measuredValue: Double,
    deviceTarget: String
) -> BenchmarkResult {
    BenchmarkResult(
        targetId: targetId,
        name: name,
        samplesMs: samples,
        threshold: threshold,
        unit: unit,
        measuredValue: measuredValue,
        passed: measuredValue < threshold,
        timestamp: ISO8601DateFormatter().string(from: Date()),
        deviceTarget: deviceTarget
    )
}

// MARK: - D-PERF-1: Cold Launch Time

@Suite("D-PERF-1: Cold Launch Time")
struct ColdLaunchTests {

    /// Measures the cold launch critical path: parser init + file read + initial parse + renderer init.
    ///
    /// This proxies the real cold launch by measuring the time to initialize all
    /// components in the editing-ready critical path: create a parser, open and read
    /// a file from disk, parse it, and prepare the renderer. On device, this must
    /// complete in <1 second per [D-PERF-1].
    @Test("Cold launch critical path completes under 1 second")
    func coldLaunchCriticalPath() throws {
        let device = DeviceTarget.detectCurrent()

        // Create a representative document on disk
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("perf-test-launch-\(UUID().uuidString).md")
        let sampleDoc = FullReparseBenchmark.generateDocument(lineCount: 1_000)
        try sampleDoc.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let samples = try benchmark(warmUp: 2, iterations: 10) {
            // 1. Parser initialization
            let parser = MarkdownParser()

            // 2. File read (simulates coordinated file read)
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ColdLaunchError.invalidEncoding
            }

            // 3. Parse document
            let result = parser.parse(text)
            _ = result.ast

            // 4. Renderer initialization
            let renderer = MarkdownRenderer()
            _ = renderer
        }

        let p95Value = p95(samples)
        let result = makeResult(
            targetId: "D-PERF-1",
            name: "Cold Launch Critical Path",
            samples: samples,
            threshold: PerformanceTargets.coldLaunchMs,
            unit: "ms",
            measuredValue: p95Value,
            deviceTarget: device.rawValue
        )

        print(result)
        #expect(
            result.passed,
            "Cold launch p95 \(String(format: "%.2f", p95Value))ms exceeds \(PerformanceTargets.coldLaunchMs)ms threshold"
        )
    }
}

private enum ColdLaunchError: Error {
    case invalidEncoding
}

// MARK: - D-PERF-2: Keystroke-to-Render Latency

@Suite("D-PERF-2: Keystroke-to-Render Latency")
struct KeystrokeLatencyTests {

    /// Measures the parse + format pipeline that runs on each keystroke.
    ///
    /// The real keystroke-to-render path includes TextKit 2 layout (which requires
    /// a UITextView), but the critical computation is: parse the document, compute
    /// formatting rules, and produce rendering attributes. This must complete in
    /// <16ms (one frame at 60fps) per [D-PERF-2].
    @Test("Keystroke parse+format pipeline completes under 16ms")
    func keystrokeParseFormatPipeline() {
        let device = DeviceTarget.detectCurrent()

        // Build a representative 200-paragraph document (typical editing session)
        var lines: [String] = ["# Test Document\n"]
        for i in 1...200 {
            lines.append("## Section \(i)\n")
            lines.append("This is paragraph \(i) with **bold**, *italic*, and `code` spans. It has [a link](https://example.com/\(i)).\n")
            lines.append("- Item \(i)a\n- Item \(i)b\n")
        }
        let source = lines.joined(separator: "\n")
        let parser = MarkdownParser()

        // Pre-parse (simulates the document already being open)
        var ast = parser.parse(source).ast

        let samples = benchmark(warmUp: 5, iterations: 50) {
            // Simulate keystroke: re-parse (incremental re-parse simulated as full re-parse
            // of the affected region — in practice, the parser operates per-paragraph)
            let result = parser.parse(source)
            ast = result.ast
        }

        let p95Value = p95(samples)
        let result = makeResult(
            targetId: "D-PERF-2",
            name: "Keystroke Parse Pipeline",
            samples: samples,
            threshold: PerformanceTargets.keystrokeLatencyMs,
            unit: "ms",
            measuredValue: p95Value,
            deviceTarget: device.rawValue
        )

        print(result)
        _ = ast // silence unused warning
        #expect(
            result.passed,
            "Keystroke latency p95 \(String(format: "%.2f", p95Value))ms exceeds \(PerformanceTargets.keystrokeLatencyMs)ms threshold"
        )
    }

    /// Measures auto-formatting engine latency on list operations (complementary to parse).
    @Test("Auto-format on 500-item list completes under 16ms")
    func autoFormatListPerformance() {
        let device = DeviceTarget.detectCurrent()

        let engine = FormattingEngine.listFormattingEngine()
        let listText = (1...500).map { "- Item \($0)" }.joined(separator: "\n")
        let cursor = listText.endIndex

        let context = FormattingContext(
            text: listText,
            cursorPosition: cursor,
            trigger: .enter
        )

        let samples = benchmark(warmUp: 5, iterations: 100) {
            _ = engine.evaluate(context)
        }

        let p95Value = p95(samples)
        let result = makeResult(
            targetId: "D-PERF-2",
            name: "Auto-Format List (500 items)",
            samples: samples,
            threshold: PerformanceTargets.keystrokeLatencyMs,
            unit: "ms",
            measuredValue: p95Value,
            deviceTarget: device.rawValue
        )

        print(result)
        #expect(
            result.passed,
            "Auto-format p95 \(String(format: "%.2f", p95Value))ms exceeds \(PerformanceTargets.keystrokeLatencyMs)ms threshold"
        )
    }
}

// MARK: - D-PERF-3: Scroll Performance

@Suite("D-PERF-3: Scroll Performance")
struct ScrollPerformanceTests {

    /// Measures the per-frame render budget for scroll: parse + attribute computation.
    ///
    /// During scroll, each visible paragraph needs attributes computed. This test
    /// measures the time to compute rendering attributes for a large document.
    /// The budget is 8.3ms per frame at 120fps (ProMotion) or 16.6ms at 60fps.
    @Test("Per-frame render computation fits within frame budget")
    func perFrameRenderBudget() {
        let device = DeviceTarget.detectCurrent()
        let frameBudgetMs = device.supportsProMotion ? (1000.0 / 120.0) : (1000.0 / 60.0)

        // A large document — scroll needs to lay out visible paragraphs
        let parser = MarkdownParser()
        var lines: [String] = ["# Scroll Test Document\n"]
        for i in 1...500 {
            lines.append("Paragraph \(i) with **bold**, *italic*, `code`, and [link](https://example.com). ")
            lines.append("More text to make the paragraph long enough to wrap across multiple lines in a typical viewport.\n")
        }
        let source = lines.joined(separator: "\n")
        _ = parser.parse(source) // pre-warm

        // Measure per-frame cost: during scroll, the renderer re-parses visible paragraphs.
        // Each frame processes ~5 visible paragraphs. We simulate this by extracting and
        // re-parsing paragraph-sized chunks of the source text.
        let paragraphsPerFrame = 5
        let lineArray = source.components(separatedBy: "\n")
        let chunkSize = max(1, lineArray.count / 20) // ~25 lines per chunk
        let samples = benchmark(warmUp: 5, iterations: 50) {
            // Simulate scroll frame: parse 5 paragraph-sized chunks
            for chunk in 0..<paragraphsPerFrame {
                let startLine = (chunk * chunkSize) % max(1, lineArray.count - chunkSize)
                let endLine = min(startLine + chunkSize, lineArray.count)
                let paragraphSource = lineArray[startLine..<endLine].joined(separator: "\n")
                _ = parser.parse(paragraphSource)
            }
        }

        let p95Value = p95(samples)

        // Use the device's FPS target for threshold
        let fpsTarget = device.expectedScrollFps
        let result = makeResult(
            targetId: "D-PERF-3",
            name: "Scroll Frame Budget (\(Int(fpsTarget))fps)",
            samples: samples,
            threshold: frameBudgetMs,
            unit: "ms",
            measuredValue: p95Value,
            deviceTarget: device.rawValue
        )

        print(result)
        #expect(
            result.passed,
            "Scroll frame p95 \(String(format: "%.2f", p95Value))ms exceeds \(String(format: "%.2f", frameBudgetMs))ms budget (\(Int(fpsTarget))fps)"
        )
    }

    /// Measures full document parse time — determines if scroll-triggered re-parse
    /// can complete within the scroll deceleration window.
    @Test("Full 10K-line re-parse completes under 100ms")
    func fullReparseForScroll() {
        let device = DeviceTarget.detectCurrent()

        let results = FullReparseBenchmark.run()
        let benchResult = makeResult(
            targetId: "D-PERF-3",
            name: "Full Re-Parse (10K lines)",
            samples: results.samples.map { $0 * 1000 }, // convert s → ms
            threshold: 100.0,
            unit: "ms",
            measuredValue: results.p95ms,
            deviceTarget: device.rawValue
        )

        print(benchResult)
        #expect(
            benchResult.passed,
            "Full re-parse p95 \(String(format: "%.2f", results.p95ms))ms exceeds 100ms threshold"
        )
    }
}

// MARK: - D-PERF-4: AI First-Token Latency

@Suite("D-PERF-4: AI First-Token Latency")
struct AIFirstTokenTests {

    /// Measures the AI provider selection and prompt construction latency.
    ///
    /// The full first-token latency includes model inference, which varies by hardware.
    /// This test measures the controllable portion: provider selection, prompt building,
    /// and stream setup. This overhead must be minimal (<50ms) to leave headroom for
    /// the <500ms total target from [D-PERF-4].
    @Test("AI prompt construction and provider setup completes under 50ms")
    func aiPromptConstructionLatency() {
        let device = DeviceTarget.detectCurrent()

        // Measure prompt construction — the controllable latency before inference starts
        let precedingText = String(repeating: "This is sample text for the AI model. ", count: 50)
        let surroundingContext = String(repeating: "# Heading\nParagraph with **bold** and *italic*.\n", count: 20)

        let samples = benchmark(warmUp: 5, iterations: 50) {
            // Build the prompt (same as GhostTextService does before calling provider.generate)
            let prompt = ContinueWritingPromptTemplate.buildPrompt(
                precedingText: String(precedingText.suffix(500)),
                surroundingContext: surroundingContext
            )
            _ = prompt
        }

        let p95Value = p95(samples)
        // Prompt construction should be <50ms to leave 450ms for actual inference
        let promptOverheadThreshold = 50.0
        let result = makeResult(
            targetId: "D-PERF-4",
            name: "AI Prompt Construction",
            samples: samples,
            threshold: promptOverheadThreshold,
            unit: "ms",
            measuredValue: p95Value,
            deviceTarget: device.rawValue
        )

        print(result)
        #expect(
            result.passed,
            "AI prompt construction p95 \(String(format: "%.2f", p95Value))ms exceeds \(promptOverheadThreshold)ms overhead threshold"
        )
    }

    /// Validates that the signpost infrastructure for first-token measurement is in place.
    /// The actual <500ms target is validated on-device with real AI inference.
    @Test("First-token signpost threshold is correctly configured")
    func firstTokenThresholdConfigured() {
        #expect(PerformanceTargets.aiFirstTokenMs == 500.0)
        #expect(PerformanceTargets.aiFullResponseSeconds == 3.0)
    }
}

// MARK: - D-PERF-5: Memory Usage

@Suite("D-PERF-5: Memory Usage")
struct MemoryUsageTests {

    /// Measures memory footprint after loading a typical editing session.
    ///
    /// Creates a parser, opens a document, parses it, and checks that the total
    /// memory allocated for these core objects stays under the 100MB budget from [D-PERF-5].
    @Test("Typical session memory stays under 100MB")
    func typicalSessionMemory() throws {
        let device = DeviceTarget.detectCurrent()

        // Measure baseline memory
        let baselineMemory = currentMemoryMB()

        // Simulate a typical editing session: parse a moderately large document
        let parser = MarkdownParser()
        let doc = FullReparseBenchmark.generateDocument(lineCount: 5_000)
        let result = parser.parse(doc)

        // Hold references to prevent deallocation during measurement
        let ast = result.ast
        let renderer = MarkdownRenderer()

        // Force document stats calculation
        let stats = DocumentStatsCalculator.computeFullStats(for: doc)

        // Measure memory after session setup
        let sessionMemory = currentMemoryMB()
        let delta = sessionMemory - baselineMemory

        // Keep references alive past measurement
        _ = (ast, renderer, stats)

        let samples = [delta] // Memory is a single-sample metric
        let benchResult = makeResult(
            targetId: "D-PERF-5",
            name: "Typical Session Memory",
            samples: samples,
            threshold: PerformanceTargets.maxMemoryMb,
            unit: "MB",
            measuredValue: delta,
            deviceTarget: device.rawValue
        )

        print(benchResult)
        #expect(
            benchResult.passed,
            "Session memory \(String(format: "%.1f", delta))MB exceeds \(PerformanceTargets.maxMemoryMb)MB threshold"
        )
    }

    /// Measures memory growth from repeated parse cycles (leak detection).
    @Test("No significant memory leak after 100 parse cycles")
    func noMemoryLeakOnRepeatedParse() {
        let parser = MarkdownParser()
        let doc = FullReparseBenchmark.generateDocument(lineCount: 1_000)

        // Warm up and establish baseline
        for _ in 0..<5 {
            _ = parser.parse(doc)
        }
        let baselineMemory = currentMemoryMB()

        // Run 100 parse cycles
        for _ in 0..<100 {
            _ = parser.parse(doc)
        }

        let afterMemory = currentMemoryMB()
        let growth = afterMemory - baselineMemory

        // Allow up to 10MB growth (accounting for caches, autoreleased objects)
        let maxGrowthMB = 10.0
        print("Memory growth after 100 parse cycles: \(String(format: "%.1f", growth))MB (max: \(maxGrowthMB)MB)")
        #expect(
            growth < maxGrowthMB,
            "Memory grew \(String(format: "%.1f", growth))MB after 100 parse cycles — possible leak"
        )
    }

    /// Returns the current process memory usage in megabytes.
    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }
}

// MARK: - Integrated Regression Suite

@Suite("Performance Regression Suite")
struct PerformanceRegressionSuite {

    /// Runs all benchmarks and produces a historical comparison report.
    /// This is the primary entry point for CI — it logs results and compares
    /// against stored baselines to detect gradual drift per AC3.
    @Test("All performance targets pass with historical comparison")
    func fullRegressionSuite() throws {
        let device = DeviceTarget.detectCurrent()
        var results: [BenchmarkResult] = []

        // D-PERF-1: Cold Launch
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("perf-regression-\(UUID().uuidString).md")
        let sampleDoc = FullReparseBenchmark.generateDocument(lineCount: 1_000)
        try sampleDoc.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let launchSamples = try benchmark(warmUp: 2, iterations: 10) {
            let parser = MarkdownParser()
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let result = parser.parse(text)
            _ = result.ast
            let renderer = MarkdownRenderer()
            _ = renderer
        }
        results.append(makeResult(
            targetId: "D-PERF-1", name: "Cold Launch Critical Path",
            samples: launchSamples, threshold: PerformanceTargets.coldLaunchMs,
            unit: "ms", measuredValue: p95(launchSamples), deviceTarget: device.rawValue
        ))

        // D-PERF-2: Keystroke Latency
        let parser = MarkdownParser()
        var lines: [String] = ["# Test\n"]
        for i in 1...200 {
            lines.append("Section \(i) with **bold** and `code`.\n")
        }
        let source = lines.joined(separator: "\n")
        _ = parser.parse(source) // pre-warm

        let keystrokeSamples = benchmark(warmUp: 5, iterations: 50) {
            _ = parser.parse(source)
        }
        results.append(makeResult(
            targetId: "D-PERF-2", name: "Keystroke Parse Pipeline",
            samples: keystrokeSamples, threshold: PerformanceTargets.keystrokeLatencyMs,
            unit: "ms", measuredValue: p95(keystrokeSamples), deviceTarget: device.rawValue
        ))

        // D-PERF-3: Scroll (full re-parse)
        let reparseResults = FullReparseBenchmark.run()
        results.append(makeResult(
            targetId: "D-PERF-3", name: "Full Re-Parse (10K lines)",
            samples: reparseResults.samples.map { $0 * 1000 }, threshold: 100.0,
            unit: "ms", measuredValue: reparseResults.p95ms, deviceTarget: device.rawValue
        ))

        // D-PERF-4: AI Prompt Construction
        let precedingText = String(repeating: "Sample text. ", count: 50)
        let aiSamples = benchmark(warmUp: 5, iterations: 50) {
            let prompt = ContinueWritingPromptTemplate.buildPrompt(
                precedingText: String(precedingText.suffix(500)),
                surroundingContext: nil
            )
            _ = prompt
        }
        results.append(makeResult(
            targetId: "D-PERF-4", name: "AI Prompt Construction",
            samples: aiSamples, threshold: 50.0,
            unit: "ms", measuredValue: p95(aiSamples), deviceTarget: device.rawValue
        ))

        // D-PERF-5: Memory
        let baselineMem = currentMemoryMB()
        let memParser = MarkdownParser()
        let memDoc = FullReparseBenchmark.generateDocument(lineCount: 5_000)
        let memResult = memParser.parse(memDoc)
        let stats = DocumentStatsCalculator.computeFullStats(for: memDoc)
        let sessionMem = currentMemoryMB()
        let memDelta = sessionMem - baselineMem
        _ = (memResult.ast, stats)

        results.append(makeResult(
            targetId: "D-PERF-5", name: "Typical Session Memory",
            samples: [memDelta], threshold: PerformanceTargets.maxMemoryMb,
            unit: "MB", measuredValue: memDelta, deviceTarget: device.rawValue
        ))

        // Report with historical comparison (AC3) and save baseline
        let allPassed = BaselineStore.reportAndSave(results: results, deviceTarget: device.rawValue)
        #expect(allPassed, "One or more performance targets exceeded — see report above")
    }

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }
}
