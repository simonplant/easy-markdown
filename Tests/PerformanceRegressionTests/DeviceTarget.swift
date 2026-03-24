/// Representative device targets for performance regression testing per FEAT-064 AC4.
///
/// Defines the device configurations that benchmarks run against. On CI, the simulator
/// destination is selected based on these targets. On real hardware, the device is
/// auto-detected.
enum DeviceTarget: String, CaseIterable, Sendable {
    /// iPhone 15 — baseline phone target for keystroke latency [D-PERF-2].
    case iPhone15 = "iPhone15"
    /// iPad Pro (M2) — ProMotion target for scroll FPS [D-PERF-3].
    case iPadPro = "iPadPro"

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .iPhone15: return "iPhone 15"
        case .iPadPro: return "iPad Pro (M2)"
        }
    }

    /// Xcode simulator destination string for `xcodebuild -destination`.
    var simulatorDestination: String {
        switch self {
        case .iPhone15:
            return "platform=iOS Simulator,name=iPhone 15,OS=latest"
        case .iPadPro:
            return "platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation),OS=latest"
        }
    }

    /// Whether this device supports ProMotion (120Hz).
    var supportsProMotion: Bool {
        switch self {
        case .iPhone15: return false
        case .iPadPro: return true
        }
    }

    /// Expected scroll FPS target for this device.
    var expectedScrollFps: Double {
        supportsProMotion ? 120.0 : 60.0
    }

    /// Detects the current runtime environment and returns the closest matching target.
    static func detectCurrent() -> DeviceTarget {
        #if targetEnvironment(simulator)
        // In simulator, check the SIMULATOR_MODEL_IDENTIFIER environment variable
        if let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            if model.contains("iPad") {
                return .iPadPro
            }
        }
        return .iPhone15
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        if machine.hasPrefix("iPad") {
            return .iPadPro
        }
        return .iPhone15
        #endif
    }
}
