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
    @State private var showingFilePicker = false

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
                    .accessibilityHint("Opens the file picker to choose a markdown file")

                    Button(action: newFile) {
                        Label("New File", systemImage: "doc.badge.plus")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Creates a new empty markdown document")
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
            }
        }
        .task {
            recentsManager.pruneStaleEntries()
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
        #endif
    }

    private func openFile() {
        #if os(iOS)
        showingFilePicker = true
        #else
        openFileViaNSOpenPanel()
        #endif
    }

    private func newFile() {
        // File creation will come with FEAT-002.
        router.openEditor()
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
    #endif
}
