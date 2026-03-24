/// Centralized performance thresholds per [D-PERF-1] through [D-PERF-5].
///
/// These constants define the regression thresholds for the automated performance
/// test suite (FEAT-064 / [D-QA-2]). A benchmark that exceeds any target blocks the build.
public enum PerformanceTargets: Sendable {

    // MARK: - D-PERF-1: Cold Launch

    /// Maximum cold launch time in milliseconds (app open → editing-ready).
    public static let coldLaunchMs: Double = 1_000.0

    // MARK: - D-PERF-2: Keystroke-to-Render

    /// Maximum p95 keystroke-to-render latency in milliseconds (one frame at 60fps).
    public static let keystrokeLatencyMs: Double = 16.0

    // MARK: - D-PERF-3: Scroll FPS

    /// Minimum scroll FPS on ProMotion displays.
    public static let scrollFpsProMotion: Double = 120.0

    /// Minimum scroll FPS on standard 60Hz displays.
    public static let scrollFpsStandard: Double = 60.0

    // MARK: - D-PERF-4: AI Response

    /// Maximum AI first-token latency in milliseconds.
    public static let aiFirstTokenMs: Double = 500.0

    /// Maximum AI full-response time in seconds.
    public static let aiFullResponseSeconds: Double = 3.0

    // MARK: - D-PERF-5: Memory

    /// Maximum memory usage in megabytes for a typical editing session.
    public static let maxMemoryMb: Double = 100.0
}
