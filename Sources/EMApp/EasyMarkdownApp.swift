import SwiftUI
import EMCore
import EMFile
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
    private let recentsManager: RecentsManager
    private let fileOpenCoordinator: FileOpenCoordinator
    private let fileCreateCoordinator: FileCreateCoordinator

    public init() {
        let settings = SettingsManager()
        let errorPresenter = ErrorPresenter()
        let recentsManager = RecentsManager(settings: settings)
        let bookmarkManager = BookmarkManager()
        let scopedAccessManager = ScopedAccessManager()
        let fileOpenService = FileOpenService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: scopedAccessManager
        )
        let fileCreateService = FileCreateService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: scopedAccessManager
        )
        let openFileRegistry = OpenFileRegistry()

        self.settings = settings
        self.errorPresenter = errorPresenter
        self.recentsManager = recentsManager
        self.fileOpenCoordinator = FileOpenCoordinator(
            fileOpenService: fileOpenService,
            openFileRegistry: openFileRegistry,
            recentsManager: recentsManager,
            errorPresenter: errorPresenter,
            settings: settings
        )
        self.fileCreateCoordinator = FileCreateCoordinator(
            fileCreateService: fileCreateService,
            openFileRegistry: openFileRegistry,
            recentsManager: recentsManager,
            errorPresenter: errorPresenter,
            settings: settings
        )
    }

    /// Returns the configured root view with all environment dependencies injected.
    public func rootView() -> some View {
        AppRootWrapper(
            settings: settings,
            errorPresenter: errorPresenter,
            recentsManager: recentsManager,
            fileOpenCoordinator: fileOpenCoordinator,
            fileCreateCoordinator: fileCreateCoordinator
        )
    }
}

/// Internal wrapper that reactively applies color scheme preference.
/// Needed because `@Observable` properties require an observing View to trigger updates.
struct AppRootWrapper: View {
    @State var settings: SettingsManager
    @State var errorPresenter: ErrorPresenter
    @State var recentsManager: RecentsManager
    @State var fileOpenCoordinator: FileOpenCoordinator
    @State var fileCreateCoordinator: FileCreateCoordinator

    var body: some View {
        RootView()
            .environment(settings)
            .environment(errorPresenter)
            .environment(recentsManager)
            .environment(fileOpenCoordinator)
            .environment(fileCreateCoordinator)
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
