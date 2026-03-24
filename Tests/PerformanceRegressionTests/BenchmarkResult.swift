/// A single benchmark result with timing statistics and pass/fail status.
///
/// Captures measurements from a performance benchmark run so results can be
/// serialized for historical comparison and CI build gating per [D-QA-2].
import Foundation

struct BenchmarkResult: Codable, Sendable, CustomStringConvertible {
    /// Performance target identifier (e.g. "D-PERF-1").
    let targetId: String
    /// Human-readable name of the benchmark.
    let name: String
    /// All individual timing samples in milliseconds.
    let samplesMs: [Double]
    /// The threshold that must not be exceeded (in the same unit as the metric).
    let threshold: Double
    /// Unit label for display (e.g. "ms", "MB", "fps").
    let unit: String
    /// The measured value used for pass/fail comparison.
    let measuredValue: Double
    /// Whether the benchmark passed its threshold.
    let passed: Bool
    /// ISO 8601 timestamp of the run.
    let timestamp: String
    /// Device target this was measured on (e.g. "iPhone15,2", "iPad14,6-Pro").
    let deviceTarget: String

    /// p50 in milliseconds (for sample-based benchmarks).
    var p50: Double { percentile(0.50) }
    /// p95 in milliseconds (for sample-based benchmarks).
    var p95: Double { percentile(0.95) }
    /// p99 in milliseconds (for sample-based benchmarks).
    var p99: Double { percentile(0.99) }

    var description: String {
        """
        \(name) [\(targetId)] — \(passed ? "PASS" : "FAIL")
          measured: \(String(format: "%.2f", measuredValue)) \(unit) (threshold: \(String(format: "%.2f", threshold)) \(unit))
          p50: \(String(format: "%.2f", p50)) \(unit), p95: \(String(format: "%.2f", p95)) \(unit), p99: \(String(format: "%.2f", p99)) \(unit)
          samples: \(samplesMs.count), device: \(deviceTarget), at: \(timestamp)
        """
    }

    private func percentile(_ p: Double) -> Double {
        guard !samplesMs.isEmpty else { return 0 }
        let sorted = samplesMs.sorted()
        let index = p * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }
}
