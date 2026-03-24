import SwiftUI
import EMFile
#if canImport(AppKit)
import AppKit
#endif

/// Home screen per [D-UX-2]: no onboarding, no tutorial, no account creation.
/// Shows Open File and New File buttons plus the recents list.
/// Recents list is the fallback home screen — not a separate mode.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RecentsManager.self) private var recentsManager
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(FileCreateCoordinator.self) private var fileCreateCoordinator
    @Environment(ReviewPromptCoordinator.self) private var reviewPromptCoordinator
    @State private var showingFilePicker = false
    @State private var showingSavePicker = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 32) {
                Spacer()

                Text("easy-markdown")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 16) {
                    Button(action: openFile) {
                        Label("Open File", systemImage: "doc")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityHint("Opens the file picker to choose a markdown file")
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif

                    Button(action: newFile) {
                        Label("New File", systemImage: "doc.badge.plus")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityHint("Creates a new empty markdown document")
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif

                    Button(action: openFromGitHub) {
                        Label("Open from GitHub", systemImage: "arrow.triangle.branch")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Browse and open files from your GitHub repositories")
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)

            if !recentsManager.recentItems.isEmpty {
                RecentsListView()
            }
        }
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { router.showSettings() }) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .task {
            recentsManager.pruneStaleEntries()
        }
        .onAppear {
            reviewPromptCoordinator.requestReviewIfEligible()
        }
        #if os(iOS)
        .sheet(isPresented: $showingFilePicker) {
            DocumentPickerView(
                onPick: { url in
                    showingFilePicker = false
                    handleFilePicked(url)
                },
                onCancel: {
                    showingFilePicker = false
                }
            )
        }
        .sheet(isPresented: $showingSavePicker) {
            SavePickerView(
                onSave: { url in
                    showingSavePicker = false
                    handleFileCreated(url)
                },
                onCancel: {
                    showingSavePicker = false
                }
            )
        }
        #endif
    }

    private func openFromGitHub() {
        router.showGitHubRepoBrowser()
    }

    private func openFile() {
        #if os(iOS)
        showingFilePicker = true
        #else
        openFileViaNSOpenPanel()
        #endif
    }

    private func newFile() {
        #if os(iOS)
        showingSavePicker = true
        #else
        newFileViaNSSavePanel()
        #endif
    }

    private func handleFileCreated(_ url: URL) {
        // Close any currently open file before creating a new one
        fileOpenCoordinator.closeCurrentFile()

        let attempt = fileCreateCoordinator.createFile(at: url)
        switch attempt {
        case .created:
            // Transfer created file to the open coordinator so the editor can use it
            if let content = fileCreateCoordinator.createdFileContent {
                fileOpenCoordinator.setFileContent(content, url: url)
                fileCreateCoordinator.clearCreatedFile()
            }
            router.openEditor()
        case .failed:
            // Error already presented by FileCreateCoordinator.
            break
        }
    }

    private func handleFilePicked(_ url: URL) {
        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened:
            router.openEditor()
        case .alreadyOpen:
            // AC-6: File already open — on single-window iOS, just navigate to editor.
            // Multi-window activation handled at scene level.
            router.openEditor()
        case .failed:
            // Error already presented by FileOpenCoordinator.
            break
        }
    }

    #if os(macOS)
    private func openFileViaNSOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownExtensions.utTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                handleFilePicked(url)
            }
        }
    }

    private func newFileViaNSSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = MarkdownExtensions.utTypes
        panel.nameFieldStringValue = "Untitled.md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                handleFileCreated(url)
            }
        }
    }
    #endif
}
