import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import EMCore
import EMEditor
import EMFile
import EMSettings

/// Editor shell: toolbar at top, content area in center, format bar and status bar at bottom.
/// Uses EMEditor's TextViewBridge for the text editing area (TextKit 2).
/// Monitors for external file changes per FEAT-045 and [A-027].
struct EditorShellView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SettingsManager.self) private var settings
    @Environment(ErrorPresenter.self) private var errorPresenter
    @State private var editorState = EditorState()
    @State private var text = ""
    @State private var wordCount = 0
    @State private var diagnosticCount = 0
    @State private var conflictManager: FileConflictManager?

    /// The file URL to monitor. Set by the caller when opening a file.
    var fileURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Editor content area — TextKit 2 via EMEditor per [A-004]
            TextViewBridge(
                text: $text,
                editorState: editorState,
                isEditable: true,
                isSpellCheckEnabled: settings.isSpellCheckEnabled,
                onTextChange: { newText in
                    updateWordCount(newText)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Document editor")
            .accessibilityHint("Edit your markdown document here")

            Divider()
            FormatBar()
            Divider()
            StatusBar(wordCount: wordCount, diagnosticCount: diagnosticCount)
        }
        .overlay(alignment: .top) {
            if let manager = conflictManager,
               manager.conflictState != .none {
                ConflictBannerView(
                    conflictState: manager.conflictState,
                    onReload: { handleReload(manager) },
                    onKeepMine: { manager.keepMine() },
                    onSaveElsewhere: { handleSaveElsewhere() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: conflictManager?.conflictState)
        .navigationTitle("Untitled")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            EditorToolbar(
                isSourceView: editorState.isSourceView,
                onToggleSource: toggleSourceView,
                onSettings: { router.showSettings() }
            )
        }
        .onAppear {
            startConflictMonitoring()
        }
        .onDisappear {
            conflictManager?.stopMonitoring()
        }
    }

    private func toggleSourceView() {
        editorState.isSourceView.toggle()
        #if canImport(UIKit)
        HapticFeedback.trigger(.toggleView)
        #endif
    }

    private func updateWordCount(_ text: String) {
        let words = text.split(omittingEmptySubsequences: true) { $0.isWhitespace || $0.isNewline }
        wordCount = words.count
    }

    // MARK: - Conflict Detection per FEAT-045

    private func startConflictMonitoring() {
        guard let url = fileURL else { return }
        let manager = FileConflictManager(url: url)
        conflictManager = manager
        manager.startMonitoring()
    }

    private func handleReload(_ manager: FileConflictManager) {
        do {
            let content = try manager.reload()
            text = content.text
        } catch {
            let emError = (error as? EMError) ?? .unexpected(underlying: error)
            errorPresenter.present(emError)
        }
    }

    private func handleSaveElsewhere() {
        // File was deleted — present error with data-loss-risk severity
        // so the user gets a modal alert. Full save-to-new-location flow
        // will be wired when FEAT-002 (Create File) is implemented.
        guard let url = fileURL, let manager = conflictManager else { return }
        errorPresenter.present(
            EMError.file(.externallyDeleted(url: url)),
            recoveryActions: [
                RecoveryAction(label: "OK") { [weak manager] in
                    manager?.keepMine()
                }
            ]
        )
    }
}
