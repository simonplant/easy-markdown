import SwiftUI
import EMApp

@main
struct EasyMarkdownApp: App {
    @State private var appShell = AppShell()

    var body: some Scene {
        WindowGroup {
            appShell.rootView()
        }
    }
}
