import SwiftUI
import UniformTypeIdentifiers
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
/// Loads file content from FileOpenCoordinator per FEAT-001.
struct EditorShellView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SettingsManager.self) private var settings
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @State private var editorState = EditorState()
    @State private var text = ""
    @State private var wordCount = 0
    @State private var diagnosticCount = 0
    @State private var conflictManager: FileConflictManager?
    @State private var showingSaveElsewherePanel = false
    @State private var currentLineEnding: LineEnding = .lf

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
        .navigationTitle(navigationTitle)
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
        .fileExporter(
            isPresented: $showingSaveElsewherePanel,
            document: TextFileDocument(text: text),
            contentType: .plainText,
            defaultFilename: fileOpenCoordinator.currentFileURL?.lastPathComponent ?? "Untitled.md"
        ) { result in
            switch result {
            case .success:
                // File saved successfully by fileExporter — clear conflict state.
                conflictManager?.keepMine()
            case .failure(let error):
                // User cancelled the save panel — not an error. Banner stays visible
                // so they can try again or dismiss.
                if (error as? CocoaError)?.code == .userCancelled { return }
                errorPresenter.present(.unexpected(underlying: error))
            }
        }
        .onAppear {
            loadFileContent()
            startConflictMonitoring()
        }
        .onDisappear {
            conflictManager?.stopMonitoring()
            // Save in-place on disappear (AC-1): auto-save wired here,
            // full debounced auto-save will come with FEAT-008.
            saveCurrentFile()
        }
    }

    /// The navigation title shows the filename or "Untitled".
    private var navigationTitle: String {
        fileOpenCoordinator.currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    // MARK: - File Loading per FEAT-001

    /// Loads file content from the coordinator into the editor.
    private func loadFileContent() {
        guard let content = fileOpenCoordinator.currentFileContent else { return }
        text = content.text
        currentLineEnding = content.lineEnding
        updateWordCount(content.text)
    }

    /// Saves current editor text back to the open file (AC-1).
    private func saveCurrentFile() {
        guard let url = fileOpenCoordinator.currentFileURL else { return }
        do {
            // Pause conflict detection during our own save
            conflictManager?.pauseDetection()
            try CoordinatedFileAccess.write(
                text: text,
                to: url,
                lineEnding: currentLineEnding
            )
            conflictManager?.resumeDetection()
        } catch {
            conflictManager?.resumeDetection()
            let emError = (error as? EMError) ?? .unexpected(underlying: error)
            errorPresenter.present(emError)
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
        guard let url = fileOpenCoordinator.currentFileURL else { return }
        let manager = FileConflictManager(url: url)
        conflictManager = manager
        manager.startMonitoring()
    }

    private func handleReload(_ manager: FileConflictManager) {
        do {
            let content = try manager.reload()
            text = content.text
            currentLineEnding = content.lineEnding
        } catch {
            let emError = (error as? EMError) ?? .unexpected(underlying: error)
            errorPresenter.present(emError)
        }
    }

    private func handleSaveElsewhere() {
        showingSaveElsewherePanel = true
    }
}

/// Lightweight FileDocument wrapper for exporting editor content via `.fileExporter`.
/// Used by the file deletion conflict flow to save content to a new location.
private struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
