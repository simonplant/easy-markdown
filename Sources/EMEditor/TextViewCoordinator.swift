/// Bridges EMTextView delegate callbacks to EditorState.
/// Delegates rendering, find/replace, and key commands to focused sub-types per FEAT-075.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMParser

#if canImport(UIKit)

@MainActor
public final class TextViewCoordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {

    var text: ValueBinding<String>
    var editorState: EditorState
    var onTextChange: ((String) -> Void)?

    /// Current rendering configuration. Updated from the bridge.
    var renderConfig: RenderConfiguration? {
        didSet { renderingCoordinator.renderConfig = renderConfig }
    }

    /// Weak reference to the managed text view for ImproveWritingTextViewDelegate.
    weak var managedTextView: EMTextView? {
        didSet { renderingCoordinator.managedTextView = managedTextView }
    }

    /// Prevents feedback loops when programmatically updating text.
    private var isUpdatingFromBinding = false

    /// Ghost text coordinator per FEAT-056.
    weak var ghostTextCoordinator: GhostTextCoordinator?

    /// Smart completion coordinator per FEAT-025.
    weak var smartCompletionCoordinator: SmartCompletionCoordinator?

    /// Handler for link taps per FEAT-049.
    var onLinkTap: ((URL) -> Void)?

    /// Whether AI actions should appear in the edit/context menu per FEAT-058.
    var showAIContextMenuActions: Bool = false

    /// Handler for AI Improve from context menu per FEAT-058.
    var onContextMenuImprove: (() -> Void)?

    /// Handler for AI Summarize from context menu per FEAT-058.
    var onContextMenuSummarize: (() -> Void)?

    // MARK: - Extracted Sub-Coordinators per FEAT-075

    let renderingCoordinator: TextViewRenderingCoordinator
    let findReplaceCoordinator: FindReplaceCoordinator
    let keyCommandHandler: TextViewKeyCommandHandler

    /// Document Doctor coordinator per FEAT-005.
    var doctorCoordinator: DoctorCoordinator { renderingCoordinator.doctorCoordinator }

    init(text: ValueBinding<String>, editorState: EditorState) {
        self.text = text
        self.editorState = editorState

        let doctor = DoctorCoordinator(editorState: editorState)
        let signpost = OSSignpost(subsystem: "com.easymarkdown.emeditor", category: "keystroke")

        self.findReplaceCoordinator = FindReplaceCoordinator()
        self.keyCommandHandler = TextViewKeyCommandHandler(signpost: signpost, editorState: editorState)
        self.renderingCoordinator = TextViewRenderingCoordinator(editorState: editorState, doctorCoordinator: doctor)
        super.init()

        renderingCoordinator.findReplaceCoordinator = findReplaceCoordinator
        keyCommandHandler.onMutationApplied = { [weak self] textView in
            guard let self else { return }
            let newText = textView.text ?? ""
            self.text.wrappedValue = newText
            self.onTextChange?(newText)
            if let emTextView = textView as? EMTextView {
                self.renderingCoordinator.scheduleRender(for: emTextView)
            }
        }
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        keyCommandHandler.signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }

        let newText = textView.text ?? ""
        text.wrappedValue = newText
        onTextChange?(newText)

        ghostTextCoordinator?.textDidChange()
        smartCompletionCoordinator?.textDidChange()

        if let emTextView = textView as? EMTextView {
            renderingCoordinator.scheduleRender(for: emTextView)
        }
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        editorState.selection.updateSelectedRange(range)

        if range.length > 0, let text = textView.text,
           let swiftRange = Range(range, in: text) {
            let selectedText = String(text[swiftRange])
            editorState.selection.updateSelectionWordCount(DocumentStatsCalculator.countWords(in: selectedText))
        } else {
            editorState.selection.updateSelectionWordCount(nil)
        }

        updateSelectionRect(for: textView)
    }

    /// Computes the rect of the first line of the selection for floating bar positioning.
    private func updateSelectionRect(for textView: UITextView) {
        guard textView.selectedRange.length > 0,
              let start = textView.selectedTextRange?.start,
              let end = textView.selectedTextRange?.end,
              let selRange = textView.textRange(from: start, to: end) else {
            editorState.selection.updateSelectionRect(nil)
            return
        }
        let firstRect = textView.firstRect(for: selRange)
        guard !firstRect.isNull, !firstRect.isInfinite else {
            editorState.selection.updateSelectionRect(nil)
            return
        }
        let converted = textView.convert(firstRect, to: textView.superview)
        editorState.selection.updateSelectionRect(converted)
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        keyCommandHandler.signpost.begin("keystroke")

        // Ghost text Tab accept per FEAT-056 AC-2.
        if text == "\t",
           let coordinator = ghostTextCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            keyCommandHandler.signpost.end("keystroke")
            return false
        }

        // Smart completion Tab accept per FEAT-025 AC-2.
        if text == "\t",
           let coordinator = smartCompletionCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            keyCommandHandler.signpost.end("keystroke")
            return false
        }

        smartCompletionCoordinator?.willChangeText(replacementText: text)

        // CJK IME: composing text passes through per AC-3.
        if textView.markedTextRange != nil {
            return true
        }

        // Auto-format keystroke interception per [A-051], FEAT-004, and FEAT-052.
        if keyCommandHandler.evaluateFormattingTrigger(
            replacementText: text,
            rangeLength: range.length,
            range: range,
            in: textView,
            ast: renderingCoordinator.currentAST
        ) {
            return false
        }

        return true
    }

    // MARK: - Context Menu per FEAT-058

    public func textView(
        _ textView: UITextView,
        editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        var actions = suggestedActions

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

    @discardableResult
    func updateTextView(_ textView: EMTextView, with newText: String) -> Bool {
        guard textView.text != newText else { return false }
        isUpdatingFromBinding = true
        textView.text = newText
        isUpdatingFromBinding = false
        return true
    }

    /// Opens a link URL per FEAT-049 AC-3.
    func handleLinkTap(url: URL) {
        if let onLinkTap {
            onLinkTap(url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Delegating Wrappers per FEAT-075

    func handleShiftTab(in textView: UITextView) -> Bool {
        keyCommandHandler.handleShiftTab(in: textView, ast: renderingCoordinator.currentAST)
    }

    func handleReplaceText(_ newText: String, in textView: UITextView) {
        renderingCoordinator.handleReplaceText(newText, in: textView, text: text, onTextChange: onTextChange)
    }
}

// MARK: - macOS Coordinator

#elseif canImport(AppKit)

@MainActor
public final class TextViewCoordinator: NSObject, NSTextViewDelegate {

    var text: ValueBinding<String>
    var editorState: EditorState
    var onTextChange: ((String) -> Void)?

    /// Current rendering configuration. Updated from the bridge.
    var renderConfig: RenderConfiguration? {
        didSet { renderingCoordinator.renderConfig = renderConfig }
    }

    /// Weak reference to the managed text view for ImproveWritingTextViewDelegate.
    weak var managedTextView: EMTextView? {
        didSet { renderingCoordinator.managedTextView = managedTextView }
    }

    /// Prevents feedback loops when programmatically updating text.
    private var isUpdatingFromBinding = false

    /// Ghost text coordinator per FEAT-056.
    weak var ghostTextCoordinator: GhostTextCoordinator?

    /// Smart completion coordinator per FEAT-025.
    weak var smartCompletionCoordinator: SmartCompletionCoordinator?

    /// Handler for link clicks per FEAT-049.
    var onLinkTap: ((URL) -> Void)?

    // MARK: - Extracted Sub-Coordinators per FEAT-075

    let renderingCoordinator: TextViewRenderingCoordinator
    let findReplaceCoordinator: FindReplaceCoordinator
    let keyCommandHandler: TextViewKeyCommandHandler

    /// Document Doctor coordinator per FEAT-005.
    var doctorCoordinator: DoctorCoordinator { renderingCoordinator.doctorCoordinator }

    init(text: ValueBinding<String>, editorState: EditorState) {
        self.text = text
        self.editorState = editorState

        let doctor = DoctorCoordinator(editorState: editorState)
        let signpost = OSSignpost(subsystem: "com.easymarkdown.emeditor", category: "keystroke")

        self.findReplaceCoordinator = FindReplaceCoordinator()
        self.keyCommandHandler = TextViewKeyCommandHandler(signpost: signpost, editorState: editorState)
        self.renderingCoordinator = TextViewRenderingCoordinator(editorState: editorState, doctorCoordinator: doctor)
        super.init()

        renderingCoordinator.findReplaceCoordinator = findReplaceCoordinator
        keyCommandHandler.onMutationApplied = { [weak self] textView in
            guard let self else { return }
            let newText = textView.string
            self.text.wrappedValue = newText
            self.onTextChange?(newText)
            if let emTextView = textView as? EMTextView {
                self.renderingCoordinator.scheduleRender(for: emTextView)
            }
        }
    }

    // MARK: - NSTextViewDelegate

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        keyCommandHandler.signpost.begin("keystroke")

        // Ghost text Tab accept per FEAT-056 AC-2.
        if replacementString == "\t",
           let coordinator = ghostTextCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            keyCommandHandler.signpost.end("keystroke")
            return false
        }

        // Smart completion Tab accept per FEAT-025 AC-2.
        if replacementString == "\t",
           let coordinator = smartCompletionCoordinator,
           coordinator.phase == .ready || coordinator.phase == .streaming {
            coordinator.accept()
            keyCommandHandler.signpost.end("keystroke")
            return false
        }

        if let replacement = replacementString {
            smartCompletionCoordinator?.willChangeText(replacementText: replacement)
        }

        // CJK IME: composing text passes through per AC-3.
        if textView.hasMarkedText() {
            return true
        }

        // Auto-format keystroke interception per [A-051], FEAT-004, and FEAT-052.
        if let replacement = replacementString {
            if keyCommandHandler.evaluateFormattingTrigger(
                replacementText: replacement,
                rangeLength: affectedCharRange.length,
                range: affectedCharRange,
                in: textView,
                ast: renderingCoordinator.currentAST
            ) {
                return false
            }
        }

        return true
    }

    public func textDidChange(_ notification: Notification) {
        keyCommandHandler.signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }
        guard let textView = notification.object as? EMTextView else { return }
        let newText = textView.string
        text.wrappedValue = newText
        onTextChange?(newText)

        ghostTextCoordinator?.textDidChange()
        smartCompletionCoordinator?.textDidChange()

        renderingCoordinator.scheduleRender(for: textView)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let range = textView.selectedRange()
        editorState.selection.updateSelectedRange(range)

        if range.length > 0 {
            let text = textView.string
            if let swiftRange = Range(range, in: text) {
                let selectedText = String(text[swiftRange])
                editorState.selection.updateSelectionWordCount(DocumentStatsCalculator.countWords(in: selectedText))
            }
        } else {
            editorState.selection.updateSelectionWordCount(nil)
        }

        updateSelectionRect(for: textView)
    }

    /// Computes the rect of the first line of the selection for floating bar positioning.
    private func updateSelectionRect(for textView: NSTextView) {
        let range = textView.selectedRange()
        guard range.length > 0 else {
            editorState.selection.updateSelectionRect(nil)
            return
        }
        var actualRange = NSRange()
        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: &actualRange)
        guard !screenRect.isNull, !screenRect.isInfinite,
              let window = textView.window else {
            editorState.selection.updateSelectionRect(nil)
            return
        }
        let windowRect = window.convertFromScreen(screenRect)
        let viewRect = textView.convert(windowRect, from: nil)
        let converted = textView.convert(viewRect, to: textView.superview)
        editorState.selection.updateSelectionRect(converted)
    }

    // MARK: - Scroll tracking

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

    /// Opens a link URL per FEAT-049 AC-3.
    func handleLinkTap(url: URL) {
        if let onLinkTap {
            onLinkTap(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Delegating Wrappers per FEAT-075

    func handleShiftTab(in textView: NSTextView) -> Bool {
        keyCommandHandler.handleShiftTab(in: textView, ast: renderingCoordinator.currentAST)
    }

    func handleReplaceText(_ newText: String, in textView: NSTextView) {
        renderingCoordinator.handleReplaceText(newText, in: textView, text: text, onTextChange: onTextChange)
    }
}

#endif

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
