import SwiftUI
import EMCore
import EMSettings

/// Composition root per [A-059].
/// Creates and wires all shared singletons, provides the app scene.
///
/// Usage in the Xcode app target:
/// ```swift
/// import SwiftUI
/// import EMApp
///
/// @main
/// struct EasyMarkdownApp: App {
///     @State private var appShell = AppShell()
///
///     var body: some Scene {
///         WindowGroup {
///             appShell.rootView()
///         }
///     }
/// }
/// ```
@MainActor
public final class AppShell {
    private let settings: SettingsManager
    private let errorPresenter: ErrorPresenter

    public init() {
        self.settings = SettingsManager()
        self.errorPresenter = ErrorPresenter()
    }

    /// Returns the configured root view with all environment dependencies injected.
    public func rootView() -> some View {
        AppRootWrapper(settings: settings, errorPresenter: errorPresenter)
    }
}

/// Internal wrapper that reactively applies color scheme preference.
/// Needed because `@Observable` properties require an observing View to trigger updates.
struct AppRootWrapper: View {
    @State var settings: SettingsManager
    @State var errorPresenter: ErrorPresenter

    var body: some View {
        RootView()
            .environment(settings)
            .environment(errorPresenter)
            .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch settings.preferredColorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
