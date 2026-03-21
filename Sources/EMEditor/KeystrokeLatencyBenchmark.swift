/// SPIKE-001: TextKit 2 Keystroke Latency Benchmark per [A-004].
///
/// Measures keystroke-to-render latency using os_signpost for a TextKit 2-backed
/// text view with attributed string updates per paragraph. Designed to run on
/// iPhone 15 and iPhone SE (3rd gen) to validate the <16ms target from [D-PERF-2].
///
/// Usage: instantiate `KeystrokeLatencyBenchmark` with a `UITextView` backed by
/// `NSTextLayoutManager`, call `runBenchmark()`, then read `results`.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Signpost Instrumentation

private let benchmarkLog = OSLog(subsystem: "com.easymarkdown.spike001", category: .pointsOfInterest)

/// Signpost-based keystroke-to-render latency measurement for SPIKE-001.
///
/// Wraps os_signpost interval tracking: begin on `textViewDidBeginEditing`-equivalent
/// keystroke processing, end after layout completes and the display link fires.
public struct KeystrokeSignpost {

    private static let signpostID = OSSignpostID(log: benchmarkLog)

    /// Mark the start of a keystroke processing interval.
    public static func beginKeystroke(_ index: Int) {
        os_signpost(.begin, log: benchmarkLog, name: "KeystrokeToRender", signpostID: signpostID,
                    "keystroke %d", index)
    }

    /// Mark the end of keystroke processing (after layout + render commit).
    public static func endKeystroke(_ index: Int) {
        os_signpost(.end, log: benchmarkLog, name: "KeystrokeToRender", signpostID: signpostID,
                    "keystroke %d", index)
    }
}

// MARK: - Benchmark Results

/// Latency statistics from a benchmark run.
public struct LatencyResults: Sendable, CustomStringConvertible {
    /// All individual latency samples in seconds.
    public let samples: [Double]
    /// Device identifier string (e.g. "iPhone15,2").
    public let deviceModel: String
    /// Number of keystrokes measured.
    public var count: Int { samples.count }

    /// p50 latency in milliseconds.
    public var p50ms: Double { percentile(0.50) * 1000 }
    /// p95 latency in milliseconds.
    public var p95ms: Double { percentile(0.95) * 1000 }
    /// p99 latency in milliseconds.
    public var p99ms: Double { percentile(0.99) * 1000 }
    /// Minimum latency in milliseconds.
    public var minMs: Double { (samples.min() ?? 0) * 1000 }
    /// Maximum latency in milliseconds.
    public var maxMs: Double { (samples.max() ?? 0) * 1000 }
    /// Mean latency in milliseconds.
    public var meanMs: Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0, +) / Double(samples.count)) * 1000
    }
    /// Whether all p95 samples meet the <16ms target.
    public var meetsTarget: Bool { p95ms < 16.0 }

    public var description: String {
        """
        Keystroke Latency Results (\(count) samples, \(deviceModel))
        ─────────────────────────────────────────
        p50:  \(String(format: "%.2f", p50ms)) ms
        p95:  \(String(format: "%.2f", p95ms)) ms
        p99:  \(String(format: "%.2f", p99ms)) ms
        min:  \(String(format: "%.2f", minMs)) ms
        max:  \(String(format: "%.2f", maxMs)) ms
        mean: \(String(format: "%.2f", meanMs)) ms
        Target (<16ms p95): \(meetsTarget ? "PASS" : "FAIL")
        """
    }

    private func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = p * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }
}

// MARK: - Benchmark Runner

#if canImport(UIKit)

/// Runs a keystroke-to-render latency benchmark on a TextKit 2-backed UITextView.
///
/// The benchmark:
/// 1. Pre-populates the text view with representative markdown content (~50 paragraphs)
/// 2. Simulates 120 consecutive keystrokes (typed characters)
/// 3. For each keystroke, applies a per-paragraph attributed string update
/// 4. Measures the interval from text insertion to CATransaction completion
/// 5. Collects all latency samples and computes p50/p95/p99
@MainActor
public final class KeystrokeLatencyBenchmark {

    /// Representative markdown content for benchmark (mixed headings, paragraphs, lists).
    private static let sampleMarkdown: String = {
        var lines: [String] = []
        lines.append("# SPIKE-001 Benchmark Document\n")
        lines.append("This document contains representative markdown content for benchmarking.\n")
        for i in 1...20 {
            lines.append("## Section \(i)\n")
            lines.append("This is paragraph content for section \(i). It contains enough text to exercise the text layout engine with attributed string rendering. The content includes **bold**, *italic*, and `inline code` spans that require attribute computation.\n")
            lines.append("- List item \(i)a with some detail text")
            lines.append("- List item \(i)b with **bold** formatting")
            lines.append("- List item \(i)c with `code` and *emphasis*\n")
        }
        return lines.joined(separator: "\n")
    }()

    private let textView: UITextView
    private var latencySamples: [Double] = []
    private let keystrokeCount: Int

    /// Creates a benchmark runner.
    ///
    /// - Parameters:
    ///   - textView: A TextKit 2-backed UITextView (must use NSTextLayoutManager).
    ///   - keystrokeCount: Number of keystrokes to simulate (default 120).
    public init(textView: UITextView, keystrokeCount: Int = 120) {
        self.textView = textView
        self.keystrokeCount = keystrokeCount
    }

    /// Runs the benchmark and returns latency results.
    ///
    /// This must be called on the main actor. The method uses a continuation-based
    /// approach to wait for each keystroke's render cycle to complete.
    public func runBenchmark() async -> LatencyResults {
        // Pre-populate with markdown content
        textView.text = Self.sampleMarkdown

        // Let initial layout settle
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms settle time

        latencySamples.removeAll()
        latencySamples.reserveCapacity(keystrokeCount)

        let insertionPoint = textView.text.count

        for i in 0..<keystrokeCount {
            let latency = await measureSingleKeystroke(index: i, insertionPoint: insertionPoint + i)
            latencySamples.append(latency)
        }

        let model = deviceModelIdentifier()
        return LatencyResults(samples: latencySamples, deviceModel: model)
    }

    /// Measures a single keystroke-to-render interval.
    private func measureSingleKeystroke(index: Int, insertionPoint: Int) async -> Double {
        let start = CACurrentMediaTime()

        KeystrokeSignpost.beginKeystroke(index)

        // Simulate keystroke: insert a character at the end
        let char = Character(UnicodeScalar(0x61 + (index % 26))!) // a-z cycling
        let range = NSRange(location: insertionPoint, length: 0)
        textView.textStorage.replaceCharacters(in: range, with: String(char))

        // Apply per-paragraph attributed string update (simulates re-render pipeline)
        applyParagraphAttributes(around: insertionPoint)

        // Force layout pass
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }

        // Wait for CATransaction to commit (render to screen)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                continuation.resume()
            }
            CATransaction.commit()
        }

        let end = CACurrentMediaTime()
        KeystrokeSignpost.endKeystroke(index)

        return end - start
    }

    /// Applies attributed string styling to the paragraph containing the edit point.
    /// This simulates the per-paragraph re-render that the real editor performs.
    private func applyParagraphAttributes(around location: Int) {
        let storage = textView.textStorage
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let paragraphRange = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))

        // Apply representative attributes matching what MarkdownRenderer does
        storage.beginEditing()
        storage.addAttributes([
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4.0
                style.paragraphSpacing = 8.0
                return style
            }()
        ], range: paragraphRange)
        storage.endEditing()
    }

    /// Returns the device model identifier (e.g. "iPhone15,2" for iPhone 15).
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

// MARK: - Benchmark View Controller

/// Standalone view controller for running SPIKE-001 benchmarks.
///
/// Presents a TextKit 2 text view and a "Run Benchmark" button. Results are
/// displayed inline and logged via os_signpost for Instruments analysis.
public final class KeystrokeBenchmarkViewController: UIViewController {

    private var textView: UITextView!
    private var resultsLabel: UILabel!
    private var runButton: UIButton!
    private var activityIndicator: UIActivityIndicatorView!

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "SPIKE-001: Keystroke Latency"
        view.backgroundColor = .systemBackground

        // TextKit 2 text view setup (mirrors EMTextView init)
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        ))
        layoutManager.textContainer = container

        textView = UITextView(frame: .zero, textContainer: container)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isEditable = true
        textView.isScrollEnabled = true
        view.addSubview(textView)

        resultsLabel = UILabel()
        resultsLabel.translatesAutoresizingMaskIntoConstraints = false
        resultsLabel.numberOfLines = 0
        resultsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultsLabel.textColor = .secondaryLabel
        view.addSubview(resultsLabel)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        runButton = UIButton(type: .system)
        runButton.translatesAutoresizingMaskIntoConstraints = false
        runButton.setTitle("Run Benchmark (120 keystrokes)", for: .normal)
        runButton.addTarget(self, action: #selector(runBenchmarkTapped), for: .touchUpInside)
        view.addSubview(runButton)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            runButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 16),
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
        resultsLabel.text = "Running benchmark..."

        Task { @MainActor in
            let benchmark = KeystrokeLatencyBenchmark(textView: textView)
            let results = await benchmark.runBenchmark()

            resultsLabel.text = results.description
            runButton.isEnabled = true
            activityIndicator.stopAnimating()

            let logger = Logger(subsystem: "com.easymarkdown.spike001", category: "results")
            logger.info("\(results.description)")
        }
    }
}

#endif
