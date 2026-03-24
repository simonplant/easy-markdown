import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMEditor
import EMFile
import EMFormatter
import EMSettings
import EMAI
import EMCloud

/// Editor shell: toolbar at top, content area in center, format bar and status bar at bottom.
/// Uses EMEditor's TextViewBridge for the text editing area (TextKit 2).
/// Monitors for external file changes per FEAT-045 and [A-027].
/// Loads file content from FileOpenCoordinator per FEAT-001.
/// Per-scene instance — each window has its own editor per [A-028] and [A-034].
/// Responsive to Split View widths (1/3, 1/2, 2/3) via horizontalSizeClass per FEAT-015 AC-3.
struct EditorShellView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SettingsManager.self) private var settings
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(FileCreateCoordinator.self) private var fileCreateCoordinator
    @Environment(AIProviderManager.self) private var aiProviderManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(ReviewPromptCoordinator.self) private var reviewPromptCoordinator
    // MARK: - State (kept under 10 per FEAT-074)
    @State private var editorState = EditorState()
    @State private var text = ""
    @State private var showDoctorPopover = false
    @State private var currentLineEnding: LineEnding = .lf
    @State private var aiCoordinator: AICoordinator?
    @State private var exportCoordinator = ExportCoordinator()
    @State private var showingOpenFilePicker = false
    @State private var showingNewFilePicker = false
    @State private var imageDropState = ImageDropState()
    /// Find and replace engine per FEAT-017.
    private let findReplaceEngine = FindReplaceEngine()
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

    /// Rendering configuration for the current view mode per FEAT-003, FEAT-007, FEAT-010, FEAT-019.
    private var renderConfig: RenderConfiguration {
        let isDark = colorScheme == .dark
        let selectedTheme = Theme.builtIn(id: settings.themeID)
        let typeScale = TypeScale.make(fontChoice: settings.fontName, baseSize: CGFloat(settings.fontSize))
        return RenderConfiguration(
            typeScale: typeScale,
            colors: selectedTheme.colors(isDark: isDark),
            isSourceView: editorState.isSourceView,
            colorVariant: "\(settings.themeID)-\(isDark ? "dark" : "light")",
            layoutMetrics: layoutMetrics
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Editor content area — TextKit 2 via EMEditor per [A-004]
            // Rich text rendering per FEAT-003 and [A-018]
            makeTextViewBridge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Document editor")
            .accessibilityHint("Edit your markdown document here")
            .overlay {
                // Image save progress overlay per FEAT-020 AC-4.
                if editorState.isImageSaving {
                    VStack {
                        ProgressView()
                            .controlSize(.large)
                        Text("Saving image…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Saving image")
                }
            }
            .overlay(alignment: .top) {
                // Floating action bar per FEAT-054 and [A-023].
                // Positioned above the selection via GeometryReader + selectionRect.
                // Falls back to top-center when selection rect is unavailable.
                floatingActionBarOverlay
            }
            #if canImport(Speech)
            .overlay(alignment: .bottom) {
                // Voice transcription overlay per FEAT-068 AC-3
                voiceTranscriptionOverlay
                    .padding(.bottom, 80)
            }
            #endif

            // Summary popover per FEAT-055
            .popover(
                isPresented: Binding(
                    get: { aiCoordinator?.summarizeCoordinator?.isPopoverPresented ?? false },
                    set: { newValue in
                        if !newValue { aiCoordinator?.summarizeCoordinator?.dismiss() }
                    }
                )
            ) {
                if let coordinator = aiCoordinator?.summarizeCoordinator {
                    SummaryPopoverContent(
                        summaryText: coordinator.summaryText,
                        isStreaming: coordinator.phase == .streaming,
                        onInsert: {
                            coordinator.insert { summary in
                                insertTextAtCursor(summary)
                            }
                        },
                        onCopy: { coordinator.copyToClipboard() },
                        onDismiss: { coordinator.dismiss() }
                    )
                }
            }

            // Find and replace bar per FEAT-017
            if editorState.findReplaceState.isVisible {
                Divider()
                FindReplaceBar(
                    state: editorState.findReplaceState,
                    onReplace: { performReplace() },
                    onReplaceAll: { performReplaceAll() },
                    onDismiss: { dismissFindReplace() }
                )
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
                        onNavigate: { diagnostic in
                            showDoctorPopover = false
                            editorState.navigateToLine?(diagnostic.line)
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
                diagnosticCount: editorState.diagnostics.count,
                writingGoalWordCount: editorState.writingGoalWordCount
            )
        }
        .overlay(alignment: .top) {
            if let manager = fileOpenCoordinator.conflictManager,
               manager.conflictState != .none {
                ConflictBannerView(
                    conflictState: manager.conflictState,
                    onReload: { handleReload() },
                    onKeepMine: { manager.keepMine() },
                    onSaveElsewhere: { fileOpenCoordinator.handleSaveElsewhere() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editorState.selectedRange.length > 0)
        .animation(.easeInOut(duration: 0.2), value: aiCoordinator?.improveCoordinator?.diffState.phase)
        .animation(.easeInOut(duration: 0.2), value: aiCoordinator?.toneCoordinator?.diffState.phase)
        .animation(.easeInOut(duration: 0.2), value: aiCoordinator?.translationCoordinator?.diffState.phase)
        #if canImport(Speech)
        .animation(.easeInOut(duration: 0.2), value: aiCoordinator?.voiceCoordinator?.diffState.phase)
        .animation(.easeInOut(duration: 0.2), value: aiCoordinator?.voiceCoordinator?.phase)
        #endif
        .animation(.easeInOut(duration: 0.25), value: fileOpenCoordinator.conflictManager?.conflictState)
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            EditorToolbar(
                isSourceView: editorState.isSourceView,
                onToggleSource: toggleSourceView,
                onExportPDF: {
                    exportCoordinator.exportPDF(
                        text: text,
                        documentURL: fileOpenCoordinator.currentFileURL,
                        includeWatermark: settings.isPDFExportWatermarkEnabled,
                        errorPresenter: errorPresenter
                    )
                },
                onShareMarkdown: {
                    exportCoordinator.shareMarkdownFile(
                        text: text,
                        fileURL: fileOpenCoordinator.currentFileURL
                    )
                },
                onPrint: {
                    exportCoordinator.printDocument(
                        text: text,
                        documentURL: fileOpenCoordinator.currentFileURL
                    )
                },
                onSettings: { router.showSettings() },
                showVoiceMic: aiCoordinator?.voiceMicVisible ?? false,
                isVoiceListening: aiCoordinator?.voiceIsListening ?? false,
                isVoiceAvailable: aiCoordinator?.voiceIsAvailable ?? false,
                onVoiceToggle: { aiCoordinator?.toggleVoiceControl() }
            )
        }
        .fileExporter(
            isPresented: Bindable(fileOpenCoordinator).showingSaveElsewherePanel,
            document: TextFileDocument(text: text),
            contentType: .plainText,
            defaultFilename: fileOpenCoordinator.currentFileURL?.lastPathComponent ?? "Untitled.md"
        ) { result in
            switch result {
            case .success:
                // File saved successfully by fileExporter — clear conflict state.
                fileOpenCoordinator.conflictManager?.keepMine()
            case .failure(let error):
                // User cancelled the save panel — not an error. Banner stays visible
                // so they can try again or dismiss.
                if (error as? CocoaError)?.code == .userCancelled { return }
                errorPresenter.present(.unexpected(underlying: error))
            }
        }
        #if os(iOS)
        .sheet(isPresented: Bindable(exportCoordinator).showingPDFShareSheet) {
            if let url = exportCoordinator.exportedPDFURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .sheet(isPresented: Bindable(exportCoordinator).showingMarkdownShareSheet) {
            if let url = exportCoordinator.markdownShareURL(
                text: text,
                fileURL: fileOpenCoordinator.currentFileURL
            ) {
                ShareSheetView(activityItems: [url])
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showingOpenFilePicker) {
            DocumentPickerView(
                onPick: { url in
                    showingOpenFilePicker = false
                    handleFilePickedFromEditor(url)
                },
                onCancel: { showingOpenFilePicker = false }
            )
        }
        .sheet(isPresented: $showingNewFilePicker) {
            SavePickerView(
                onSave: { url in
                    showingNewFilePicker = false
                    handleFileCreatedFromEditor(url)
                },
                onCancel: { showingNewFilePicker = false }
            )
        }
        .sheet(isPresented: $imageDropState.showingPicker) {
            ImageSavePickerView(
                suggestedFilename: imageDropState.filename,
                onSave: { url in
                    imageDropState.showingPicker = false
                    saveAndInsertImage(to: url)
                },
                onCancel: {
                    imageDropState.showingPicker = false
                    imageDropState.data = nil
                }
            )
        }
        #endif
        .alert(
            "Pro AI Feature",
            isPresented: Binding(
                get: { aiCoordinator?.showingProUpgrade ?? false },
                set: { aiCoordinator?.showingProUpgrade = $0 }
            )
        ) {
            Button("Learn More") {
                router.showSubscriptionOffer()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Translate and Tone adjustment are Pro AI features powered by cloud models. Subscribe to unlock them.")
        }
        .confirmationDialog(
            "Adjust Tone",
            isPresented: Binding(
                get: { aiCoordinator?.showingTonePicker ?? false },
                set: { aiCoordinator?.showingTonePicker = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("More Formal") { aiCoordinator?.startToneAdjustment(toneStyle: .formal, text: text) }
            Button("More Casual") { aiCoordinator?.startToneAdjustment(toneStyle: .casual, text: text) }
            Button("More Technical") { aiCoordinator?.startToneAdjustment(toneStyle: .academic, text: text) }
            Button("Simpler") { aiCoordinator?.startToneAdjustment(toneStyle: .concise, text: text) }
            Button("Friendlier") { aiCoordinator?.startToneAdjustment(toneStyle: .friendly, text: text) }
            Button("Custom...") { aiCoordinator?.showingCustomToneInput = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Custom Tone", isPresented: Binding(
            get: { aiCoordinator?.showingCustomToneInput ?? false },
            set: { aiCoordinator?.showingCustomToneInput = $0 }
        )) {
            TextField("e.g. more persuasive", text: Binding(
                get: { aiCoordinator?.customToneInstruction ?? "" },
                set: { aiCoordinator?.customToneInstruction = $0 }
            ))
            Button("Apply") {
                guard let ai = aiCoordinator else { return }
                let instruction = ai.customToneInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else { return }
                ai.startToneAdjustment(toneStyle: .custom(instruction), text: text)
                ai.customToneInstruction = ""
            }
            Button("Cancel", role: .cancel) {
                aiCoordinator?.customToneInstruction = ""
            }
        } message: {
            Text("Describe the tone you want:")
        }
        .confirmationDialog(
            "Translate To",
            isPresented: Binding(
                get: { aiCoordinator?.showingLanguagePicker ?? false },
                set: { aiCoordinator?.showingLanguagePicker = $0 }
            ),
            titleVisibility: .visible
        ) {
            ForEach(TranslationLanguage.all) { language in
                Button(language.name) { aiCoordinator?.requestTranslation(targetLanguage: language.code, text: text) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Large Selection",
            isPresented: Binding(
                get: { aiCoordinator?.showingLongSelectionWarning ?? false },
                set: { aiCoordinator?.showingLongSelectionWarning = $0 }
            )
        ) {
            Button("Continue") { aiCoordinator?.startTranslation(targetLanguage: aiCoordinator?.pendingTranslationLanguage ?? "", text: text) }
            Button("Cancel", role: .cancel) { aiCoordinator?.pendingTranslationLanguage = "" }
        } message: {
            Text("This selection is very long and may take a while to translate. Continue?")
        }
        .alert(
            "Translation Incomplete",
            isPresented: Binding(
                get: { aiCoordinator?.translationCoordinator?.hasPartialFailure ?? false },
                set: { newValue in
                    if !newValue {
                        aiCoordinator?.translationCoordinator?.hasPartialFailure = false
                    }
                }
            )
        ) {
            Button("Retry") {
                aiCoordinator?.translationCoordinator?.dismiss()
                aiCoordinator?.startTranslation(targetLanguage: aiCoordinator?.lastTranslationLanguage ?? "", text: text)
            }
            Button("Cancel", role: .cancel) { aiCoordinator?.translationCoordinator?.dismiss() }
        } message: {
            Text("The translation was interrupted. You can retry or cancel.")
        }
        .onAppear {
            loadFileContent()
            fileOpenCoordinator.startConflictMonitoring()
            startAutoSave()
            setupAI()
            editorState.writingGoalWordCount = settings.writingGoalWordCount
        }
        .task {
            // Check Pro subscription status for floating bar badge per FEAT-054 AC-3.
            if let ai = aiCoordinator {
                ai.isProSubscriber = await aiProviderManager.checkProSubscription()
            }
        }
        .onChange(of: subscriptionManager.isProActive) { _, isActive in
            // Update immediately when subscription state changes per FEAT-062 AC-4.
            aiCoordinator?.isProSubscriber = isActive
        }
        .onDisappear {
            // Cancel any active AI sessions on file close
            aiCoordinator?.cancelAll()
            // Clear doctor state on file close per FEAT-005 AC-3
            editorState.clearDiagnostics()
            // Save, then release per-scene file coordination resources per [A-028].
            // closeCurrentFile() is idempotent — safe if closeFile() already ran.
            // This handles window-close in Stage Manager per FEAT-015 AC-7.
            let openCoordinator = fileOpenCoordinator
            Task { @MainActor in
                await openCoordinator.autoSaveManager?.saveNow()
                openCoordinator.closeCurrentFile()
            }
        }
        .onChange(of: settings.isGhostTextEnabled) { _, newValue in
            aiCoordinator?.updateGhostTextEnabled(newValue)
        }
        .onChange(of: settings.writingGoalWordCount) { _, newValue in
            editorState.writingGoalWordCount = newValue
        }
        .onChange(of: editorState.findReplaceState.searchQuery) { _, _ in
            updateFindMatches()
        }
        .onChange(of: editorState.findReplaceState.mode) { _, _ in
            updateFindMatches()
        }
        .onChange(of: editorState.findReplaceState.isCaseSensitive) { _, _ in
            updateFindMatches()
        }
        .onChange(of: editorState.findReplaceState.currentMatchIndex) { _, _ in
            let findState = editorState.findReplaceState
            if !findState.matches.isEmpty {
                editorState.applyFindHighlights?(findState.matches, findState.currentMatchIndex)
            }
        }
        .onChange(of: fileOpenCoordinator.autoSaveManager?.savedWhileInBackground) { _, newValue in
            if newValue == true {
                #if canImport(UIKit)
                HapticFeedback.trigger(.autoSaveConfirm)
                #endif
                fileOpenCoordinator.autoSaveManager?.clearBackgroundSaveFlag()
            }
        }
        #if os(macOS)
        // macOS menu bar command handling per FEAT-021.
        // Toggle Source View and Find/Replace are forwarded from the menu bar
        // via NotificationCenter to the active editor scene.
        .onReceive(NotificationCenter.default.publisher(for: .macOSMenuToggleSourceView)) { _ in
            toggleSourceView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOSMenuFindReplace)) { _ in
            toggleFindReplace()
        }
        // Format menu actions per FEAT-021 AC-5.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.easymarkdown.menu.bold"))) { _ in
            editorState.performBold?()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.easymarkdown.menu.italic"))) { _ in
            editorState.performItalic?()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.easymarkdown.menu.insertLink"))) { _ in
            editorState.performLink?()
        }
        #endif
    }

    /// Creates the TextViewBridge with all coordinator wiring per FEAT-039.
    /// Separated into a method so the voice coordinator (behind `#if canImport(Speech)`)
    /// can be set on the struct before returning it.
    private func makeTextViewBridge() -> TextViewBridge {
        var bridge = TextViewBridge(
            text: $text,
            editorState: editorState,
            renderConfig: renderConfig,
            isEditable: true,
            isSpellCheckEnabled: settings.isSpellCheckEnabled,
            onTextChange: { newText in
                updateDocumentStats(newText)
                fileOpenCoordinator.autoSaveManager?.contentDidChange()
            },
            onLinkTap: { url in handleLinkTap(url) },
            improveCoordinator: aiCoordinator?.improveCoordinator,
            toneCoordinator: aiCoordinator?.toneCoordinator,
            translationCoordinator: aiCoordinator?.translationCoordinator,
            ghostTextCoordinator: aiCoordinator?.ghostTextCoordinator,
            smartCompletionCoordinator: aiCoordinator?.smartCompletionCoordinator,
            isAutoFormatHeadingSpacing: settings.isAutoFormatHeadingSpacing,
            isAutoFormatBlankLineSeparation: settings.isAutoFormatBlankLineSeparation,
            isAutoFormatTrailingWhitespaceTrim: settings.trailingWhitespaceBehavior == .strip,
            isProseSuggestionsEnabled: settings.isProseSuggestionsEnabled,
            onAIAssist: { editorState.focusAISection = true },
            onVoiceControl: { aiCoordinator?.toggleVoiceControl() },
            onToggleSourceView: { toggleSourceView() },
            onOpenFile: { openFileFromEditor() },
            onNewFile: { newFileFromEditor() },
            onCloseFile: { closeFile() },
            onFindReplace: { toggleFindReplace() },
            onImageReceived: { data, name in handleImageReceived(data: data, suggestedName: name) },
            showAIContextMenuActions: aiCoordinator?.shouldShowAIUI ?? false,
            onContextMenuImprove: { aiCoordinator?.startImprove(text: text) },
            onContextMenuSummarize: { aiCoordinator?.startSummarize(text: text) }
        )
        #if canImport(Speech)
        bridge.voiceCoordinator = aiCoordinator?.voiceCoordinator
        #endif
        return bridge
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
        fileOpenCoordinator.startAutoSave(
            lineEnding: currentLineEnding,
            text: text,
            contentProvider: { [self] in
                var content = text
                if settings.isAutoFormatEnsureTrailingNewline {
                    content = ensureTrailingNewline(content)
                }
                return content
            },
            onSaveError: { [weak fileOpenCoordinator] error in
                errorPresenter.present(error, recoveryActions: [
                    RecoveryAction(label: "Try Again") {
                        await fileOpenCoordinator?.autoSaveManager?.saveNow()
                    }
                ])
            }
        )
    }

    /// Creates the AICoordinator with all AI-related state per FEAT-074.
    private func setupAI() {
        let ai = AICoordinator(
            editorState: editorState,
            aiProviderManager: aiProviderManager,
            settings: settings
        )
        ai.setup()
        aiCoordinator = ai
    }

    private func toggleSourceView() {
        editorState.isSourceView.toggle()
        #if canImport(UIKit)
        HapticFeedback.trigger(.toggleView)
        #endif
    }

    // MARK: - File Navigation Shortcuts per FEAT-009

    /// Opens the file picker from the editor (Cmd+O).
    private func openFileFromEditor() {
        #if os(iOS)
        showingOpenFilePicker = true
        #else
        openFileViaNSOpenPanel()
        #endif
    }

    /// Shows the save picker for a new file from the editor (Cmd+N).
    private func newFileFromEditor() {
        #if os(iOS)
        showingNewFilePicker = true
        #else
        newFileViaNSSavePanel()
        #endif
    }

    /// Closes the current file and returns to the home screen (Cmd+W).
    private func closeFile() {
        Task {
            await fileOpenCoordinator.autoSaveManager?.saveNow()
            fileOpenCoordinator.closeCurrentFile()
            router.popToHome()
        }
    }

    /// Handles a file picked via Cmd+O from the editor.
    private func handleFilePickedFromEditor(_ url: URL) {
        // Close current file before opening the new one (also stops conflict monitoring + auto-save)
        fileOpenCoordinator.closeCurrentFile()

        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened, .alreadyOpen:
            loadFileContent()
            fileOpenCoordinator.startConflictMonitoring()
            startAutoSave()
        case .failed:
            router.popToHome()
        }
    }

    /// Handles a file created via Cmd+N from the editor.
    private func handleFileCreatedFromEditor(_ url: URL) {
        fileOpenCoordinator.closeCurrentFile()

        let attempt = fileCreateCoordinator.createFile(at: url)
        switch attempt {
        case .created:
            if let content = fileCreateCoordinator.createdFileContent {
                fileOpenCoordinator.setFileContent(content, url: url)
                fileCreateCoordinator.clearCreatedFile()
            }
            loadFileContent()
            fileOpenCoordinator.startConflictMonitoring()
            startAutoSave()
        case .failed:
            router.popToHome()
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
                handleFilePickedFromEditor(url)
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
                handleFileCreatedFromEditor(url)
            }
        }
    }
    #endif

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
        reviewPromptCoordinator.requestReviewIfEligible()
    }

    /// Recomputes document stats using NLTokenizer-based calculator per [A-055].
    /// CJK text is segmented correctly (not space-delimited).
    private func updateDocumentStats(_ text: String) {
        let stats = DocumentStatsCalculator.computeFullStats(for: text)
        editorState.updateDocumentStats(stats)
    }

    // MARK: - Floating Action Bar per FEAT-054

    /// Whether to use compact layout (icon-only) for the floating bar.
    private var isFloatingBarCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    /// Floating action bar overlay positioned above the text selection.
    @ViewBuilder
    private var floatingActionBarOverlay: some View {
        if aiCoordinator?.shouldShowFloatingBar ?? false {
            FloatingActionBar(
                diffPhase: aiCoordinator?.activeDiffPhase ?? .inactive,
                actions: FloatingActionBarActions(
                    onImprove: { aiCoordinator?.startImprove(text: text) },
                    onSummarize: { aiCoordinator?.startSummarize(text: text) },
                    onTranslate: { aiCoordinator?.showingLanguagePicker = true },
                    onTone: { aiCoordinator?.showingTonePicker = true },
                    onProUpgrade: { aiCoordinator?.showingProUpgrade = true },
                    onAccept: {
                        aiCoordinator?.acceptActiveDiff()
                        reviewPromptCoordinator.requestReviewIfEligible()
                    },
                    onDismiss: { aiCoordinator?.dismissActiveDiff() },
                    onBold: { editorState.performBold?() },
                    onItalic: { editorState.performItalic?() },
                    onLink: { editorState.performLink?() }
                ),
                showAIActions: aiCoordinator?.shouldShowAIUI ?? false,
                isProSubscriber: aiCoordinator?.isProSubscriber ?? false,
                isCompact: isFloatingBarCompact,
                focusAISection: Binding(
                    get: { editorState.focusAISection },
                    set: { editorState.focusAISection = $0 }
                )
            )
            .fixedSize()
            .transition(.scale.combined(with: .opacity))
            .offset(y: floatingBarYOffset)
            .padding(.top, 8)
        }
    }

    /// Vertical offset for the floating action bar.
    private var floatingBarYOffset: CGFloat {
        guard let selRect = editorState.selectionRect else { return 0 }
        let targetY = max(selRect.minY - 52, 0)
        return targetY
    }

    // MARK: - Voice Transcription Overlay per FEAT-068

    #if canImport(Speech)
    @ViewBuilder
    private var voiceTranscriptionOverlay: some View {
        if let coordinator = aiCoordinator?.voiceCoordinator,
           coordinator.phase == .listening || coordinator.phase == .interpreting {
            VoiceTranscriptionOverlay(
                phase: coordinator.phase,
                transcript: coordinator.liveTranscript,
                isAvailable: coordinator.isAvailable,
                onStartListening: { coordinator.startListening() },
                onStopListening: { coordinator.stopListening() }
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
    #endif

    /// Inserts text at the current cursor position per FEAT-055 AC-2.
    /// Uses `Range(NSRange, in:)` for correct UTF-16 → String.Index conversion.
    private func insertTextAtCursor(_ insertedText: String) {
        let cursorLocation = editorState.selectedRange.location
        let nsRange = NSRange(location: cursorLocation, length: 0)
        guard let insertRange = Range(nsRange, in: text) else { return }

        text.insert(contentsOf: insertedText, at: insertRange.lowerBound)
    }

    // MARK: - Image Handling per FEAT-020 (F-015)

    /// Handles an image received via drag-and-drop or paste per FEAT-020.
    /// Stores the data and presents a save location picker.
    private func handleImageReceived(data: Data, suggestedName: String) {
        imageDropState.data = data
        imageDropState.filename = suggestedName

        #if os(iOS)
        imageDropState.showingPicker = true
        #else
        saveImageViaNSSavePanel()
        #endif
    }

    #if os(macOS)
    /// Shows an NSSavePanel for choosing the image save location on macOS per FEAT-020.
    private func saveImageViaNSSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp]
        panel.nameFieldStringValue = imageDropState.filename
        panel.canCreateDirectories = true

        // Default to document's directory if available
        if let docURL = fileOpenCoordinator.currentFileURL {
            panel.directoryURL = docURL.deletingLastPathComponent()
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                self.imageDropState.data = nil
                return
            }
            Task { @MainActor in
                saveAndInsertImage(to: url)
            }
        }
    }
    #endif

    /// Saves pending image data to the chosen URL and inserts markdown at cursor per FEAT-020.
    /// Runs on a background thread for large images (AC-4).
    private func saveAndInsertImage(to destinationURL: URL) {
        guard let imageData = imageDropState.data else { return }
        let isLargeImage = imageData.count >= 10_000_000 // 10MB threshold per AC-4

        if isLargeImage {
            editorState.isImageSaving = true
        }

        let documentURL = fileOpenCoordinator.currentFileURL

        Task.detached {
            do {
                try ImageSaveService.save(data: imageData, to: destinationURL)

                let relativePath = ImageSaveService.relativePath(
                    from: documentURL,
                    to: destinationURL
                )

                await MainActor.run {
                    self.editorState.isImageSaving = false
                    self.imageDropState.data = nil

                    // Insert markdown image link at cursor position
                    let markdown = "![image](\(relativePath))"
                    self.insertTextAtCursor(markdown)
                }
            } catch {
                await MainActor.run {
                    self.editorState.isImageSaving = false
                    self.imageDropState.data = nil
                    self.errorPresenter.present(
                        EMError.file(.saveFailed(url: destinationURL, underlying: error))
                    )
                }
            }
        }
    }

    // MARK: - Link Handling per FEAT-049 AC-3, AC-5

    /// Handles link taps: relative .md files open in easy-markdown,
    /// other relative files open via system handler, absolute URLs open in browser.
    private func handleLinkTap(_ url: URL) {
        // Absolute URLs (http/https/mailto/etc.) → open in system browser
        if url.scheme != nil && url.scheme != "file" {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
            return
        }

        // Relative or file URL → resolve against the current document's directory
        guard let currentFileURL = fileOpenCoordinator.currentFileURL else {
            // No current file (unsaved doc) — cannot resolve relative links
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
            return
        }

        let resolvedURL: URL
        if url.scheme == "file" {
            resolvedURL = url
        } else {
            // Relative path — resolve against the current file's directory
            let baseDir = currentFileURL.deletingLastPathComponent()
            resolvedURL = baseDir.appendingPathComponent(url.relativeString)
                .standardized
        }

        // .md files → open in easy-markdown via the router
        if resolvedURL.pathExtension.lowercased() == "md" {
            let attempt = fileOpenCoordinator.openFile(url: resolvedURL)
            switch attempt {
            case .opened, .alreadyOpen:
                router.openEditor()
            case .failed:
                break // Error already presented by FileOpenCoordinator
            }
            return
        }

        // Other file types → open with system handler
        #if canImport(UIKit)
        UIApplication.shared.open(resolvedURL)
        #else
        NSWorkspace.shared.open(resolvedURL)
        #endif
    }

    // MARK: - Conflict Detection per FEAT-045

    private func handleReload() {
        do {
            guard let content = try fileOpenCoordinator.handleReload() else { return }
            text = content.text
            currentLineEnding = content.lineEnding
        } catch {
            let emError = (error as? EMError) ?? .unexpected(underlying: error)
            errorPresenter.present(emError)
        }
    }

    // MARK: - Find and Replace per FEAT-017

    /// Toggles the find bar visibility.
    private func toggleFindReplace() {
        let findState = editorState.findReplaceState
        if findState.isVisible {
            dismissFindReplace()
        } else {
            findState.isVisible = true
            // If there's selected text, use it as the search query
            let selectedRange = editorState.selectedRange
            if selectedRange.length > 0,
               let swiftRange = Range(selectedRange, in: text) {
                findState.searchQuery = String(text[swiftRange])
            }
            updateFindMatches()
        }
    }

    /// Dismisses the find bar and clears highlights.
    private func dismissFindReplace() {
        editorState.applyFindHighlights?([], nil)
        let findState = editorState.findReplaceState
        findState.isVisible = false
        findState.reset()
    }

    /// Runs the search engine and updates matches in state.
    /// Also applies visual highlighting to the document per FEAT-017 AC-1.
    private func updateFindMatches() {
        let findState = editorState.findReplaceState
        let result = findReplaceEngine.findMatches(
            query: findState.searchQuery,
            in: text,
            mode: findState.mode,
            caseSensitive: findState.isCaseSensitive
        )
        findState.updateMatches(result.matches, errorMessage: result.errorMessage)
        editorState.applyFindHighlights?(findState.matches, findState.currentMatchIndex)
    }

    /// Replaces the current match and advances to the next.
    private func performReplace() {
        let findState = editorState.findReplaceState
        guard let index = findState.currentMatchIndex else { return }

        guard let newText = findReplaceEngine.replaceOne(
            at: index,
            matches: findState.matches,
            replacement: findState.replaceText,
            in: text,
            mode: findState.mode,
            query: findState.searchQuery,
            caseSensitive: findState.isCaseSensitive
        ) else { return }

        // Route through coordinator for undo tracking per [A-022]
        if let replaceAction = editorState.performReplaceText {
            replaceAction(newText)
        } else {
            text = newText
        }
        updateFindMatches()
    }

    /// Replaces all matches as a single undo step per FEAT-017 AC-3.
    /// Routes through the coordinator's text storage replacement so the
    /// entire operation is a single undo group.
    private func performReplaceAll() {
        let findState = editorState.findReplaceState
        guard !findState.matches.isEmpty else { return }

        let newText = findReplaceEngine.replaceAll(
            matches: findState.matches,
            replacement: findState.replaceText,
            in: text,
            mode: findState.mode,
            query: findState.searchQuery,
            caseSensitive: findState.isCaseSensitive
        )

        // Route through coordinator for single undo group per FEAT-017 AC-3
        if let replaceAction = editorState.performReplaceText {
            replaceAction(newText)
        } else {
            text = newText
        }
        updateFindMatches()
    }
}

/// Bundles image drop/paste state into a single value type per FEAT-074.
/// Replaces three separate @State properties (pendingImageData, pendingImageFilename, showingImageSavePicker).
struct ImageDropState {
    var data: Data?
    var filename: String = ""
    var showingPicker = false
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

#if os(iOS)
/// UIKit share sheet wrapper for presenting `UIActivityViewController` in SwiftUI.
private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
