/// Owns the parse/debounce/render pipeline per FEAT-075.
/// Extracted from TextViewCoordinator to isolate rendering concerns.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMDoctor
import EMParser

private let renderLogger = Logger(subsystem: "com.easymarkdown.emeditor", category: "rendering")

// MARK: - iOS Rendering Coordinator

#if canImport(UIKit)

@MainActor
final class TextViewRenderingCoordinator {

    /// Parser for markdown text per [A-003].
    private let parser = MarkdownParser()

    /// Renderer for AST → styled attributes per [A-018].
    private let renderer = MarkdownRenderer()

    /// Cursor mapper for view toggle per FEAT-050 and [A-021].
    private let cursorMapper = CursorMapper()

    /// Most recent AST from a full parse.
    private(set) var currentAST: MarkdownAST?

    /// Debounce task for full re-parse per [A-017].
    private var parseDebounceTask: Task<Void, Never>?

    /// Debounce interval for full re-parse (300ms per [A-017]).
    private let parseDebounceInterval: UInt64 = 300_000_000

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

    /// Current rendering configuration. Updated from the coordinator.
    var renderConfig: RenderConfiguration?

    /// Weak reference to the managed text view for image reload callbacks.
    weak var managedTextView: EMTextView?

    /// Reference to editor state for doctor coordination and find state.
    private let editorState: EditorState

    /// Document Doctor coordinator per FEAT-005.
    let doctorCoordinator: DoctorCoordinator

    /// Find/replace coordinator for reapplying highlights after render.
    weak var findReplaceCoordinator: FindReplaceCoordinator?

    init(editorState: EditorState, doctorCoordinator: DoctorCoordinator) {
        self.editorState = editorState
        self.doctorCoordinator = doctorCoordinator

        renderer.imageLoader.onImageLoaded = { [weak self] _ in
            guard let self, let textView = self.managedTextView else { return }
            self.requestRender(for: textView)
        }
    }

    // MARK: - View Mode Toggle per FEAT-050 and FEAT-014

    /// Performs an animated view mode toggle with cursor mapping per [A-021] and FEAT-014.
    func handleViewModeToggle(for textView: EMTextView, toSourceView: Bool) {
        toggleSignpost.begin("toggle")

        guard let config = renderConfig else {
            toggleSignpost.end("toggle")
            return
        }

        let sourceText = textView.text ?? ""

        let parseResult = parser.parse(sourceText)
        currentAST = parseResult.ast

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
    func scheduleRender(for textView: EMTextView) {
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
            renderLogger.warning("Text storage length mismatch — skipping render")
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
            findReplaceCoordinator?.applyFindHighlights(
                findState.matches, currentIndex: findState.currentMatchIndex, in: textView
            )
        }
    }

    // MARK: - Text Replacement

    /// Replaces the entire document text as a single undo group per FEAT-017 AC-3.
    func handleReplaceText(
        _ newText: String,
        in textView: UITextView,
        text: ValueBinding<String>,
        onTextChange: ((String) -> Void)?
    ) {
        let oldText = textView.text ?? ""
        guard oldText != newText else { return }

        let fullRange = NSRange(location: 0, length: (oldText as NSString).length)
        let undoManager = editorState.undoManager

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: textView) { [weak self] tv in
            self?.handleReplaceText(oldText, in: tv, text: text, onTextChange: onTextChange)
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

    // MARK: - Navigation

    /// Navigates the cursor to the start of a 1-based line number per FEAT-022 AC-2.
    func handleNavigateToLine(_ line: Int, in textView: UITextView) {
        let fullText = textView.text ?? ""
        let offset = utf16OffsetForLine(line, in: fullText)
        let nsRange = NSRange(location: offset, length: 0)
        textView.selectedRange = nsRange
        textView.scrollRangeToVisible(nsRange)
        editorState.selection.updateSelectedRange(nsRange)
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
}

// MARK: - ImproveWritingTextViewDelegate (iOS)

extension TextViewCoordinator: ImproveWritingTextViewDelegate {

    public func currentText() -> String {
        managedTextView?.text ?? text.wrappedValue
    }

    public func currentSelectedRange() -> NSRange {
        managedTextView?.selectedRange ?? editorState.selection.selectedRange
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
        renderingCoordinator.requestRender(for: textView)
    }
}

// MARK: - GhostTextViewDelegate (iOS)

extension TextViewCoordinator: GhostTextViewDelegate {

    public func isCursorInsideCodeBlock() -> Bool {
        guard let ast = renderingCoordinator.currentAST else { return false }
        let text = currentText()
        let cursorLocation = currentSelectedRange().location

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

// MARK: - macOS Rendering Coordinator

#elseif canImport(AppKit)

@MainActor
final class TextViewRenderingCoordinator {

    /// Parser for markdown text per [A-003].
    private let parser = MarkdownParser()

    /// Renderer for AST → styled attributes per [A-018].
    private let renderer = MarkdownRenderer()

    /// Cursor mapper for view toggle per FEAT-050 and [A-021].
    private let cursorMapper = CursorMapper()

    /// Most recent AST from a full parse.
    private(set) var currentAST: MarkdownAST?

    /// Debounce task for full re-parse per [A-017].
    private var parseDebounceTask: Task<Void, Never>?

    /// Debounce interval for full re-parse (300ms per [A-017]).
    private let parseDebounceInterval: UInt64 = 300_000_000

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

    /// Current rendering configuration. Updated from the coordinator.
    var renderConfig: RenderConfiguration?

    /// Weak reference to the managed text view for image reload callbacks.
    weak var managedTextView: EMTextView?

    /// Reference to editor state for doctor coordination and find state.
    private let editorState: EditorState

    /// Document Doctor coordinator per FEAT-005.
    let doctorCoordinator: DoctorCoordinator

    /// Find/replace coordinator for reapplying highlights after render.
    weak var findReplaceCoordinator: FindReplaceCoordinator?

    init(editorState: EditorState, doctorCoordinator: DoctorCoordinator) {
        self.editorState = editorState
        self.doctorCoordinator = doctorCoordinator

        renderer.imageLoader.onImageLoaded = { [weak self] _ in
            guard let self, let textView = self.managedTextView else { return }
            self.requestRender(for: textView)
        }
    }

    // MARK: - View Mode Toggle per FEAT-050 and FEAT-014

    /// Performs an animated view mode toggle with cursor mapping per [A-021] and FEAT-014.
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
    func scheduleRender(for textView: EMTextView) {
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
            renderLogger.warning("Text storage length mismatch — skipping render")
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
            findReplaceCoordinator?.applyFindHighlights(
                findState.matches, currentIndex: findState.currentMatchIndex, in: textView
            )
        }
    }

    // MARK: - Text Replacement

    /// Replaces the entire document text as a single undo group per FEAT-017 AC-3.
    func handleReplaceText(
        _ newText: String,
        in textView: NSTextView,
        text: ValueBinding<String>,
        onTextChange: ((String) -> Void)?
    ) {
        let oldText = textView.string
        guard oldText != newText else { return }

        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: (oldText as NSString).length)

        if let undoManager = textView.undoManager {
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: textView) { [weak self] tv in
                self?.handleReplaceText(oldText, in: tv, text: text, onTextChange: onTextChange)
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

    // MARK: - Navigation

    /// Navigates the cursor to the start of a 1-based line number per FEAT-022 AC-2.
    func handleNavigateToLine(_ line: Int, in textView: NSTextView) {
        let fullText = textView.string
        let offset = utf16OffsetForLine(line, in: fullText)
        let nsRange = NSRange(location: offset, length: 0)
        textView.setSelectedRange(nsRange)
        textView.scrollRangeToVisible(nsRange)
        editorState.selection.updateSelectedRange(nsRange)
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
}

// MARK: - ImproveWritingTextViewDelegate (macOS)

extension TextViewCoordinator: ImproveWritingTextViewDelegate {

    public func currentText() -> String {
        managedTextView?.string ?? text.wrappedValue
    }

    public func currentSelectedRange() -> NSRange {
        managedTextView?.selectedRange() ?? editorState.selection.selectedRange
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
        renderingCoordinator.requestRender(for: textView)
    }
}

// MARK: - GhostTextViewDelegate (macOS)

extension TextViewCoordinator: GhostTextViewDelegate {

    public func isCursorInsideCodeBlock() -> Bool {
        guard let ast = renderingCoordinator.currentAST else { return false }
        let text = currentText()
        let cursorLocation = currentSelectedRange().location

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

#endif
