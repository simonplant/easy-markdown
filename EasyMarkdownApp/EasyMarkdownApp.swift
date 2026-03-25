import SwiftUI
import EMApp

/// Thin app target entry point — all logic lives in EMApp's AppShell.
/// See BUILDING.md for Xcode target setup instructions.
@main
struct EasyMarkdownApp: App {
    @State private var appShell = AppShell()

    var body: some Scene {
        WindowGroup {
            appShell.rootView()
        }
        #if os(macOS)
        .commands {
            appShell.macOSCommands()
        }
        #endif
    }
}
