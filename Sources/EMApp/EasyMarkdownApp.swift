import SwiftUI
import EMCore
import EMFile
import EMSettings
import EMAI
import EMCloud

/// NSUserActivity type for per-scene state restoration per [A-034] and [A-061].
/// Each window scene advertises its open document via this activity type.
public let sceneActivityType = "com.easymarkdown.scene.editDocument"

/// Composition root per [A-059].
/// Creates and wires all shared singletons, provides the app scene.
/// Per-scene coordinators are created fresh per window per [A-028] and [A-034].
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
    // MARK: - Shared singletons (across all scenes)

    private let settings: SettingsManager
    private let errorPresenter: ErrorPresenter
    private let recentsManager: RecentsManager

    /// Purchase manager — handles one-time app purchase per [A-012].
    private let purchaseManager: PurchaseManager

    /// Subscription manager — provides subscription status to EMAI per [A-057].
    private let subscriptionManager: SubscriptionManager

    /// AI provider manager — shared singleton per [A-059].
    /// Gates AI UI visibility via `shouldShowAIUI` per AC-6.
    private let aiProviderManager: AIProviderManager

    // MARK: - Shared file services (used by per-scene coordinators)

    private let fileOpenService: FileOpenService
    private let fileCreateService: FileCreateService

    /// Shared open file registry for cross-window duplicate detection per [A-028].
    private let openFileRegistry: OpenFileRegistry

    public init() {
        // Register custom bundled typefaces before any UI is created per [A-052].
        FontRegistration.registerFonts()

        let settings = SettingsManager()
        let errorPresenter = ErrorPresenter()
        let recentsManager = RecentsManager(settings: settings)
        let bookmarkManager = BookmarkManager()
        let scopedAccessManager = ScopedAccessManager()

        self.settings = settings
        self.errorPresenter = errorPresenter
        self.recentsManager = recentsManager
        self.fileOpenService = FileOpenService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: scopedAccessManager
        )
        self.fileCreateService = FileCreateService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: scopedAccessManager
        )
        self.openFileRegistry = OpenFileRegistry()

        // EMCloud: purchase and subscription management per [A-012].
        let purchaseManager = PurchaseManager()
        let subscriptionManager = SubscriptionManager()
        self.purchaseManager = purchaseManager
        self.subscriptionManager = subscriptionManager

        // Wire EMCloud → EMAI via EMCore protocol per [A-057] and [A-059].
        self.aiProviderManager = AIProviderManager(
            subscriptionStatus: subscriptionManager
        )
    }

    /// Returns the configured root view with per-scene coordinators per [A-028].
    /// Each call creates fresh FileOpenCoordinator and FileCreateCoordinator instances
    /// so each window scene owns its own file state independently.
    public func rootView() -> some View {
        let fileOpenCoordinator = FileOpenCoordinator(
            fileOpenService: fileOpenService,
            openFileRegistry: openFileRegistry,
            recentsManager: recentsManager,
            errorPresenter: errorPresenter,
            settings: settings
        )
        let fileCreateCoordinator = FileCreateCoordinator(
            fileCreateService: fileCreateService,
            openFileRegistry: openFileRegistry,
            recentsManager: recentsManager,
            errorPresenter: errorPresenter,
            settings: settings
        )

        return AppRootWrapper(
            settings: settings,
            errorPresenter: errorPresenter,
            recentsManager: recentsManager,
            purchaseManager: purchaseManager,
            fileOpenCoordinator: fileOpenCoordinator,
            fileCreateCoordinator: fileCreateCoordinator,
            aiProviderManager: aiProviderManager
        )
    }
}

/// Internal wrapper that reactively applies color scheme preference per FEAT-007.
/// Theme changes animate with a 200ms crossfade; Reduced Motion triggers instant switch.
/// Per-scene coordinators are owned per window instance per [A-028] and [A-034].
struct AppRootWrapper: View {
    @State var settings: SettingsManager
    @State var errorPresenter: ErrorPresenter
    @State var recentsManager: RecentsManager
    @State var purchaseManager: PurchaseManager
    @State var fileOpenCoordinator: FileOpenCoordinator
    @State var fileCreateCoordinator: FileCreateCoordinator
    @State var aiProviderManager: AIProviderManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RootView()
            .environment(settings)
            .environment(errorPresenter)
            .environment(recentsManager)
            .environment(purchaseManager)
            .environment(fileOpenCoordinator)
            .environment(fileCreateCoordinator)
            .environment(aiProviderManager)
            .preferredColorScheme(colorScheme)
            .animation(themeTransition, value: colorScheme)
    }

    /// Maps user preference to SwiftUI color scheme.
    private var colorScheme: ColorScheme? {
        switch settings.preferredColorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// 200ms crossfade for theme transitions per FEAT-007 AC-6.
    /// Instant switch when Reduced Motion is enabled per AC-7.
    private var themeTransition: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }
}
