/// SPIKE-003: Full Re-Parse Benchmark for swift-markdown per [A-003].
///
/// Measures full document re-parse time using `ContinuousClock` and `os_signpost`
/// for a 10,000-line markdown document. Designed to validate the <100ms background
/// re-parse target from [A-017].
///
/// Usage: call `FullReparseBenchmark.run()` to execute the benchmark and get results.

import Foundation
import Markdown
import os

// MARK: - Signpost Instrumentation

private let benchmarkLog = OSLog(subsystem: "com.easymarkdown.spike003", category: .pointsOfInterest)

// MARK: - Benchmark Results

/// Parse timing statistics from the SPIKE-003 benchmark.
public struct ReparseResults: Sendable, CustomStringConvertible {
    /// All individual parse time samples in seconds.
    public let samples: [Double]
    /// Number of lines in the benchmark document.
    public let lineCount: Int
    /// Number of parse iterations.
    public var iterationCount: Int { samples.count }

    /// p50 parse time in milliseconds.
    public var p50ms: Double { percentile(0.50) * 1000 }
    /// p95 parse time in milliseconds.
    public var p95ms: Double { percentile(0.95) * 1000 }
    /// p99 parse time in milliseconds.
    public var p99ms: Double { percentile(0.99) * 1000 }
    /// Minimum parse time in milliseconds.
    public var minMs: Double { (samples.min() ?? 0) * 1000 }
    /// Maximum parse time in milliseconds.
    public var maxMs: Double { (samples.max() ?? 0) * 1000 }
    /// Mean parse time in milliseconds.
    public var meanMs: Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0, +) / Double(samples.count)) * 1000
    }
    /// Whether p95 meets the <100ms background re-parse target from [A-017].
    public var meetsTarget: Bool { p95ms < 100.0 }

    public var description: String {
        """
        Full Re-Parse Results (\(iterationCount) iterations, \(lineCount) lines)
        ─────────────────────────────────────────
        p50:  \(String(format: "%.2f", p50ms)) ms
        p95:  \(String(format: "%.2f", p95ms)) ms
        p99:  \(String(format: "%.2f", p99ms)) ms
        min:  \(String(format: "%.2f", minMs)) ms
        max:  \(String(format: "%.2f", maxMs)) ms
        mean: \(String(format: "%.2f", meanMs)) ms
        Target (<100ms p95): \(meetsTarget ? "PASS" : "FAIL")
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

/// Benchmarks full re-parse of a 10,000-line markdown document via swift-markdown.
///
/// Generates a representative markdown document with mixed block types (headings,
/// paragraphs, lists, code blocks, tables, blockquotes) and measures `Document(parsing:)`
/// across multiple iterations to produce stable statistics.
public enum FullReparseBenchmark {

    /// Number of warm-up iterations (discarded) before measurement.
    private static let warmUpIterations = 3

    /// Number of measured iterations.
    private static let measuredIterations = 20

    /// Generates a representative 10,000-line markdown document.
    ///
    /// The document includes a realistic mix of block types matching
    /// typical user content: headings, paragraphs with inline formatting,
    /// bullet and ordered lists, fenced code blocks, tables, and blockquotes.
    public static func generateDocument(lineCount targetLines: Int = 10_000) -> String {
        var lines: [String] = []
        lines.reserveCapacity(targetLines + 100)

        lines.append("# SPIKE-003 Benchmark Document")
        lines.append("")
        lines.append("This document is auto-generated for benchmarking full re-parse performance.")
        lines.append("")

        var sectionIndex = 0
        while lines.count < targetLines {
            sectionIndex += 1

            // H2 heading
            lines.append("## Section \(sectionIndex): Topic Area \(sectionIndex)")
            lines.append("")

            // Paragraph with inline formatting
            lines.append("This is paragraph content for section \(sectionIndex). It contains **bold text**, *italic text*, `inline code`, and [a link](https://example.com/\(sectionIndex)). The paragraph is long enough to exercise the parser with multiple inline elements including ~~strikethrough~~ and mixed **bold *and italic*** nesting.")
            lines.append("")

            // Bullet list (5 items)
            for j in 1...5 {
                lines.append("- List item \(sectionIndex).\(j) with some descriptive text")
            }
            lines.append("")

            // Ordered list (3 items)
            for j in 1...3 {
                lines.append("\(j). Ordered item \(sectionIndex).\(j) with **bold** and `code`")
            }
            lines.append("")

            // Fenced code block (every 3rd section)
            if sectionIndex % 3 == 0 {
                lines.append("```swift")
                lines.append("func example\(sectionIndex)() -> Int {")
                lines.append("    let value = \(sectionIndex) * 42")
                lines.append("    return value")
                lines.append("}")
                lines.append("```")
                lines.append("")
            }

            // Table (every 4th section)
            if sectionIndex % 4 == 0 {
                lines.append("| Column A | Column B | Column C |")
                lines.append("|----------|----------|----------|")
                for j in 1...3 {
                    lines.append("| Cell \(j)A  | Cell \(j)B  | Cell \(j)C  |")
                }
                lines.append("")
            }

            // Blockquote (every 5th section)
            if sectionIndex % 5 == 0 {
                lines.append("> This is a blockquote in section \(sectionIndex).")
                lines.append("> It spans multiple lines to test blockquote parsing.")
                lines.append("> > And includes a nested blockquote for depth.")
                lines.append("")
            }

            // Task list (every 6th section)
            if sectionIndex % 6 == 0 {
                lines.append("- [x] Completed task in section \(sectionIndex)")
                lines.append("- [ ] Pending task in section \(sectionIndex)")
                lines.append("- [ ] Another pending task")
                lines.append("")
            }

            // H3 subsection with paragraph
            lines.append("### Subsection \(sectionIndex).1")
            lines.append("")
            lines.append("Additional content under a subsection heading. This helps test heading hierarchy parsing and ensures the document has realistic structural depth with multiple heading levels.")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Runs the full re-parse benchmark.
    ///
    /// - Parameter document: The markdown string to benchmark. Defaults to a 10,000-line document.
    /// - Returns: `ReparseResults` with timing statistics.
    public static func run(document: String? = nil) -> ReparseResults {
        let source = document ?? generateDocument()
        let lineCount = source.filter { $0 == "\n" }.count + 1

        let signpostID = OSSignpostID(log: benchmarkLog)
        let parseOptions: Markdown.ParseOptions = [.parseBlockDirectives, .parseMinimalDashes]

        let logger = Logger(subsystem: "com.easymarkdown.spike003", category: "benchmark")
        logger.info("Starting SPIKE-003 benchmark: \(lineCount) lines, \(warmUpIterations) warm-up + \(measuredIterations) measured iterations")

        // Warm-up iterations (discard results, prime caches)
        for _ in 0..<warmUpIterations {
            _ = Markdown.Document(parsing: source, options: parseOptions)
        }

        // Measured iterations
        var samples: [Double] = []
        samples.reserveCapacity(measuredIterations)

        for i in 0..<measuredIterations {
            os_signpost(.begin, log: benchmarkLog, name: "FullReparse", signpostID: signpostID,
                        "iteration %d", i)

            let start = ContinuousClock.now
            _ = Markdown.Document(parsing: source, options: parseOptions)
            let duration = ContinuousClock.now - start

            os_signpost(.end, log: benchmarkLog, name: "FullReparse", signpostID: signpostID,
                        "iteration %d", i)

            let seconds = Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
            samples.append(seconds)
        }

        let results = ReparseResults(samples: samples, lineCount: lineCount)
        logger.info("SPIKE-003 benchmark complete:\n\(results.description)")

        return results
    }
}
