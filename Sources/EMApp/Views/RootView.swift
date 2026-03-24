import SwiftUI
import EMCore
import EMSettings
import EMFile
import EMAI
#if os(macOS)
import AppKit
#endif

/// Root view with NavigationStack routing per [A-058].
/// Error banners and modal alerts are attached here so they cover all navigation destinations.
/// Handles per-scene state restoration via NSUserActivity per [A-034] and [A-061].
/// Each window scene owns its own AppRouter, FileOpenCoordinator, and FileCreateCoordinator.
/// First-run experience per FEAT-044.
public struct RootView: View {
    @State private var router = AppRouter()
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(RecentsManager.self) private var recentsManager
    @Environment(SettingsManager.self) private var settings
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(FileCreateCoordinator.self) private var fileCreateCoordinator
    @Environment(AIProviderManager.self) private var aiProviderManager
    @State private var hasAttemptedRestore = false
    @State private var firstRunCoordinator: FirstRunCoordinator?
    @State private var showQuickOpen = false
    @State private var quickOpenViewModel: QuickOpenViewModel?

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
                SubscriptionOfferView()
            case .gitHubRepoBrowser:
                RepoBrowserView()
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
        // Quick Open overlay per F-011
        .overlay {
            if showQuickOpen, let vm = quickOpenViewModel {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showQuickOpen = false }
                        .accessibilityHidden(true)

                    VStack {
                        QuickOpenView(viewModel: vm) {
                            showQuickOpen = false
                        }
                        .padding(.top, 60)
                        Spacer()
                    }

                    // Escape key dismissal
                    Button("") { showQuickOpen = false }
                        .keyboardShortcut(.escape, modifiers: [])
                        .hidden()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showQuickOpen)
        .background {
            Button("Quick Open") {
                presentQuickOpen()
            }
            .keyboardShortcut("p", modifiers: .command)
            .hidden()
        }
        .errorAlert()
        .environment(router)
        // Per-scene state advertisement via NSUserActivity per [A-034] and [A-061].
        // Each window scene encodes its open file as an activity so the system can
        // restore windows individually after termination.
        // isActive is true when a file is open, ensuring the activity is updated
        // when the scene has a document to restore.
        .userActivity(sceneActivityType, isActive: fileOpenCoordinator.currentFileURL != nil) { activity in
            encodeSceneState(into: activity)
        }
        .onContinueUserActivity(sceneActivityType) { activity in
            restoreSceneState(from: activity)
        }
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
        #if os(macOS)
        // macOS window configuration: tabs, full screen, split view per FEAT-021.
        .macOSWindowConfiguration()
        // Drag-and-drop file opening per FEAT-021.
        .macOSDragDrop { url in
            handleDroppedFile(url)
        }
        // macOS menu bar command handling per FEAT-021 AC-5.
        .onReceive(NotificationCenter.default.publisher(for: .macOSMenuOpenFile)) { _ in
            macOSOpenFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOSMenuNewFile)) { _ in
            macOSNewFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOSMenuCloseFile)) { _ in
            macOSCloseFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOSMenuSettings)) { _ in
            router.showSettings()
        }
        #endif
    }

    // MARK: - Quick Open per F-011

    /// Presents the Quick Open overlay, creating the view model if needed.
    private func presentQuickOpen() {
        if quickOpenViewModel == nil {
            quickOpenViewModel = QuickOpenViewModel(recentsManager: recentsManager)
        }
        quickOpenViewModel?.reset()
        showQuickOpen = true
    }

    // MARK: - State Restoration per [A-061]

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

    // MARK: - macOS Menu and Drag-Drop per FEAT-021

    #if os(macOS)
    /// Handles a file dropped onto the window.
    private func handleDroppedFile(_ url: URL) {
        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened, .alreadyOpen:
            router.openEditor()
        case .failed:
            break
        }
    }

    /// Opens a file via NSOpenPanel from the menu bar.
    private func macOSOpenFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownExtensions.utTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let attempt = fileOpenCoordinator.openFile(url: url)
                switch attempt {
                case .opened, .alreadyOpen:
                    router.openEditor()
                case .failed:
                    break
                }
            }
        }
    }

    /// Creates a new file via NSSavePanel from the menu bar.
    private func macOSNewFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = MarkdownExtensions.utTypes
        panel.nameFieldStringValue = "Untitled.md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let attempt = fileCreateCoordinator.createFile(at: url)
                if case .created = attempt,
                   let content = fileCreateCoordinator.createdFileContent {
                    fileOpenCoordinator.setFileContent(content, url: url)
                    fileCreateCoordinator.clearCreatedFile()
                    router.openEditor()
                }
            }
        }
    }

    /// Closes the current file from the menu bar.
    private func macOSCloseFile() {
        fileOpenCoordinator.closeCurrentFile()
        router.popToHome()
    }
    #endif

    // MARK: - Per-Scene NSUserActivity per [A-034]

    /// Encodes the current scene's open file into the NSUserActivity for restoration.
    /// Called by SwiftUI's `userActivity` modifier whenever scene state changes.
    private func encodeSceneState(into activity: NSUserActivity) {
        activity.title = "Edit Document"
        activity.needsSave = true

        guard let url = fileOpenCoordinator.currentFileURL else {
            // No file open — clear activity payload
            activity.userInfo = nil
            return
        }

        // Encode the file's security-scoped bookmark for restoration
        do {
            let bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            activity.userInfo = [
                "bookmarkData": bookmarkData,
                "filename": url.lastPathComponent
            ]
        } catch {
            // Bookmark creation failed — activity won't restore this file
            activity.userInfo = nil
        }
    }

    /// Restores scene state from an NSUserActivity when the system restores a window.
    /// Per [A-034]: each scene restores its own file independently.
    private func restoreSceneState(from activity: NSUserActivity) {
        guard let userInfo = activity.userInfo,
              let bookmarkData = userInfo["bookmarkData"] as? Data else {
            return
        }

        let attempt = fileOpenCoordinator.openFile(fromBookmark: bookmarkData)
        switch attempt {
        case .opened, .alreadyOpen:
            router.openEditor()
        case .failed:
            break // Stay on home screen
        }
    }
}
