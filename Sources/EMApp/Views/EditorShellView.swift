import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import EMCore
import EMEditor
import EMFile
import EMSettings
import EMAI

/// Editor shell: toolbar at top, content area in center, format bar and status bar at bottom.
/// Uses EMEditor's TextViewBridge for the text editing area (TextKit 2).
/// Monitors for external file changes per FEAT-045 and [A-027].
/// Loads file content from FileOpenCoordinator per FEAT-001.
struct EditorShellView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SettingsManager.self) private var settings
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(AIProviderManager.self) private var aiProviderManager
    @State private var editorState = EditorState()
    @State private var text = ""
    @State private var showDoctorPopover = false
    @State private var conflictManager: FileConflictManager?
    @State private var autoSaveManager: AutoSaveManager?
    @State private var showingSaveElsewherePanel = false
    @State private var currentLineEnding: LineEnding = .lf
    @State private var improveCoordinator: ImproveWritingCoordinator?
    @State private var improveService: ImproveWritingService?
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Device-aware layout metrics based on current size class per FEAT-010.
    private var layoutMetrics: LayoutMetrics {
        #if os(iOS)
        let sizeClass: SizeClass = (horizontalSizeClass == .regular) ? .regular : .compact
        return LayoutMetrics.forSizeClass(sizeClass)
        #else
        return .mac
        #endif
    }

    /// Rendering configuration for the current view mode per FEAT-003, FEAT-007, FEAT-010.
    private var renderConfig: RenderConfiguration {
        let isDark = colorScheme == .dark
        return RenderConfiguration(
            typeScale: .default,
            colors: Theme.default.colors(isDark: isDark),
            isSourceView: editorState.isSourceView,
            colorVariant: isDark ? "dark" : "light",
            layoutMetrics: layoutMetrics
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Editor content area — TextKit 2 via EMEditor per [A-004]
            // Rich text rendering per FEAT-003 and [A-018]
            TextViewBridge(
                text: $text,
                editorState: editorState,
                renderConfig: renderConfig,
                isEditable: true,
                isSpellCheckEnabled: settings.isSpellCheckEnabled,
                onTextChange: { newText in
                    updateDocumentStats(newText)
                    autoSaveManager?.contentDidChange()
                },
                improveCoordinator: improveCoordinator
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Document editor")
            .accessibilityHint("Edit your markdown document here")

            // Floating action bar per FEAT-054 and [A-023]
            // Shows on text selection, provides Improve button (FEAT-011 entry point).
            // Accept/dismiss controls appear during active inline diff.
            if let coordinator = improveCoordinator,
               (editorState.selectedRange.length > 0 || coordinator.diffState.isActive),
               aiProviderManager.shouldShowAIUI {
                FloatingActionBar(
                    diffPhase: coordinator.diffState.phase,
                    actions: FloatingActionBarActions(
                        onImprove: { startImprove() },
                        onAccept: { coordinator.accept() },
                        onDismiss: { coordinator.dismiss() }
                    ),
                    showAIActions: aiProviderManager.shouldShowAIUI
                )
                .transition(.scale.combined(with: .opacity))
                .padding(.bottom, 4)
            }

            // Doctor indicator bar per FEAT-005 — non-blocking overlay
            if !editorState.diagnostics.isEmpty {
                Divider()
                DoctorIndicatorBar(
                    diagnostics: editorState.diagnostics,
                    onTap: { showDoctorPopover = true }
                )
                .popover(isPresented: $showDoctorPopover) {
                    DoctorPopoverContent(
                        diagnostics: editorState.diagnostics,
                        onFix: { diagnostic in
                            handleDoctorFix(diagnostic)
                        },
                        onDismiss: { diagnostic in
                            editorState.dismissDiagnostic(diagnostic)
                            #if canImport(UIKit)
                            HapticFeedback.trigger(.doctorFixApplied)
                            #endif
                        }
                    )
                }
            }

            Divider()
            FormatBar()
            Divider()
            StatusBar(
                stats: editorState.documentStats,
                selectionWordCount: editorState.selectionWordCount,
                diagnosticCount: editorState.diagnostics.count
            )
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
        .animation(.easeInOut(duration: 0.2), value: editorState.selectedRange.length > 0)
        .animation(.easeInOut(duration: 0.2), value: improveCoordinator?.diffState.phase)
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
            startAutoSave()
            setupImproveWriting()
        }
        .onDisappear {
            Task {
                await autoSaveManager?.saveNow()
                autoSaveManager?.stop()
            }
            conflictManager?.stopMonitoring()
            // Cancel any active AI improve session on file close
            improveCoordinator?.cancel()
            // Clear doctor state on file close per FEAT-005 AC-3
            editorState.clearDiagnostics()
        }
        .onChange(of: autoSaveManager?.savedWhileInBackground) { _, newValue in
            if newValue == true {
                #if canImport(UIKit)
                HapticFeedback.trigger(.autoSaveConfirm)
                #endif
                autoSaveManager?.clearBackgroundSaveFlag()
            }
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
        updateDocumentStats(content.text)
    }

    /// Sets up the auto-save manager for the current file per FEAT-008 and [A-026].
    private func startAutoSave() {
        guard let url = fileOpenCoordinator.currentFileURL,
              let manager = conflictManager else { return }
        let autoSave = AutoSaveManager(
            url: url,
            lineEnding: currentLineEnding,
            conflictManager: manager,
            initialContent: text
        )
        autoSave.contentProvider = { [self] in text }
        autoSave.onSaveError = { [weak autoSave] error in
            errorPresenter.present(error, recoveryActions: [
                RecoveryAction(label: "Try Again") {
                    await autoSave?.saveNow()
                }
            ])
        }
        autoSaveManager = autoSave
    }

    private func toggleSourceView() {
        editorState.isSourceView.toggle()
        #if canImport(UIKit)
        HapticFeedback.trigger(.toggleView)
        #endif
    }

    /// Applies a doctor fix by replacing text at the specified range per FEAT-005.
    private func handleDoctorFix(_ diagnostic: Diagnostic) {
        guard let fix = diagnostic.fix else { return }
        let fixRange = fix.range

        // Convert UTF-8 offset to String.Index
        let utf8 = text.utf8
        guard let startIdx = utf8.index(utf8.startIndex, offsetBy: fixRange.startOffset, limitedBy: utf8.endIndex),
              let endIdx = utf8.index(startIdx, offsetBy: fixRange.length, limitedBy: utf8.endIndex) else {
            return
        }
        let stringStart = String.Index(startIdx, within: text) ?? text.startIndex
        let stringEnd = String.Index(endIdx, within: text) ?? text.endIndex

        text.replaceSubrange(stringStart..<stringEnd, with: fix.replacement)
        editorState.dismissDiagnostic(diagnostic)

        #if canImport(UIKit)
        HapticFeedback.trigger(.doctorFixApplied)
        #endif

        settings.recordDoctorFixAccept()
    }

    /// Recomputes document stats using NLTokenizer-based calculator per [A-055].
    /// CJK text is segmented correctly (not space-delimited).
    private func updateDocumentStats(_ text: String) {
        let stats = DocumentStatsCalculator.computeFullStats(for: text)
        editorState.updateDocumentStats(stats)
    }

    // MARK: - AI Improve Writing per FEAT-011

    /// Creates the improve writing coordinator and service per FEAT-011.
    /// Wires EMAI → EMEditor via EMCore's ImproveWritingUpdate, maintaining
    /// module isolation per [A-015].
    private func setupImproveWriting() {
        guard aiProviderManager.shouldShowAIUI else { return }
        let coordinator = ImproveWritingCoordinator(editorState: editorState)
        improveCoordinator = coordinator
        improveService = ImproveWritingService(providerManager: aiProviderManager)
    }

    /// Starts the AI improve flow per FEAT-011 AC-1.
    /// User selects text, taps Improve → AI streams improved version.
    private func startImprove() {
        guard let coordinator = improveCoordinator,
              let service = improveService else { return }

        let selectedRange = editorState.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        let selectedText = String(text[swiftRange])
        let stream = service.startImproving(selectedText: selectedText)
        coordinator.startImprove(updateStream: stream)
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
