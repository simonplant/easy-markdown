/// Coordinator that bridges EMTextView delegate callbacks to EditorState.
/// Handles text changes, selection updates, scroll tracking, and
/// keystroke performance instrumentation per [A-037].

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

    /// Prevents feedback loops when programmatically updating text.
    private var isUpdatingFromBinding = false

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

        // Future: auto-format keystroke interception per [A-051]
        // will go here — query AST context, invoke EMFormatter rules.

        return true
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        editorState.updateScrollOffset(scrollView.contentOffset.y)
    }

    // MARK: - Programmatic text updates

    /// Update the text view's content from the binding without triggering delegate callbacks.
    func updateTextView(_ textView: EMTextView, with newText: String) {
        guard textView.text != newText else { return }
        isUpdatingFromBinding = true
        textView.text = newText
        isUpdatingFromBinding = false
    }

    // MARK: - Word counting

    /// Simple word count for selection stats.
    /// Full document word count uses NLTokenizer (in EditorShellView for now).
    private func wordCount(in text: String) -> Int {
        text.split(omittingEmptySubsequences: true) { $0.isWhitespace || $0.isNewline }.count
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
    private var isUpdatingFromBinding = false

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

        // Future: auto-format keystroke interception per [A-051]
        // will go here — query AST context, invoke EMFormatter rules.

        return true
    }

    public func textDidChange(_ notification: Notification) {
        signpost.end("keystroke")

        guard !isUpdatingFromBinding else { return }
        guard let textView = notification.object as? NSTextView else { return }
        let newText = textView.string
        text.wrappedValue = newText
        onTextChange?(newText)
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

    func updateTextView(_ textView: EMTextView, with newText: String) {
        guard textView.string != newText else { return }
        isUpdatingFromBinding = true
        textView.string = newText
        isUpdatingFromBinding = false
    }

    // MARK: - Word counting

    /// Simple word count for selection stats.
    /// Full document word count uses NLTokenizer (in EditorShellView for now).
    private func wordCount(in text: String) -> Int {
        text.split(omittingEmptySubsequences: true) { $0.isWhitespace || $0.isNewline }.count
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
