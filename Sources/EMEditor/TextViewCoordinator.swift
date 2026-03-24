/// Coordinator that bridges EMTextView delegate callbacks to EditorState.
/// Handles text changes, selection updates, scroll tracking,
/// keystroke performance instrumentation per [A-037],
/// and markdown rendering per FEAT-003 and [A-018].

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMDoctor
import EMFormatter
import EMParser

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "coordinator")

// MARK: - iOS Coordinator

#if canImport(UIKit)

/// Coordinates between UITextView delegate events and the SwiftUI binding/EditorState.
@MainActor
public final class TextViewCoordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {

    /// Signpost log for measuring keystroke-to-render per [D-PERF-2].
    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "keystroke"
    )

    var text: ValueBinding<String>
    var editorState: EditorState
    var onTextChange: ((String) -> Void)?

    /// Current rendering configuration. Updated from the bridge.
    var renderConfig: RenderConfiguration?

    /// Weak reference to the managed text view for ImproveWritingTextViewDelegate.
    weak var managedTextView: EMTextView?

    /// Formatting engine for auto-formatting per FEAT-004, FEAT-052, and [A-051].
    /// Rebuilt when formatting settings change via `updateFormattingSettings`.
    private var formattingEngine = FormattingEngine.defaultFormattingEngine()

    /// Cached formatting setting values for change detection.
    private var cachedHeadingSpacing: Bool = true
    private var cachedBlankLineSeparation: Bool = true
    private var cachedTrailingWhitespaceTrim: Bool = true

    /// Updates the formatting engine when settings change per FEAT-053 AC-6.
    func updateFormattingSettings(
        isHeadingSpacingEnabled: Bool,
        isBlankLineSeparationEnabled: Bool,
        isTrailingWhitespaceTrimEnabled: Bool
    ) {
        guard isHeadingSpacingEnabled != cachedHeadingSpacing
           || isBlankLineSeparationEnabled != cachedBlankLineSeparation
           || isTrailingWhitespaceTrimEnabled != cachedTrailingWhitespaceTrim else { return }
        cachedHeadingSpacing = isHeadingSpacingEnabled
        cachedBlankLineSeparation = isBlankLineSeparationEnabled
        cachedTrailingWhitespaceTrim = isTrailingWhitespaceTrimEnabled
        formattingEngine = FormattingEngine.defaultFormattingEngine(
            isHeadingSpacingEnabled: isHeadingSpacingEnabled,
            isBlankLineSeparationEnabled: isBlankLineSeparationEnabled,
            isTrailingWhitespaceTrimEnabled: isTrailingWhitespaceTrimEnabled
        )
    }

    /// Prevents feedback loops when programmatically updating text.
    private var isUpdatingFromBinding = false

    /// Parser for markdown text per [A-003].
    private let parser = MarkdownParser()

    /// Renderer for AST → styled attributes per [A-018].
    private let renderer = MarkdownRenderer()

    /// Cursor mapper for view toggle per FEAT-050 and [A-021].
    private let cursorMapper = CursorMapper()

    /// Most recent AST from a full parse.
    private var currentAST: MarkdownAST?

    /// Debounce task for full re-parse per [A-017].
    private var parseDebounceTask: Task<Void, Never>?

    /// Debounce interval for full re-parse (300ms per [A-017]).
    private let parseDebounceInterval: UInt64 = 300_000_000

    /// Document Doctor coordinator per FEAT-005.
    lazy var doctorCoordinator = DoctorCoordinator(editorState: editorState)

    /// Ghost text coordinator per FEAT-056.
    /// Set by TextViewBridge when a ghost text coordinator is provided.
    weak var ghostTextCoordinator: GhostTextCoordinator?

    /// Smart completion coordinator per FEAT-025.
    /// Set by TextViewBridge when a smart completion coordinator is provided.
    weak var smartCompletionCoordinator: SmartCompletionCoordinator?

    /// Whether this is the first render (triggers immediate doctor evaluation
    /// and file-open animation per FEAT-014 AC-11).
    private var isFirstRender = true

    /// Render transition animator per FEAT-014 and [A-020].
    private let renderAnimator = RenderTransitionAnimator()

    /// Signpost for toggle latency measurement per FEAT-050.
    private let toggleSignpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "toggle"
    )

    init(text: ValueBinding<String>, editorState: EditorState) {
        self.text = text
        self.editorState = editorState
        super.init()

        // Wire image loader callback to trigger re-render when async images complete per FEAT-048.
        renderer.imageLoader.onImageLoaded = { [weak self] _ in
            self?.requestRerender()
        }
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }

        let newText = textView.text ?? ""
        text.wrappedValue = newText
        onTextChange?(newText)

        // Notify ghost text coordinator of text change per FEAT-056.
        // This both dismisses active ghost text (AC-3) and resets the pause timer (AC-1).
        ghostTextCoordinator?.textDidChange()

        // Notify smart completion coordinator of text change per FEAT-025.
        // Triggers structure-aware completion on Enter after markdown patterns.
        smartCompletionCoordinator?.textDidChange()

        // Schedule debounced re-parse and render per [A-017]
        if let emTextView = textView as? EMTextView {
            scheduleRender(for: emTextView)
        }
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        editorState.updateSelectedRange(range)

        // Update selection word count per [A-055]
        if range.length > 0, let text = textView.text,
           let swiftRange = Range(range, in: text) {
            let selectedText = String(text[swiftRange])
            let count = wordCount(in: selectedText)
            editorState.updateSelectionWordCount(count)
        } else {
            editorState.updateSelectionWordCount(nil)
        }

        // Update selection rect for floating action bar positioning per FEAT-054.
        updateSelectionRect(for: textView)
    }

    /// Computes the rect of the first line of the selection in the text view's
    /// coordinate space and updates EditorState for floating bar positioning.
    private func updateSelectionRect(for textView: UITextView) {
        guard textView.selectedRange.length > 0,
              let start = textView.selectedTextRange?.start,
              let end = textView.selectedTextRange?.end,
              let selRange = textView.textRange(from: start, to: end) else {
            editorState.updateSelectionRect(nil)
            return
        }
        // Use first rect of the selection range for positioning above.
        let firstRect = textView.firstRect(for: selRange)
        guard !firstRect.isNull, !firstRect.isInfinite else {
            editorState.updateSelectionRect(nil)
            return
        }
        // Convert to the text view's superview coordinates for overlay alignment.
        let converted = textView.convert(firstRect, to: textView.superview)
        editorState.updateSelectionRect(converted)
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        // Start keystroke performance signpost per [A-037].
        signpost.begin("keystroke")

        // Ghost text Tab accept per FEAT-056 AC-2.
        // Intercept Tab before formatting engine when ghost text is active.
        if text == "\t",
           let coordinator = ghostTextCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            signpost.end("keystroke")
            return false
        }

        // Smart completion Tab accept per FEAT-025 AC-2.
        if text == "\t",
           let coordinator = smartCompletionCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            signpost.end("keystroke")
            return false
        }

        // Record replacement text for smart completion Enter detection per FEAT-025.
        smartCompletionCoordinator?.willChangeText(replacementText: text)

        // CJK IME: if the text view has marked text (composing),
        // let the input system handle it without interference per AC-3.
        if textView.markedTextRange != nil {
            return true
        }

        // Auto-format keystroke interception per [A-051], FEAT-004, and FEAT-052.
        if let trigger = formattingTrigger(for: text, rangeLength: range.length) {
            let fullText = textView.text ?? ""
            if let swiftRange = Range(range, in: fullText) {
                let context = FormattingContext(
                    text: fullText,
                    cursorPosition: swiftRange.lowerBound,
                    trigger: trigger,
                    ast: currentAST,
                    replacementRange: swiftRange
                )
                if let mutation = formattingEngine.evaluate(context) {
                    applyMutation(mutation, to: textView)
                    return false
                }
            }
        }

        return true
    }

    /// Maps replacement text and range to a formatting trigger.
    private func formattingTrigger(for replacementText: String, rangeLength: Int) -> FormattingTrigger? {
        switch replacementText {
        case "\n": return .enter
        case "\t": return .tab
        default:
            if replacementText.isEmpty && rangeLength > 0 {
                return .delete
            }
            if !replacementText.isEmpty {
                return .characterInput(replacementText)
            }
            return nil
        }
    }

    /// Applies a TextMutation to the text view as a discrete undo group per [A-022].
    private func applyMutation(_ mutation: TextMutation, to textView: UITextView) {
        let fullText = textView.text ?? ""

        // Convert String.Index range to NSRange for UITextView
        let nsRange = NSRange(mutation.range, in: fullText)

        // Build the result text to resolve cursorAfter index
        let resultText = String(fullText[..<mutation.range.lowerBound])
            + mutation.replacement
            + String(fullText[mutation.range.upperBound...])
        let cursorUTF16Offset = resultText.utf16.distance(
            from: resultText.startIndex,
            to: mutation.cursorAfter
        )

        // Register undo — each auto-format is a discrete undo step per [A-022]
        let undoManager = editorState.undoManager
        let oldText = String(fullText[mutation.range])
        let replacementNSRange = NSRange(
            location: nsRange.location,
            length: (mutation.replacement as NSString).length
        )

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: textView) { [weak self] tv in
            if let textRange = Range(replacementNSRange, in: tv.text ?? "") {
                let revert = TextMutation(
                    range: textRange,
                    replacement: oldText,
                    cursorAfter: textRange.lowerBound
                )
                self?.applyMutation(revert, to: tv)
            }
        }
        undoManager.endUndoGrouping()

        // Apply the text change
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: nsRange, with: mutation.replacement)
        textView.textStorage.endEditing()

        // Update cursor position
        textView.selectedRange = NSRange(location: cursorUTF16Offset, length: 0)

        // Update binding and trigger re-render
        let newText = textView.text ?? ""
        text.wrappedValue = newText
        onTextChange?(newText)
        if let emTextView = textView as? EMTextView {
            scheduleRender(for: emTextView)
        }

        // Haptic feedback per [A-062]
        if let haptic = mutation.hapticStyle {
            HapticFeedback.trigger(haptic)
        }

        signpost.end("keystroke")
    }

    /// Custom attribute key for find match highlighting per FEAT-017.
    private static let findHighlightKey = NSAttributedString.Key("com.easymarkdown.findHighlight")

    /// Applies find match highlighting to the text storage per FEAT-017.
    /// All matches get a subtle background. The current match gets a stronger highlight.
    func applyFindHighlights(_ matches: [FindMatch], currentIndex: Int?, in textView: UITextView) {
        let storage = textView.textStorage
        let fullText = textView.text ?? ""
        let fullNSRange = NSRange(location: 0, length: (fullText as NSString).length)

        // Clear previous highlights
        storage.beginEditing()
        storage.removeAttribute(Self.findHighlightKey, range: fullNSRange)
        storage.removeAttribute(.backgroundColor, range: fullNSRange)

        // Apply highlights for all matches
        for (i, match) in matches.enumerated() {
            let nsRange = NSRange(match.range, in: fullText)
            let color: PlatformColor
            if i == currentIndex {
                color = PlatformColor.systemYellow.withAlphaComponent(0.5)
            } else {
                color = PlatformColor.systemYellow.withAlphaComponent(0.2)
            }
            storage.addAttribute(.backgroundColor, value: color, range: nsRange)
            storage.addAttribute(Self.findHighlightKey, value: true, range: nsRange)
        }
        storage.endEditing()

        // Scroll to current match
        if let idx = currentIndex, idx < matches.count {
            let nsRange = NSRange(matches[idx].range, in: fullText)
            textView.scrollRangeToVisible(nsRange)
        }
    }

    /// Replaces the entire document text as a single undo group per FEAT-017 AC-3.
    /// Routes through text storage so the undo manager tracks the change.
    func handleReplaceText(_ newText: String, in textView: UITextView) {
        let oldText = textView.text ?? ""
        guard oldText != newText else { return }

        let fullRange = NSRange(location: 0, length: (oldText as NSString).length)
        let undoManager = editorState.undoManager

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: textView) { [weak self] tv in
            self?.handleReplaceText(oldText, in: tv)
        }
        undoManager.endUndoGrouping()

        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: fullRange, with: newText)
        textView.textStorage.endEditing()

        text.wrappedValue = newText
        onTextChange?(newText)
        if let emTextView = textView as? EMTextView {
            scheduleRender(for: emTextView)
        }
    }

    /// Navigates the cursor to the start of a 1-based line number and scrolls
    /// it into view per FEAT-022 AC-2.
    func handleNavigateToLine(_ line: Int, in textView: UITextView) {
        let fullText = textView.text ?? ""
        let offset = utf16OffsetForLine(line, in: fullText)
        let nsRange = NSRange(location: offset, length: 0)
        textView.selectedRange = nsRange
        textView.scrollRangeToVisible(nsRange)
        editorState.updateSelectedRange(nsRange)
    }

    /// Returns the UTF-16 offset of the start of a 1-based line number.
    private func utf16OffsetForLine(_ line: Int, in text: String) -> Int {
        guard line > 1 else { return 0 }
        var currentLine = 1
        for (i, char) in text.utf16.enumerated() {
            if char == 0x0A { // newline
                currentLine += 1
                if currentLine == line {
                    return i + 1
                }
            }
        }
        return text.utf16.count
    }

    /// Handles Shift-Tab for list outdent per FEAT-004.
    /// Called from EMTextView's key command handler.
    /// Returns true if the event was consumed by a formatting rule.
    func handleShiftTab(in textView: UITextView) -> Bool {
        signpost.begin("keystroke")
        let fullText = textView.text ?? ""
        let range = textView.selectedRange
        guard let cursorStart = Range(range, in: fullText)?.lowerBound else {
            signpost.end("keystroke")
            return false
        }
        let context = FormattingContext(
            text: fullText,
            cursorPosition: cursorStart,
            trigger: .shiftTab,
            ast: currentAST
        )
        guard let mutation = formattingEngine.evaluate(context) else {
            signpost.end("keystroke")
            return false
        }
        applyMutation(mutation, to: textView)
        return true
    }

    // MARK: - Formatting Shortcuts per FEAT-009

    /// Toggles bold markdown markers around the selection.
    func handleBold(in textView: UITextView) {
        if let mutation = inlineMarkerMutation(marker: "**", fullText: textView.text ?? "", selectedRange: textView.selectedRange) {
            applyMutation(mutation, to: textView)
        }
    }

    /// Toggles italic markdown markers around the selection.
    func handleItalic(in textView: UITextView) {
        if let mutation = inlineMarkerMutation(marker: "*", fullText: textView.text ?? "", selectedRange: textView.selectedRange) {
            applyMutation(mutation, to: textView)
        }
    }

    /// Toggles inline code markers around the selection.
    func handleCode(in textView: UITextView) {
        if let mutation = inlineMarkerMutation(marker: "`", fullText: textView.text ?? "", selectedRange: textView.selectedRange) {
            applyMutation(mutation, to: textView)
        }
    }

    /// Inserts a markdown link around the selection.
    func handleLinkInsert(in textView: UITextView) {
        if let mutation = linkInsertMutation(fullText: textView.text ?? "", selectedRange: textView.selectedRange) {
            applyMutation(mutation, to: textView)
        }
    }

    // MARK: - Interactive Elements (FEAT-049)

    /// Handler for link taps. When set, receives all link taps (including relative links).
    /// When nil, links open in the system browser by default.
    var onLinkTap: ((URL) -> Void)?

    /// Toggles a task list checkbox at the given range per FEAT-049.
    /// Replaces `[ ]` with `[x]` or `[x]`/`[X]` with `[ ]` as a single undo step per AC-2.
    func toggleCheckbox(at checkboxRange: NSRange, in textView: UITextView) {
        let fullText = textView.text ?? ""
        guard let swiftRange = Range(checkboxRange, in: fullText) else { return }
        let current = String(fullText[swiftRange])

        let replacement: String
        if current == "[ ]" {
            replacement = "[x]"
        } else if current == "[x]" || current == "[X]" {
            replacement = "[ ]"
        } else {
            return
        }

        let cursorAfter = swiftRange.upperBound
        let mutation = TextMutation(
            range: swiftRange,
            replacement: replacement,
            cursorAfter: cursorAfter,
            hapticStyle: .listContinuation
        )
        applyMutation(mutation, to: textView)
    }

    /// Opens a link URL per FEAT-049 AC-3.
    /// Delegates to onLinkTap callback if set, otherwise opens in system browser.
    func handleLinkTap(url: URL) {
        if let onLinkTap {
            onLinkTap(url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Context Menu per FEAT-058

    /// Whether AI actions should appear in the edit/context menu per FEAT-058.
    var showAIContextMenuActions: Bool = false

    /// Handler for AI Improve from context menu per FEAT-058.
    var onContextMenuImprove: (() -> Void)?

    /// Handler for AI Summarize from context menu per FEAT-058.
    var onContextMenuSummarize: (() -> Void)?

    /// Builds the edit menu with AI actions injected per FEAT-058 AC-3.
    /// Called on right-click (trackpad), long-press, or keyboard (Cmd+A → right-click).
    /// System-provided Cut, Copy, Paste, Look Up are in suggestedActions.
    public func textView(
        _ textView: UITextView,
        editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        var actions = suggestedActions

        // Add AI actions when text is selected per FEAT-058 AC-3
        if range.length > 0 && showAIContextMenuActions {
            let improveAction = UIAction(
                title: NSLocalizedString("Improve Writing", comment: "Context menu AI action"),
                image: UIImage(systemName: "wand.and.stars")
            ) { [weak self] _ in
                self?.onContextMenuImprove?()
            }

            let summarizeAction = UIAction(
                title: NSLocalizedString("Summarize", comment: "Context menu AI action"),
                image: UIImage(systemName: "text.badge.minus")
            ) { [weak self] _ in
                self?.onContextMenuSummarize?()
            }

            let aiMenu = UIMenu(
                title: NSLocalizedString("AI", comment: "AI context menu section"),
                image: UIImage(systemName: "sparkles"),
                children: [improveAction, summarizeAction]
            )

            actions.append(aiMenu)
        }

        return UIMenu(children: actions)
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        editorState.updateScrollOffset(scrollView.contentOffset.y)
    }

    // MARK: - Programmatic text updates

    /// Update the text view's content from the binding without triggering delegate callbacks.
    /// Returns true if text was actually changed.
    @discardableResult
    func updateTextView(_ textView: EMTextView, with newText: String) -> Bool {
        guard textView.text != newText else { return false }
        isUpdatingFromBinding = true
        textView.text = newText
        isUpdatingFromBinding = false
        return true
    }

    // MARK: - View Mode Toggle per FEAT-050 and FEAT-014

    /// Performs an animated view mode toggle with cursor mapping per [A-021] and FEAT-014.
    /// Called from TextViewBridge when `isSourceView` changes.
    /// Animates The Render transition using snapshot-based Core Animation per [A-020].
    func handleViewModeToggle(for textView: EMTextView, toSourceView: Bool) {
        toggleSignpost.begin("toggle")

        guard let config = renderConfig else {
            toggleSignpost.end("toggle")
            return
        }

        let sourceText = textView.text ?? ""

        // Re-parse to get fresh AST for cursor mapping
        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

        // Map cursor position between views per [A-021]
        let currentSelection = textView.selectedRange
        let mappedSelection: NSRange
        if toSourceView {
            mappedSelection = cursorMapper.mapRichToSource(
                selectedRange: currentSelection,
                text: sourceText,
                ast: parseResult.ast
            )
        } else {
            mappedSelection = cursorMapper.mapSourceToRich(
                selectedRange: currentSelection,
                text: sourceText,
                ast: parseResult.ast
            )
        }

        // Extract syntax markers for The Render animation per FEAT-014
        let markers = RenderElementExtractor.extract(
            from: parseResult.ast,
            sourceText: sourceText
        )

        let direction: TransitionDirection = toSourceView ? .richToSource : .sourceToRich

        // Perform animated transition per [A-020]
        renderAnimator.performTransition(
            textView: textView,
            markers: markers,
            applyRendering: { [weak self] in
                guard let self else { return }
                applyRendering(
                    to: textView,
                    ast: parseResult.ast,
                    sourceText: sourceText,
                    config: config,
                    restoringSelection: mappedSelection
                )
            },
            direction: direction
        ) { [weak self] in
            self?.toggleSignpost.end("toggle")
            self?.doctorCoordinator.scheduleEvaluation(
                text: sourceText, ast: parseResult.ast
            )
        }
    }

    // MARK: - Rendering per FEAT-003

    /// Requests an immediate parse and render. Called on initial load and view mode toggle.
    /// On first render in rich mode, plays The Render file-open animation per FEAT-014 AC-11.
    func requestRender(for textView: EMTextView) {
        guard let config = renderConfig else { return }

        let sourceText = textView.text ?? ""
        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

        // File-open animation: first render in rich mode plays source→rich transition per FEAT-014 AC-11
        if isFirstRender && !config.isSourceView && !sourceText.isEmpty {
            isFirstRender = false

            // Apply source rendering first to establish the "before" state
            let sourceConfig = RenderConfiguration(
                typeScale: config.typeScale,
                colors: config.colors,
                isSourceView: true,
                colorVariant: config.colorVariant,
                layoutMetrics: config.layoutMetrics,
                documentURL: config.documentURL
            )
            applyRendering(
                to: textView, ast: parseResult.ast,
                sourceText: sourceText, config: sourceConfig
            )
            textView.layoutIfNeeded()

            // Extract markers and animate to rich rendering
            let markers = RenderElementExtractor.extract(
                from: parseResult.ast, sourceText: sourceText
            )
            renderAnimator.performTransition(
                textView: textView,
                markers: markers,
                applyRendering: { [weak self] in
                    guard let self else { return }
                    applyRendering(
                        to: textView, ast: parseResult.ast,
                        sourceText: sourceText, config: config
                    )
                },
                direction: .sourceToRich
            ) { [weak self] in
                self?.doctorCoordinator.evaluateImmediately(
                    text: sourceText, ast: parseResult.ast
                )
            }
            return
        }

        applyRendering(to: textView, ast: parseResult.ast, sourceText: sourceText, config: config)

        // Run Document Doctor after parse per FEAT-005
        if isFirstRender {
            isFirstRender = false
            doctorCoordinator.evaluateImmediately(text: sourceText, ast: parseResult.ast)
        } else {
            doctorCoordinator.scheduleEvaluation(text: sourceText, ast: parseResult.ast)
        }
    }

    /// Schedules a debounced parse and render after text changes per [A-017].
    private func scheduleRender(for textView: EMTextView) {
        parseDebounceTask?.cancel()

        parseDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.parseDebounceInterval ?? 300_000_000)
            } catch {
                return // Cancelled
            }

            guard let self, !Task.isCancelled else { return }
            self.requestRender(for: textView)
        }
    }

    /// Applies rendered attributes to the text view's text storage.
    private func applyRendering(
        to textView: EMTextView,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration
    ) {
        applyRendering(
            to: textView,
            ast: ast,
            sourceText: sourceText,
            config: config,
            restoringSelection: textView.selectedRange
        )
    }

    /// Applies rendered attributes to the text view's text storage,
    /// restoring the given selection and scroll position.
    private func applyRendering(
        to textView: EMTextView,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration,
        restoringSelection: NSRange
    ) {
        let textStorage = textView.textStorage
        guard textStorage.length == sourceText.utf16.count else {
            logger.warning("Text storage length mismatch — skipping render")
            return
        }

        let scrollOffset = textView.contentOffset

        textStorage.beginEditing()
        renderer.render(
            into: textStorage,
            ast: ast,
            sourceText: sourceText,
            config: config
        )
        textStorage.endEditing()

        // Restore selection and scroll
        textView.selectedRange = restoringSelection
        textView.setContentOffset(scrollOffset, animated: false)

        // Reapply find highlights if find bar is active per FEAT-017
        let findState = editorState.findReplaceState
        if findState.isVisible, !findState.matches.isEmpty {
            applyFindHighlights(findState.matches, currentIndex: findState.currentMatchIndex, in: textView)
        }
    }

    // MARK: - Word counting

    /// Word count for selection stats using NLTokenizer for CJK-aware segmentation per [A-055].
    private func wordCount(in text: String) -> Int {
        DocumentStatsCalculator.countWords(in: text)
    }
}

// MARK: - ImproveWritingTextViewDelegate (iOS)

extension TextViewCoordinator: ImproveWritingTextViewDelegate {

    public func currentText() -> String {
        managedTextView?.text ?? text.wrappedValue
    }

    public func currentSelectedRange() -> NSRange {
        managedTextView?.selectedRange ?? editorState.selectedRange
    }

    public func textStorage() -> NSMutableAttributedString? {
        managedTextView?.textStorage
    }

    public func baseFont() -> PlatformFont {
        renderConfig?.typeScale.body ?? PlatformFont.systemFont(ofSize: 17)
    }

    public func replaceText(in range: NSRange, with replacement: String) {
        guard let textView = managedTextView else { return }
        let fullText = textView.text ?? ""
        guard let swiftRange = Range(range, in: fullText) else { return }
        var mutable = fullText
        mutable.replaceSubrange(swiftRange, with: replacement)
        textView.text = mutable
        text.wrappedValue = mutable
        onTextChange?(mutable)
    }

    public func requestRerender() {
        guard let textView = managedTextView else { return }
        requestRender(for: textView)
    }
}

// MARK: - GhostTextViewDelegate (iOS)

extension TextViewCoordinator: GhostTextViewDelegate {

    public func isCursorInsideCodeBlock() -> Bool {
        guard let ast = currentAST else { return false }
        let text = currentText()
        let cursorLocation = currentSelectedRange().location

        // Convert UTF-16 offset to line:column SourcePosition
        let nsString = text as NSString
        guard cursorLocation <= nsString.length else { return false }
        let prefix = nsString.substring(to: cursorLocation)
        let lines = prefix.components(separatedBy: "\n")
        let line = lines.count
        let column = (lines.last?.utf8.count ?? 0) + 1

        let position = SourcePosition(line: line, column: column)
        guard let node = ast.node(at: position) else { return false }

        if case .codeBlock = node.type { return true }
        return false
    }
}

// MARK: - Value binding helper

/// Lightweight get/set binding for coordinator use.
/// Named to avoid collision with SwiftUI.Binding.
public struct ValueBinding<Value> {
    let get: () -> Value
    let set: (Value) -> Void

    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}

// MARK: - macOS Coordinator

#elseif canImport(AppKit)

/// Coordinates between NSTextView delegate events and the SwiftUI binding/EditorState.
@MainActor
public final class TextViewCoordinator: NSObject, NSTextViewDelegate {

    /// Signpost log for measuring keystroke-to-render per [D-PERF-2].
    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "keystroke"
    )

    var text: ValueBinding<String>
    var editorState: EditorState
    var onTextChange: ((String) -> Void)?

    /// Current rendering configuration. Updated from the bridge.
    var renderConfig: RenderConfiguration?

    /// Weak reference to the managed text view for ImproveWritingTextViewDelegate.
    weak var managedTextView: EMTextView?

    /// Formatting engine for auto-formatting per FEAT-004, FEAT-052, and [A-051].
    /// Rebuilt when formatting settings change via `updateFormattingSettings`.
    private var formattingEngine = FormattingEngine.defaultFormattingEngine()

    /// Cached formatting setting values for change detection.
    private var cachedHeadingSpacing: Bool = true
    private var cachedBlankLineSeparation: Bool = true
    private var cachedTrailingWhitespaceTrim: Bool = true

    /// Updates the formatting engine when settings change per FEAT-053 AC-6.
    func updateFormattingSettings(
        isHeadingSpacingEnabled: Bool,
        isBlankLineSeparationEnabled: Bool,
        isTrailingWhitespaceTrimEnabled: Bool
    ) {
        guard isHeadingSpacingEnabled != cachedHeadingSpacing
           || isBlankLineSeparationEnabled != cachedBlankLineSeparation
           || isTrailingWhitespaceTrimEnabled != cachedTrailingWhitespaceTrim else { return }
        cachedHeadingSpacing = isHeadingSpacingEnabled
        cachedBlankLineSeparation = isBlankLineSeparationEnabled
        cachedTrailingWhitespaceTrim = isTrailingWhitespaceTrimEnabled
        formattingEngine = FormattingEngine.defaultFormattingEngine(
            isHeadingSpacingEnabled: isHeadingSpacingEnabled,
            isBlankLineSeparationEnabled: isBlankLineSeparationEnabled,
            isTrailingWhitespaceTrimEnabled: isTrailingWhitespaceTrimEnabled
        )
    }

    private var isUpdatingFromBinding = false

    /// Parser for markdown text per [A-003].
    private let parser = MarkdownParser()

    /// Renderer for AST → styled attributes per [A-018].
    private let renderer = MarkdownRenderer()

    /// Cursor mapper for view toggle per FEAT-050 and [A-021].
    private let cursorMapper = CursorMapper()

    /// Most recent AST from a full parse.
    private var currentAST: MarkdownAST?

    /// Debounce task for full re-parse per [A-017].
    private var parseDebounceTask: Task<Void, Never>?

    /// Debounce interval for full re-parse (300ms per [A-017]).
    private let parseDebounceInterval: UInt64 = 300_000_000

    /// Document Doctor coordinator per FEAT-005.
    lazy var doctorCoordinator = DoctorCoordinator(editorState: editorState)

    /// Ghost text coordinator per FEAT-056.
    /// Set by TextViewBridge when a ghost text coordinator is provided.
    weak var ghostTextCoordinator: GhostTextCoordinator?

    /// Smart completion coordinator per FEAT-025.
    /// Set by TextViewBridge when a smart completion coordinator is provided.
    weak var smartCompletionCoordinator: SmartCompletionCoordinator?

    /// Whether this is the first render (triggers immediate doctor evaluation
    /// and file-open animation per FEAT-014 AC-11).
    private var isFirstRender = true

    /// Render transition animator per FEAT-014 and [A-020].
    private let renderAnimator = RenderTransitionAnimator()

    /// Signpost for toggle latency measurement per FEAT-050.
    private let toggleSignpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "toggle"
    )

    init(text: ValueBinding<String>, editorState: EditorState) {
        self.text = text
        self.editorState = editorState
        super.init()

        // Wire image loader callback to trigger re-render when async images complete per FEAT-048.
        renderer.imageLoader.onImageLoaded = { [weak self] _ in
            self?.requestRerender()
        }
    }

    // MARK: - NSTextViewDelegate

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // Start keystroke performance signpost per [A-037].
        signpost.begin("keystroke")

        // Ghost text Tab accept per FEAT-056 AC-2.
        // Intercept Tab before formatting engine when ghost text is active.
        if replacementString == "\t",
           let coordinator = ghostTextCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            signpost.end("keystroke")
            return false
        }

        // Smart completion Tab accept per FEAT-025 AC-2.
        if replacementString == "\t",
           let coordinator = smartCompletionCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            signpost.end("keystroke")
            return false
        }

        // Record replacement text for smart completion Enter detection per FEAT-025.
        if let replacement = replacementString {
            smartCompletionCoordinator?.willChangeText(replacementText: replacement)
        }

        // CJK IME: if the text view has marked text (composing),
        // let the input system handle it without interference per AC-3.
        if textView.hasMarkedText() {
            return true
        }

        // Auto-format keystroke interception per [A-051], FEAT-004, and FEAT-052.
        if let replacement = replacementString,
           let trigger = formattingTrigger(for: replacement, rangeLength: affectedCharRange.length) {
            let fullText = textView.string
            if let swiftRange = Range(affectedCharRange, in: fullText) {
                let context = FormattingContext(
                    text: fullText,
                    cursorPosition: swiftRange.lowerBound,
                    trigger: trigger,
                    ast: currentAST,
                    replacementRange: swiftRange
                )
                if let mutation = formattingEngine.evaluate(context) {
                    applyMutation(mutation, to: textView)
                    return false
                }
            }
        }

        return true
    }

    /// Maps replacement text and range to a formatting trigger.
    private func formattingTrigger(for replacementText: String, rangeLength: Int) -> FormattingTrigger? {
        switch replacementText {
        case "\n": return .enter
        case "\t": return .tab
        default:
            if replacementText.isEmpty && rangeLength > 0 {
                return .delete
            }
            if !replacementText.isEmpty {
                return .characterInput(replacementText)
            }
            return nil
        }
    }

    /// Applies a TextMutation to the text view as a discrete undo group per [A-022].
    private func applyMutation(_ mutation: TextMutation, to textView: NSTextView) {
        let fullText = textView.string

        // Convert String.Index range to NSRange for NSTextView
        let nsRange = NSRange(mutation.range, in: fullText)

        // Build the result text to resolve cursorAfter index
        let resultText = String(fullText[..<mutation.range.lowerBound])
            + mutation.replacement
            + String(fullText[mutation.range.upperBound...])
        let cursorUTF16Offset = resultText.utf16.distance(
            from: resultText.startIndex,
            to: mutation.cursorAfter
        )

        // Register undo — each auto-format is a discrete undo step per [A-022]
        if let undoManager = textView.undoManager {
            let oldText = String(fullText[mutation.range])
            let replacementNSRange = NSRange(
                location: nsRange.location,
                length: (mutation.replacement as NSString).length
            )

            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: textView) { [weak self] tv in
                if let textRange = Range(replacementNSRange, in: tv.string) {
                    let revert = TextMutation(
                        range: textRange,
                        replacement: oldText,
                        cursorAfter: textRange.lowerBound
                    )
                    self?.applyMutation(revert, to: tv)
                }
            }
            undoManager.endUndoGrouping()
        }

        // Apply the text change
        guard let textStorage = textView.textStorage else { return }
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: nsRange, with: mutation.replacement)
        textStorage.endEditing()

        // Update cursor position
        textView.setSelectedRange(NSRange(location: cursorUTF16Offset, length: 0))

        // Update binding and trigger re-render
        let updatedText = textView.string
        text.wrappedValue = updatedText
        onTextChange?(updatedText)
        if let emTextView = textView as? EMTextView {
            scheduleRender(for: emTextView)
        }

        signpost.end("keystroke")
    }

    /// Custom attribute key for find match highlighting per FEAT-017.
    private static let findHighlightKey = NSAttributedString.Key("com.easymarkdown.findHighlight")

    /// Applies find match highlighting to the text storage per FEAT-017.
    /// All matches get a subtle background. The current match gets a stronger highlight.
    func applyFindHighlights(_ matches: [FindMatch], currentIndex: Int?, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullText = textView.string
        let fullNSRange = NSRange(location: 0, length: (fullText as NSString).length)

        // Clear previous highlights
        storage.beginEditing()
        storage.removeAttribute(Self.findHighlightKey, range: fullNSRange)
        storage.removeAttribute(.backgroundColor, range: fullNSRange)

        // Apply highlights for all matches
        for (i, match) in matches.enumerated() {
            let nsRange = NSRange(match.range, in: fullText)
            let color: PlatformColor
            if i == currentIndex {
                color = PlatformColor.systemYellow.withAlphaComponent(0.5)
            } else {
                color = PlatformColor.systemYellow.withAlphaComponent(0.2)
            }
            storage.addAttribute(.backgroundColor, value: color, range: nsRange)
            storage.addAttribute(Self.findHighlightKey, value: true, range: nsRange)
        }
        storage.endEditing()

        // Scroll to current match
        if let idx = currentIndex, idx < matches.count {
            let nsRange = NSRange(matches[idx].range, in: fullText)
            textView.scrollRangeToVisible(nsRange)
        }
    }

    /// Replaces the entire document text as a single undo group per FEAT-017 AC-3.
    /// Routes through text storage so the undo manager tracks the change.
    func handleReplaceText(_ newText: String, in textView: NSTextView) {
        let oldText = textView.string
        guard oldText != newText else { return }

        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: (oldText as NSString).length)

        if let undoManager = textView.undoManager {
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: textView) { [weak self] tv in
                self?.handleReplaceText(oldText, in: tv)
            }
            undoManager.endUndoGrouping()
        }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: fullRange, with: newText)
        textStorage.endEditing()

        text.wrappedValue = newText
        onTextChange?(newText)
        if let emTextView = textView as? EMTextView {
            scheduleRender(for: emTextView)
        }
    }

    /// Navigates the cursor to the start of a 1-based line number and scrolls
    /// it into view per FEAT-022 AC-2.
    func handleNavigateToLine(_ line: Int, in textView: NSTextView) {
        let fullText = textView.string
        let offset = utf16OffsetForLine(line, in: fullText)
        let nsRange = NSRange(location: offset, length: 0)
        textView.setSelectedRange(nsRange)
        textView.scrollRangeToVisible(nsRange)
        editorState.updateSelectedRange(nsRange)
    }

    /// Returns the UTF-16 offset of the start of a 1-based line number.
    private func utf16OffsetForLine(_ line: Int, in text: String) -> Int {
        guard line > 1 else { return 0 }
        var currentLine = 1
        for (i, char) in text.utf16.enumerated() {
            if char == 0x0A { // newline
                currentLine += 1
                if currentLine == line {
                    return i + 1
                }
            }
        }
        return text.utf16.count
    }

    /// Handles Shift-Tab for list outdent per FEAT-004.
    /// Called from EMTextView's insertBacktab override.
    /// Returns true if the event was consumed by a formatting rule.
    func handleShiftTab(in textView: NSTextView) -> Bool {
        signpost.begin("keystroke")
        let fullText = textView.string
        let range = textView.selectedRange()
        guard let cursorStart = Range(range, in: fullText)?.lowerBound else {
            signpost.end("keystroke")
            return false
        }
        let context = FormattingContext(
            text: fullText,
            cursorPosition: cursorStart,
            trigger: .shiftTab,
            ast: currentAST
        )
        guard let mutation = formattingEngine.evaluate(context) else {
            signpost.end("keystroke")
            return false
        }
        applyMutation(mutation, to: textView)
        return true
    }

    // MARK: - Formatting Shortcuts per FEAT-009

    /// Toggles bold markdown markers around the selection.
    func handleBold(in textView: NSTextView) {
        if let mutation = inlineMarkerMutation(marker: "**", fullText: textView.string, selectedRange: textView.selectedRange()) {
            applyMutation(mutation, to: textView)
        }
    }

    /// Toggles italic markdown markers around the selection.
    func handleItalic(in textView: NSTextView) {
        if let mutation = inlineMarkerMutation(marker: "*", fullText: textView.string, selectedRange: textView.selectedRange()) {
            applyMutation(mutation, to: textView)
        }
    }

    /// Toggles inline code markers around the selection.
    func handleCode(in textView: NSTextView) {
        if let mutation = inlineMarkerMutation(marker: "`", fullText: textView.string, selectedRange: textView.selectedRange()) {
            applyMutation(mutation, to: textView)
        }
    }

    /// Inserts a markdown link around the selection.
    func handleLinkInsert(in textView: NSTextView) {
        if let mutation = linkInsertMutation(fullText: textView.string, selectedRange: textView.selectedRange()) {
            applyMutation(mutation, to: textView)
        }
    }

    // MARK: - Interactive Elements (FEAT-049)

    /// Handler for link clicks. When set, receives all link clicks (including relative links).
    /// When nil, links open in the system browser by default.
    var onLinkTap: ((URL) -> Void)?

    /// Toggles a task list checkbox at the given range per FEAT-049.
    /// Replaces `[ ]` with `[x]` or `[x]`/`[X]` with `[ ]` as a single undo step per AC-2.
    func toggleCheckbox(at checkboxRange: NSRange, in textView: NSTextView) {
        let fullText = textView.string
        guard let swiftRange = Range(checkboxRange, in: fullText) else { return }
        let current = String(fullText[swiftRange])

        let replacement: String
        if current == "[ ]" {
            replacement = "[x]"
        } else if current == "[x]" || current == "[X]" {
            replacement = "[ ]"
        } else {
            return
        }

        let cursorAfter = swiftRange.upperBound
        let mutation = TextMutation(
            range: swiftRange,
            replacement: replacement,
            cursorAfter: cursorAfter,
            hapticStyle: .listContinuation
        )
        applyMutation(mutation, to: textView)
    }

    /// Opens a link URL per FEAT-049 AC-3.
    /// Delegates to onLinkTap callback if set, otherwise opens in system browser.
    func handleLinkTap(url: URL) {
        if let onLinkTap {
            onLinkTap(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    public func textDidChange(_ notification: Notification) {
        signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }
        guard let textView = notification.object as? EMTextView else { return }
        let newText = textView.string
        text.wrappedValue = newText
        onTextChange?(newText)

        // Notify ghost text coordinator of text change per FEAT-056.
        // This both dismisses active ghost text (AC-3) and resets the pause timer (AC-1).
        ghostTextCoordinator?.textDidChange()

        // Notify smart completion coordinator of text change per FEAT-025.
        // Triggers structure-aware completion on Enter after markdown patterns.
        smartCompletionCoordinator?.textDidChange()

        // Schedule debounced re-parse and render per [A-017]
        scheduleRender(for: textView)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let range = textView.selectedRange()
        editorState.updateSelectedRange(range)

        if range.length > 0 {
            let text = textView.string
            if let swiftRange = Range(range, in: text) {
                let selectedText = String(text[swiftRange])
                let count = wordCount(in: selectedText)
                editorState.updateSelectionWordCount(count)
            }
        } else {
            editorState.updateSelectionWordCount(nil)
        }

        // Update selection rect for floating action bar positioning per FEAT-054.
        updateSelectionRect(for: textView)
    }

    /// Computes the rect of the first line of the selection in the text view's
    /// coordinate space and updates EditorState for floating bar positioning.
    private func updateSelectionRect(for textView: NSTextView) {
        let range = textView.selectedRange()
        guard range.length > 0 else {
            editorState.updateSelectionRect(nil)
            return
        }
        // NSTextView provides a convenient firstRect(forCharacterRange:actualRange:)
        // that returns the rect in screen coordinates. Convert to view coords.
        var actualRange = NSRange()
        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: &actualRange)
        guard !screenRect.isNull, !screenRect.isInfinite,
              let window = textView.window else {
            editorState.updateSelectionRect(nil)
            return
        }
        // Convert screen rect → window → view → superview
        let windowRect = window.convertFromScreen(screenRect)
        let viewRect = textView.convert(windowRect, from: nil)
        let converted = textView.convert(viewRect, to: textView.superview)
        editorState.updateSelectionRect(converted)
    }

    // MARK: - Scroll tracking

    /// Registers for scroll notifications from the enclosing NSScrollView.
    func observeScrollView(_ scrollView: NSScrollView) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        let offset = scrollView.contentView.bounds.origin.y
        editorState.updateScrollOffset(offset)
    }

    // MARK: - Programmatic text updates

    @discardableResult
    func updateTextView(_ textView: EMTextView, with newText: String) -> Bool {
        guard textView.string != newText else { return false }
        isUpdatingFromBinding = true
        textView.string = newText
        isUpdatingFromBinding = false
        return true
    }

    // MARK: - View Mode Toggle per FEAT-050 and FEAT-014

    /// Performs an animated view mode toggle with cursor mapping per [A-021] and FEAT-014.
    /// Called from TextViewBridge when `isSourceView` changes.
    func handleViewModeToggle(for textView: EMTextView, toSourceView: Bool) {
        toggleSignpost.begin("toggle")

        guard let config = renderConfig else {
            toggleSignpost.end("toggle")
            return
        }

        let sourceText = textView.string

        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

        let currentSelection = textView.selectedRange()
        let mappedSelection: NSRange
        if toSourceView {
            mappedSelection = cursorMapper.mapRichToSource(
                selectedRange: currentSelection,
                text: sourceText,
                ast: parseResult.ast
            )
        } else {
            mappedSelection = cursorMapper.mapSourceToRich(
                selectedRange: currentSelection,
                text: sourceText,
                ast: parseResult.ast
            )
        }

        // Extract syntax markers for The Render animation per FEAT-014
        let markers = RenderElementExtractor.extract(
            from: parseResult.ast,
            sourceText: sourceText
        )

        let direction: TransitionDirection = toSourceView ? .richToSource : .sourceToRich

        renderAnimator.performTransition(
            textView: textView,
            markers: markers,
            applyRendering: { [weak self] in
                guard let self else { return }
                applyRendering(
                    to: textView,
                    ast: parseResult.ast,
                    sourceText: sourceText,
                    config: config,
                    restoringSelection: mappedSelection
                )
            },
            direction: direction
        ) { [weak self] in
            self?.toggleSignpost.end("toggle")
            self?.doctorCoordinator.scheduleEvaluation(
                text: sourceText, ast: parseResult.ast
            )
        }
    }

    // MARK: - Rendering per FEAT-003

    /// Requests an immediate parse and render.
    /// On first render in rich mode, plays file-open animation per FEAT-014 AC-11.
    func requestRender(for textView: EMTextView) {
        guard let config = renderConfig else { return }

        let sourceText = textView.string
        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

        // File-open animation per FEAT-014 AC-11
        if isFirstRender && !config.isSourceView && !sourceText.isEmpty {
            isFirstRender = false

            let sourceConfig = RenderConfiguration(
                typeScale: config.typeScale,
                colors: config.colors,
                isSourceView: true,
                colorVariant: config.colorVariant,
                layoutMetrics: config.layoutMetrics,
                documentURL: config.documentURL
            )
            applyRendering(
                to: textView, ast: parseResult.ast,
                sourceText: sourceText, config: sourceConfig
            )
            textView.layoutManager?.ensureLayout(forCharacterRange: NSRange(
                location: 0, length: (sourceText as NSString).length
            ))

            let markers = RenderElementExtractor.extract(
                from: parseResult.ast, sourceText: sourceText
            )
            renderAnimator.performTransition(
                textView: textView,
                markers: markers,
                applyRendering: { [weak self] in
                    guard let self else { return }
                    applyRendering(
                        to: textView, ast: parseResult.ast,
                        sourceText: sourceText, config: config
                    )
                },
                direction: .sourceToRich
            ) { [weak self] in
                self?.doctorCoordinator.evaluateImmediately(
                    text: sourceText, ast: parseResult.ast
                )
            }
            return
        }

        applyRendering(to: textView, ast: parseResult.ast, sourceText: sourceText, config: config)

        if isFirstRender {
            isFirstRender = false
            doctorCoordinator.evaluateImmediately(text: sourceText, ast: parseResult.ast)
        } else {
            doctorCoordinator.scheduleEvaluation(text: sourceText, ast: parseResult.ast)
        }
    }

    /// Schedules a debounced parse and render after text changes per [A-017].
    private func scheduleRender(for textView: EMTextView) {
        parseDebounceTask?.cancel()

        parseDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.parseDebounceInterval ?? 300_000_000)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            self.requestRender(for: textView)
        }
    }

    /// Applies rendered attributes to the text view's text storage.
    private func applyRendering(
        to textView: EMTextView,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration
    ) {
        applyRendering(
            to: textView,
            ast: ast,
            sourceText: sourceText,
            config: config,
            restoringSelection: textView.selectedRange()
        )
    }

    /// Applies rendered attributes to the text view's text storage,
    /// restoring the given selection.
    private func applyRendering(
        to textView: EMTextView,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration,
        restoringSelection: NSRange
    ) {
        guard let textStorage = textView.textStorage else { return }
        guard textStorage.length == sourceText.utf16.count else {
            logger.warning("Text storage length mismatch — skipping render")
            return
        }

        textStorage.beginEditing()
        renderer.render(
            into: textStorage,
            ast: ast,
            sourceText: sourceText,
            config: config
        )
        textStorage.endEditing()

        textView.setSelectedRange(restoringSelection)

        // Reapply find highlights if find bar is active per FEAT-017
        let findState = editorState.findReplaceState
        if findState.isVisible, !findState.matches.isEmpty {
            applyFindHighlights(findState.matches, currentIndex: findState.currentMatchIndex, in: textView)
        }
    }

    // MARK: - Word counting

    /// Word count for selection stats using NLTokenizer for CJK-aware segmentation per [A-055].
    private func wordCount(in text: String) -> Int {
        DocumentStatsCalculator.countWords(in: text)
    }
}

// MARK: - ImproveWritingTextViewDelegate (macOS)

extension TextViewCoordinator: ImproveWritingTextViewDelegate {

    public func currentText() -> String {
        managedTextView?.string ?? text.wrappedValue
    }

    public func currentSelectedRange() -> NSRange {
        managedTextView?.selectedRange() ?? editorState.selectedRange
    }

    public func textStorage() -> NSMutableAttributedString? {
        managedTextView?.textStorage
    }

    public func baseFont() -> PlatformFont {
        renderConfig?.typeScale.body ?? PlatformFont.systemFont(ofSize: 14)
    }

    public func replaceText(in range: NSRange, with replacement: String) {
        guard let textView = managedTextView else { return }
        let fullText = textView.string
        guard let swiftRange = Range(range, in: fullText) else { return }
        var mutable = fullText
        mutable.replaceSubrange(swiftRange, with: replacement)
        textView.string = mutable
        text.wrappedValue = mutable
        onTextChange?(mutable)
    }

    public func requestRerender() {
        guard let textView = managedTextView else { return }
        requestRender(for: textView)
    }
}

// MARK: - GhostTextViewDelegate (macOS)

extension TextViewCoordinator: GhostTextViewDelegate {

    public func isCursorInsideCodeBlock() -> Bool {
        guard let ast = currentAST else { return false }
        let text = currentText()
        let cursorLocation = currentSelectedRange().location

        // Convert UTF-16 offset to line:column SourcePosition
        let nsString = text as NSString
        guard cursorLocation <= nsString.length else { return false }
        let prefix = nsString.substring(to: cursorLocation)
        let lines = prefix.components(separatedBy: "\n")
        let line = lines.count
        let column = (lines.last?.utf8.count ?? 0) + 1

        let position = SourcePosition(line: line, column: column)
        guard let node = ast.node(at: position) else { return false }

        if case .codeBlock = node.type { return true }
        return false
    }
}

/// Lightweight get/set binding for coordinator use (macOS).
/// Named to avoid collision with SwiftUI.Binding.
public struct ValueBinding<Value> {
    let get: () -> Value
    let set: (Value) -> Void

    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}

#endif

// MARK: - Shared Formatting Helpers per FEAT-009

/// Computes the mutation for toggling an inline markdown marker around a selection.
///
/// With selection: if already wrapped with the marker, unwraps. Otherwise wraps.
/// Without selection: inserts paired markers with cursor positioned between them.
func inlineMarkerMutation(
    marker: String,
    fullText: String,
    selectedRange: NSRange
) -> TextMutation? {
    guard let swiftRange = Range(selectedRange, in: fullText) else { return nil }
    let markerCount = marker.count

    if selectedRange.length > 0 {
        let selectedText = String(fullText[swiftRange])

        // Already wrapped → unwrap
        if selectedText.count >= markerCount * 2
            && selectedText.hasPrefix(marker)
            && selectedText.hasSuffix(marker) {
            let inner = String(selectedText.dropFirst(markerCount).dropLast(markerCount))
            return makeFormattingMutation(
                fullText: fullText, range: swiftRange,
                replacement: inner, cursorOffsetInReplacement: inner.count
            )
        }

        // Not wrapped → wrap
        let wrapped = marker + selectedText + marker
        return makeFormattingMutation(
            fullText: fullText, range: swiftRange,
            replacement: wrapped, cursorOffsetInReplacement: wrapped.count
        )
    } else {
        // No selection: insert paired markers, cursor between them
        let paired = marker + marker
        return makeFormattingMutation(
            fullText: fullText, range: swiftRange,
            replacement: paired, cursorOffsetInReplacement: markerCount
        )
    }
}

/// Computes the mutation for inserting a markdown link.
///
/// With selection: wraps as `[selected text]()` with cursor between the parentheses.
/// Without selection: inserts `[]()` with cursor between the brackets.
func linkInsertMutation(
    fullText: String,
    selectedRange: NSRange
) -> TextMutation? {
    guard let swiftRange = Range(selectedRange, in: fullText) else { return nil }

    if selectedRange.length > 0 {
        let selectedText = String(fullText[swiftRange])
        let linkText = "[" + selectedText + "]()"
        // Cursor between the parentheses (before closing paren)
        return makeFormattingMutation(
            fullText: fullText, range: swiftRange,
            replacement: linkText, cursorOffsetInReplacement: linkText.count - 1
        )
    } else {
        let linkText = "[]()"
        // Cursor between the brackets
        return makeFormattingMutation(
            fullText: fullText, range: swiftRange,
            replacement: linkText, cursorOffsetInReplacement: 1
        )
    }
}

/// Builds a `TextMutation` with the cursor placed at a character offset within the replacement.
private func makeFormattingMutation(
    fullText: String,
    range: Range<String.Index>,
    replacement: String,
    cursorOffsetInReplacement: Int
) -> TextMutation {
    let resultText = String(fullText[..<range.lowerBound])
        + replacement
        + String(fullText[range.upperBound...])
    let prefixCount = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
    let cursorAfter = resultText.index(
        resultText.startIndex,
        offsetBy: prefixCount + cursorOffsetInReplacement
    )
    return TextMutation(
        range: range,
        replacement: replacement,
        cursorAfter: cursorAfter
    )
}
