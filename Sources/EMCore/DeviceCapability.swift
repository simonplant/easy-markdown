/// Device capability for AI feature gating per [A-033].
/// Determines whether the device supports on-device AI inference (A16+/M1+).
public enum DeviceCapability: Sendable {
    /// A16+ / M1+ — all AI features available.
    case fullAI
    /// Older devices — no generative AI.
    case noAI

    /// Detects the current device's AI capability based on chip family.
    ///
    /// On iOS: checks the hardware machine identifier for iPhone 15+ (iPhone16,x and later).
    /// On macOS: checks for Apple Silicon (M1+) via processor translation check.
    public static func detect() -> DeviceCapability {
        #if os(iOS) || os(visionOS)
        return detectIOS()
        #elseif os(macOS)
        return detectMacOS()
        #else
        return .noAI
        #endif
    }

    #if os(iOS) || os(visionOS)
    private static func detectIOS() -> DeviceCapability {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        // iPhone: gate on iPhone 15 and later per AC-3 ("works on iPhone 15
        // and does not appear on iPhone 14"). iPhone 15 = iPhone16,x.
        // iPhone 14 Pro (iPhone15,2) has A16 but is excluded by product decision.
        if machine.hasPrefix("iPhone") {
            let version = machine.dropFirst("iPhone".count)
            if let major = parseMajorVersion(String(version)) {
                return major >= 16 ? .fullAI : .noAI
            }
        }

        // iPad: M1 starts at iPad13,4 (iPad Pro 5th gen, 2021).
        // Note: iPad13,1-2 are iPad Air 4th gen (A14, not M1) — this is a
        // known approximation. Exact mapping validated in SPIKE-005.
        if machine.hasPrefix("iPad") {
            let version = machine.dropFirst("iPad".count)
            if let major = parseMajorVersion(String(version)) {
                return major >= 13 ? .fullAI : .noAI
            }
        }

        // Simulator uses host machine capability.
        if machine == "x86_64" || machine == "arm64" {
            return .fullAI
        }

        return .noAI
    }

    private static func parseMajorVersion(_ versionString: String) -> Int? {
        let parts = versionString.split(separator: ",")
        guard let first = parts.first else { return nil }
        return Int(first)
    }
    #endif

    #if os(macOS)
    private static func detectMacOS() -> DeviceCapability {
        // Apple Silicon Macs (M1+) report arm64. Intel Macs report x86_64.
        #if arch(arm64)
        return .fullAI
        #else
        return .noAI
        #endif
    }
    #endif
}
