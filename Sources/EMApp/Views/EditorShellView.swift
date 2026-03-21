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
    @Environment(ReviewPromptCoordinator.self) private var reviewPromptCoordinator
    @State private var editorState = EditorState()
    @State private var text = ""
    @State private var showDoctorPopover = false
    @State private var conflictManager: FileConflictManager?
    @State private var autoSaveManager: AutoSaveManager?
    @State private var showingSaveElsewherePanel = false
    @State private var currentLineEnding: LineEnding = .lf
    @State private var improveCoordinator: ImproveWritingCoordinator?
    @State private var improveService: ImproveWritingService?
    @State private var summarizeCoordinator: SummarizeCoordinator?
    @State private var summarizeService: SummarizeService?
    @State private var ghostTextCoordinator: GhostTextCoordinator?
    @State private var ghostTextService: GhostTextService?
    @State private var showingOpenFilePicker = false
    @State private var showingNewFilePicker = false
    @State private var isProSubscriber = false
    @State private var showingProUpgrade = false
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
                onLinkTap: { url in handleLinkTap(url) },
                improveCoordinator: improveCoordinator,
                ghostTextCoordinator: ghostTextCoordinator,
                isAutoFormatHeadingSpacing: settings.isAutoFormatHeadingSpacing,
                isAutoFormatBlankLineSeparation: settings.isAutoFormatBlankLineSeparation,
                isAutoFormatTrailingWhitespaceTrim: settings.trailingWhitespaceBehavior == .strip,
                onAIAssist: { editorState.focusAISection = true },
                onToggleSourceView: { toggleSourceView() },
                onOpenFile: { openFileFromEditor() },
                onNewFile: { newFileFromEditor() },
                onCloseFile: { closeFile() },
                onFindReplace: { toggleFindReplace() },
                showAIContextMenuActions: aiProviderManager.shouldShowAIUI,
                onContextMenuImprove: { startImprove() },
                onContextMenuSummarize: { startSummarize() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Document editor")
            .accessibilityHint("Edit your markdown document here")
            .overlay(alignment: .top) {
                // Floating action bar per FEAT-054 and [A-023].
                // Positioned above the selection via GeometryReader + selectionRect.
                // Falls back to top-center when selection rect is unavailable.
                floatingActionBarOverlay
            }

            // Summary popover per FEAT-055
            .popover(
                isPresented: Binding(
                    get: { summarizeCoordinator?.isPopoverPresented ?? false },
                    set: { newValue in
                        if !newValue { summarizeCoordinator?.dismiss() }
                    }
                )
            ) {
                if let coordinator = summarizeCoordinator {
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
        #endif
        .alert(
            "Pro AI Feature",
            isPresented: $showingProUpgrade
        ) {
            Button("Learn More") {
                router.showSubscriptionOffer()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Translate and Tone adjustment are Pro AI features powered by cloud models. Subscribe to unlock them.")
        }
        .onAppear {
            loadFileContent()
            startConflictMonitoring()
            startAutoSave()
            setupImproveWriting()
        }
        .task {
            // Check Pro subscription status for floating bar badge per FEAT-054 AC-3.
            isProSubscriber = await aiProviderManager.checkProSubscription()
        }
        .onDisappear {
            conflictManager?.stopMonitoring()
            // Cancel any active AI sessions on file close
            improveCoordinator?.cancel()
            summarizeCoordinator?.cancel()
            ghostTextCoordinator?.cancel()
            // Clear doctor state on file close per FEAT-005 AC-3
            editorState.clearDiagnostics()
            // Save, then release per-scene file coordination resources per [A-028].
            // closeCurrentFile() is idempotent — safe if closeFile() already ran.
            // This handles window-close in Stage Manager per FEAT-015 AC-7.
            let saveManager = autoSaveManager
            let openCoordinator = fileOpenCoordinator
            Task { @MainActor in
                await saveManager?.saveNow()
                saveManager?.stop()
                openCoordinator.closeCurrentFile()
            }
        }
        .onChange(of: settings.isGhostTextEnabled) { _, newValue in
            ghostTextCoordinator?.isEnabled = newValue
            if !newValue {
                ghostTextCoordinator?.cancel()
            }
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
        .onChange(of: autoSaveManager?.savedWhileInBackground) { _, newValue in
            if newValue == true {
                #if canImport(UIKit)
                HapticFeedback.trigger(.autoSaveConfirm)
                #endif
                autoSaveManager?.clearBackgroundSaveFlag()
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
        autoSave.contentProvider = { [self] in
            var content = text
            if settings.isAutoFormatEnsureTrailingNewline {
                content = ensureTrailingNewline(content)
            }
            return content
        }
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
            await autoSaveManager?.saveNow()
            fileOpenCoordinator.closeCurrentFile()
            router.popToHome()
        }
    }

    /// Handles a file picked via Cmd+O from the editor.
    private func handleFilePickedFromEditor(_ url: URL) {
        // Close current file before opening the new one
        fileOpenCoordinator.closeCurrentFile()
        autoSaveManager?.stop()
        conflictManager?.stopMonitoring()

        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened, .alreadyOpen:
            loadFileContent()
            startConflictMonitoring()
            startAutoSave()
        case .failed:
            router.popToHome()
        }
    }

    /// Handles a file created via Cmd+N from the editor.
    private func handleFileCreatedFromEditor(_ url: URL) {
        fileOpenCoordinator.closeCurrentFile()
        autoSaveManager?.stop()
        conflictManager?.stopMonitoring()

        let attempt = fileCreateCoordinator.createFile(at: url)
        switch attempt {
        case .created:
            if let content = fileCreateCoordinator.createdFileContent {
                fileOpenCoordinator.setFileContent(content, url: url)
                fileCreateCoordinator.clearCreatedFile()
            }
            loadFileContent()
            startConflictMonitoring()
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

    // MARK: - AI Improve Writing per FEAT-011

    /// Creates the improve writing coordinator and service per FEAT-011.
    /// Also creates the summarize coordinator and service per FEAT-055.
    /// Wires EMAI → EMEditor via EMCore update types, maintaining
    /// module isolation per [A-015].
    private func setupImproveWriting() {
        guard aiProviderManager.shouldShowAIUI else { return }
        let coordinator = ImproveWritingCoordinator(editorState: editorState)
        improveCoordinator = coordinator
        improveService = ImproveWritingService(providerManager: aiProviderManager)

        // FEAT-055: Summarize
        summarizeCoordinator = SummarizeCoordinator(editorState: editorState)
        summarizeService = SummarizeService(providerManager: aiProviderManager)

        // FEAT-056: Ghost Text (Continue Writing)
        setupGhostText()
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

    // MARK: - Floating Action Bar per FEAT-054

    /// Whether the floating action bar should be visible.
    private var shouldShowFloatingBar: Bool {
        guard aiProviderManager.shouldShowAIUI else { return false }
        if let coordinator = improveCoordinator, coordinator.diffState.isActive {
            return true
        }
        return editorState.selectedRange.length > 0
    }

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
        if shouldShowFloatingBar, let coordinator = improveCoordinator {
            FloatingActionBar(
                diffPhase: coordinator.diffState.phase,
                actions: FloatingActionBarActions(
                    onImprove: { startImprove() },
                    onSummarize: { startSummarize() },
                    onTranslate: { /* Pro action — wired in future FEAT-024 */ },
                    onTone: { /* Pro action — wired in future FEAT-023 */ },
                    onProUpgrade: { showingProUpgrade = true },
                    onAccept: {
                        coordinator.accept()
                        reviewPromptCoordinator.requestReviewIfEligible()
                    },
                    onDismiss: { coordinator.dismiss() },
                    onBold: { editorState.performBold?() },
                    onItalic: { editorState.performItalic?() },
                    onLink: { editorState.performLink?() }
                ),
                showAIActions: aiProviderManager.shouldShowAIUI,
                isProSubscriber: isProSubscriber,
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
    /// Uses selectionRect when available to position above the selection;
    /// otherwise stays at the default overlay top position.
    private var floatingBarYOffset: CGFloat {
        guard let selRect = editorState.selectionRect else { return 0 }
        // Place the bar above the selection. selectionRect.minY is relative
        // to the text view's superview, which is the overlay's coordinate space.
        let targetY = max(selRect.minY - 52, 0)
        return targetY
    }

    // MARK: - AI Summarize per FEAT-055

    /// Starts the AI summarize flow per FEAT-055 AC-1.
    /// User selects text (or full document), taps Summarize → AI streams summary into popover.
    private func startSummarize() {
        guard let coordinator = summarizeCoordinator,
              let service = summarizeService else { return }

        let selectedRange = editorState.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        let selectedText = String(text[swiftRange])

        // Determine if the entire document is selected for longer summary per AC-1.
        let isFullDocument = selectedRange.length >= (text as NSString).length

        let stream = service.startSummarizing(
            selectedText: selectedText,
            isFullDocument: isFullDocument
        )
        coordinator.startSummarize(updateStream: stream)
    }

    // MARK: - AI Ghost Text per FEAT-056

    /// Creates and wires the ghost text coordinator and service per FEAT-056.
    /// Connects the coordinator's `onRequestGhostText` closure to the EMAI service,
    /// maintaining module isolation per [A-015].
    private func setupGhostText() {
        guard aiProviderManager.shouldShowAIUI else { return }

        let service = GhostTextService(providerManager: aiProviderManager)
        ghostTextService = service

        let coordinator = GhostTextCoordinator(editorState: editorState)
        coordinator.isEnabled = settings.isGhostTextEnabled

        // Wire the coordinator to request ghost text from EMAI when the pause timer fires.
        // This closure bridges EMEditor → EMAI without direct import per [A-015].
        coordinator.onRequestGhostText = { [weak service] precedingText in
            guard let service else { return nil }
            return service.startGenerating(precedingText: precedingText)
        }

        ghostTextCoordinator = coordinator
    }

    /// Inserts text at the current cursor position per FEAT-055 AC-2.
    /// Uses `Range(NSRange, in:)` for correct UTF-16 → String.Index conversion.
    private func insertTextAtCursor(_ insertedText: String) {
        let cursorLocation = editorState.selectedRange.location
        let nsRange = NSRange(location: cursorLocation, length: 0)
        guard let insertRange = Range(nsRange, in: text) else { return }

        text.insert(contentsOf: insertedText, at: insertRange.lowerBound)
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
