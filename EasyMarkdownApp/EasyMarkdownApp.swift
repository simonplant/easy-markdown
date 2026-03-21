import SwiftUI
import EMApp

/// App entry point. Per AppShell's doc comment in EasyMarkdownApp.swift (EMApp):
/// This thin wrapper delegates all logic to AppShell (the composition root).
///
/// Create an Xcode app target, add this file as its only source,
/// and link against the EMApp library. See BUILDING.md for setup steps.
@main
struct EasyMarkdownApp: App {
    @State private var appShell = AppShell()

    var body: some Scene {
        WindowGroup {
            appShell.rootView()
        }
    }
}
