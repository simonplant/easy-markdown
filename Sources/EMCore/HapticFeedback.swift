#if canImport(UIKit)
import UIKit

/// Triggers haptic feedback. Respects system haptics setting.
public enum HapticFeedback {
    public static func trigger(_ style: HapticStyle) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .listContinuation, .doctorFixApplied, .toggleView:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .aiAccepted:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .autoSaveConfirm:
            generator = UIImpactFeedbackGenerator(style: .soft)
        }
        generator.impactOccurred()
    }
}
#else

/// No-op implementation for platforms without UIKit (macOS).
public enum HapticFeedback {
    public static func trigger(_ style: HapticStyle) {
        // No haptic hardware on macOS — intentional no-op.
    }
}
#endif
