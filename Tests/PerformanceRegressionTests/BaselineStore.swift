/// Historical baseline storage for performance regression detection per [D-QA-2] AC3.
///
/// Stores benchmark results as JSON and compares new runs against historical baselines
/// to detect gradual performance drift. Results are logged with comparison to the
/// previous baseline so regressions are visible in CI output.
import Foundation

struct BaselineComparison: CustomStringConvertible {
    let current: BenchmarkResult
    let previous: BenchmarkResult?
    /// Percentage change from previous baseline (positive = slower/worse).
    var deltaPercent: Double? {
        guard let prev = previous, prev.measuredValue > 0 else { return nil }
        return ((current.measuredValue - prev.measuredValue) / prev.measuredValue) * 100.0
    }

    var description: String {
        var s = "\(current)"
        if let delta = deltaPercent, let prev = previous {
            let direction = delta > 0 ? "REGRESSION" : "improvement"
            s += "  vs baseline: \(String(format: "%.2f", prev.measuredValue)) \(current.unit) → \(String(format: "%.2f", current.measuredValue)) \(current.unit) (\(String(format: "%+.1f", delta))% \(direction))\n"
        } else {
            s += "  (no previous baseline)\n"
        }
        return s
    }
}

struct BaselineReport: Codable, Sendable {
    let results: [BenchmarkResult]
    let timestamp: String
    let deviceTarget: String
}

enum BaselineStore {

    /// Directory where baseline JSON files are stored.
    /// Uses the test bundle's resource directory or a temp directory for CI.
    static var baselineDirectory: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("easy-markdown-perf-baselines", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves a set of benchmark results as the new baseline.
    static func save(results: [BenchmarkResult], deviceTarget: String) throws {
        let report = BaselineReport(
            results: results,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            deviceTarget: deviceTarget
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)

        let file = baselineDirectory.appendingPathComponent("baseline-\(deviceTarget).json")
        try data.write(to: file, options: .atomic)
    }

    /// Loads the previous baseline for a device target, if available.
    static func loadPrevious(deviceTarget: String) -> BaselineReport? {
        let file = baselineDirectory.appendingPathComponent("baseline-\(deviceTarget).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(BaselineReport.self, from: data)
    }

    /// Compares current results against the stored baseline and produces a report.
    /// Logs all comparisons to stdout for CI visibility.
    static func compare(
        current: [BenchmarkResult],
        deviceTarget: String
    ) -> [BaselineComparison] {
        let previous = loadPrevious(deviceTarget: deviceTarget)
        let previousByKey = Dictionary(
            uniqueKeysWithValues: (previous?.results ?? []).map { ("\($0.targetId)-\($0.name)", $0) }
        )

        return current.map { result in
            BaselineComparison(
                current: result,
                previous: previousByKey["\(result.targetId)-\(result.name)"]
            )
        }
    }

    /// Logs a full comparison report to stdout and returns whether all benchmarks passed.
    @discardableResult
    static func reportAndSave(
        results: [BenchmarkResult],
        deviceTarget: String
    ) -> Bool {
        let comparisons = compare(current: results, deviceTarget: deviceTarget)

        print("═══════════════════════════════════════════════════════")
        print("Performance Regression Report — \(deviceTarget)")
        print("═══════════════════════════════════════════════════════")
        for comparison in comparisons {
            print(comparison)
        }

        let allPassed = results.allSatisfy(\.passed)
        print("Overall: \(allPassed ? "PASS ✓" : "FAIL ✗")")
        print("═══════════════════════════════════════════════════════")

        // Save as new baseline
        try? save(results: results, deviceTarget: deviceTarget)

        return allPassed
    }
}
