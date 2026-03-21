#if os(macOS)
import SwiftUI
import AppKit

/// Configures NSWindow for native macOS behavior per FEAT-021.
/// Enables tab grouping, full screen, and split view.
/// Per AC-4: Uses NSWindow, not UIWindow via Catalyst.
struct MacOSWindowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                configureMainWindow()
            }
    }

    /// Configures the key window for native macOS behavior.
    /// Per AC-1: macOS app passes Apple HIG review.
    private func configureMainWindow() {
        guard let window = NSApplication.shared.keyWindow else { return }

        // Enable native tab support per HIG.
        // .preferred allows the system to merge windows into tabs when appropriate.
        window.tabbingMode = .preferred

        // Standard title bar — not transparent, visible title per HIG.
        window.titleVisibility = .visible

        // Set minimum window size for usable editor area
        window.minSize = NSSize(width: 480, height: 360)

        // Enable window restoration
        window.isRestorable = true
    }
}

extension View {
    /// Applies native macOS window configuration per FEAT-021.
    func macOSWindowConfiguration() -> some View {
        modifier(MacOSWindowModifier())
    }
}
#endif
