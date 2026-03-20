import SwiftUI
import EMCore
import EMSettings
import EMAI

/// Root view with NavigationStack routing per [A-058].
/// Error banners and modal alerts are attached here so they cover all navigation destinations.
/// Handles state restoration on launch per [A-061] and first-run experience per FEAT-044.
public struct RootView: View {
    @State private var router = AppRouter()
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(RecentsManager.self) private var recentsManager
    @Environment(SettingsManager.self) private var settings
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(AIProviderManager.self) private var aiProviderManager
    @State private var hasAttemptedRestore = false
    @State private var firstRunCoordinator: FirstRunCoordinator?

    public init() {}

    public var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .home:
                        HomeView()
                    case .editor:
                        EditorShellView()
                    }
                }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .subscriptionOffer:
                // Subscription screen — implemented with FEAT-062
                Text("Pro AI")
                    .presentationDetents([.medium])
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let banner = errorPresenter.currentBanner {
                    ErrorBannerView(error: banner) {
                        errorPresenter.dismissBanner()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let coordinator = firstRunCoordinator,
                   coordinator.showModelDownloadBanner {
                    ModelDownloadBannerView(
                        onDownload: { coordinator.acceptDownload() },
                        onDismiss: { coordinator.dismissDownload() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
            .zIndex(1)
        }
        .animation(.easeInOut(duration: 0.25), value: errorPresenter.currentBanner?.id)
        .animation(.easeInOut(duration: 0.25), value: firstRunCoordinator?.showModelDownloadBanner)
        .errorAlert()
        .environment(router)
        .task {
            guard !hasAttemptedRestore else { return }
            hasAttemptedRestore = true
            attemptStateRestoration()

            // Preload local model on launch for capable devices per [A-008].
            await aiProviderManager.preloadLocalModel()

            let coordinator = FirstRunCoordinator(
                settings: settings,
                downloadManager: aiProviderManager.downloadManager
            )
            firstRunCoordinator = coordinator
            await coordinator.evaluateFirstRunPrompt()
        }
    }

    /// Attempts to restore the last open file on launch per [A-061] and AC-5.
    ///
    /// If the last file's bookmark resolves successfully, opens the file via
    /// FileOpenCoordinator and navigates to the editor.
    /// If it fails (file deleted/moved), stays on home screen with recents list.
    private func attemptStateRestoration() {
        guard let bookmarkData = settings.lastOpenFileBookmark else {
            return
        }

        let attempt = fileOpenCoordinator.openFile(fromBookmark: bookmarkData)
        switch attempt {
        case .opened, .alreadyOpen:
            router.openEditor()
        case .failed:
            // Bookmark stale or file gone — clear state, show home/recents
            settings.clearStateRestoration()
        }
    }
}
