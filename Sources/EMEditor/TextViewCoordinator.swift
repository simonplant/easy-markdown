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

    /// Formatting engine for list auto-formatting per FEAT-004 and [A-051].
    private let formattingEngine = FormattingEngine.listFormattingEngine()

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

    /// Whether this is the first render (triggers immediate doctor evaluation).
    private var isFirstRender = true

    /// Signpost for toggle latency measurement per FEAT-050.
    private let toggleSignpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "toggle"
    )

    init(text: ValueBinding<String>, editorState: EditorState) {
        self.text = text
        self.editorState = editorState
        super.init()
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }

        let newText = textView.text ?? ""
        text.wrappedValue = newText
        onTextChange?(newText)

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
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        // Start keystroke performance signpost per [A-037].
        signpost.begin("keystroke")

        // CJK IME: if the text view has marked text (composing),
        // let the input system handle it without interference per AC-3.
        if textView.markedTextRange != nil {
            return true
        }

        // Auto-format keystroke interception per [A-051] and FEAT-004.
        if let trigger = formattingTrigger(for: text) {
            let fullText = textView.text ?? ""
            if let cursorStart = Range(range, in: fullText)?.lowerBound {
                let context = FormattingContext(
                    text: fullText,
                    cursorPosition: cursorStart,
                    trigger: trigger,
                    ast: currentAST
                )
                if let mutation = formattingEngine.evaluate(context) {
                    applyMutation(mutation, to: textView)
                    return false
                }
            }
        }

        return true
    }

    /// Maps replacement text to a formatting trigger.
    private func formattingTrigger(for replacementText: String) -> FormattingTrigger? {
        switch replacementText {
        case "\n": return .enter
        case "\t": return .tab
        default: return nil
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

    // MARK: - View Mode Toggle per FEAT-050

    /// Performs a view mode toggle with cursor mapping per [A-021].
    /// Called from TextViewBridge when `isSourceView` changes.
    func handleViewModeToggle(for textView: EMTextView, toSourceView: Bool) {
        toggleSignpost.begin("toggle")
        defer { toggleSignpost.end("toggle") }

        guard let config = renderConfig else { return }

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

        // Apply new rendering with mapped cursor
        applyRendering(
            to: textView,
            ast: parseResult.ast,
            sourceText: sourceText,
            config: config,
            restoringSelection: mappedSelection
        )

        // Run Document Doctor after toggle
        doctorCoordinator.scheduleEvaluation(text: sourceText, ast: parseResult.ast)
    }

    // MARK: - Rendering per FEAT-003

    /// Requests an immediate parse and render. Called on initial load and view mode toggle.
    func requestRender(for textView: EMTextView) {
        guard let config = renderConfig else { return }

        let sourceText = textView.text ?? ""
        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

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
    }

    // MARK: - Word counting

    /// Word count for selection stats using NLTokenizer for CJK-aware segmentation per [A-055].
    private func wordCount(in text: String) -> Int {
        DocumentStatsCalculator.countWords(in: text)
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

    /// Formatting engine for list auto-formatting per FEAT-004 and [A-051].
    private let formattingEngine = FormattingEngine.listFormattingEngine()

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

    /// Whether this is the first render (triggers immediate doctor evaluation).
    private var isFirstRender = true

    /// Signpost for toggle latency measurement per FEAT-050.
    private let toggleSignpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "toggle"
    )

    init(text: ValueBinding<String>, editorState: EditorState) {
        self.text = text
        self.editorState = editorState
        super.init()
    }

    // MARK: - NSTextViewDelegate

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // Start keystroke performance signpost per [A-037].
        signpost.begin("keystroke")

        // CJK IME: if the text view has marked text (composing),
        // let the input system handle it without interference per AC-3.
        if textView.hasMarkedText() {
            return true
        }

        // Auto-format keystroke interception per [A-051] and FEAT-004.
        if let replacement = replacementString,
           let trigger = formattingTrigger(for: replacement) {
            let fullText = textView.string
            if let cursorStart = Range(affectedCharRange, in: fullText)?.lowerBound {
                let context = FormattingContext(
                    text: fullText,
                    cursorPosition: cursorStart,
                    trigger: trigger,
                    ast: currentAST
                )
                if let mutation = formattingEngine.evaluate(context) {
                    applyMutation(mutation, to: textView)
                    return false
                }
            }
        }

        return true
    }

    /// Maps replacement text to a formatting trigger.
    private func formattingTrigger(for replacementText: String) -> FormattingTrigger? {
        switch replacementText {
        case "\n": return .enter
        case "\t": return .tab
        default: return nil
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

    public func textDidChange(_ notification: Notification) {
        signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }
        guard let textView = notification.object as? EMTextView else { return }
        let newText = textView.string
        text.wrappedValue = newText
        onTextChange?(newText)

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

    // MARK: - View Mode Toggle per FEAT-050

    /// Performs a view mode toggle with cursor mapping per [A-021].
    /// Called from TextViewBridge when `isSourceView` changes.
    func handleViewModeToggle(for textView: EMTextView, toSourceView: Bool) {
        toggleSignpost.begin("toggle")
        defer { toggleSignpost.end("toggle") }

        guard let config = renderConfig else { return }

        let sourceText = textView.string

        // Re-parse to get fresh AST for cursor mapping
        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

        // Map cursor position between views per [A-021]
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

        // Apply new rendering with mapped cursor
        applyRendering(
            to: textView,
            ast: parseResult.ast,
            sourceText: sourceText,
            config: config,
            restoringSelection: mappedSelection
        )

        // Run Document Doctor after toggle
        doctorCoordinator.scheduleEvaluation(text: sourceText, ast: parseResult.ast)
    }

    // MARK: - Rendering per FEAT-003

    /// Requests an immediate parse and render.
    func requestRender(for textView: EMTextView) {
        guard let config = renderConfig else { return }

        let sourceText = textView.string
        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

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
    }

    // MARK: - Word counting

    /// Word count for selection stats using NLTokenizer for CJK-aware segmentation per [A-055].
    private func wordCount(in text: String) -> Int {
        DocumentStatsCalculator.countWords(in: text)
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
