/// Owns keyboard shortcut dispatch and text mutation application per FEAT-075.
/// Extracted from TextViewCoordinator to isolate formatting and shortcut concerns.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMFormatter
import EMParser

// MARK: - iOS Key Command Handler

#if canImport(UIKit)

@MainActor
final class TextViewKeyCommandHandler {

    /// Signpost log for measuring keystroke-to-render per [D-PERF-2].
    let signpost: OSSignpost

    /// Editor state for undo manager access.
    private let editorState: EditorState

    /// Formatting engine for auto-formatting per FEAT-004, FEAT-052, and [A-051].
    private var formattingEngine = FormattingEngine.defaultFormattingEngine()

    /// Cached formatting setting values for change detection.
    private var cachedHeadingSpacing: Bool = true
    private var cachedBlankLineSeparation: Bool = true
    private var cachedTrailingWhitespaceTrim: Bool = true

    /// Called after a mutation is applied to sync binding and trigger render.
    var onMutationApplied: ((UITextView) -> Void)?

    init(signpost: OSSignpost, editorState: EditorState) {
        self.signpost = signpost
        self.editorState = editorState
    }

    // MARK: - Formatting Settings

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

    // MARK: - Formatting Trigger Evaluation

    /// Evaluates whether a formatting trigger should consume the input.
    /// Returns true if a formatting rule was applied (caller should return false from shouldChangeTextIn).
    func evaluateFormattingTrigger(
        replacementText: String,
        rangeLength: Int,
        range: NSRange,
        in textView: UITextView,
        ast: MarkdownAST?
    ) -> Bool {
        guard let trigger = formattingTrigger(for: replacementText, rangeLength: rangeLength) else {
            return false
        }
        let fullText = textView.text ?? ""
        guard let swiftRange = Range(range, in: fullText) else { return false }
        let context = FormattingContext(
            text: fullText,
            cursorPosition: swiftRange.lowerBound,
            trigger: trigger,
            ast: ast,
            replacementRange: swiftRange
        )
        guard let mutation = formattingEngine.evaluate(context) else { return false }
        applyMutation(mutation, to: textView)
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

    // MARK: - Mutation Application

    /// Applies a TextMutation to the text view as a discrete undo group per [A-022].
    func applyMutation(_ mutation: TextMutation, to textView: UITextView) {
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
        onMutationApplied?(textView)

        // Haptic feedback per [A-062]
        if let haptic = mutation.hapticStyle {
            HapticFeedback.trigger(haptic)
        }

        signpost.end("keystroke")
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

    /// Handles Shift-Tab for list outdent per FEAT-004.
    /// Returns true if the event was consumed by a formatting rule.
    func handleShiftTab(in textView: UITextView, ast: MarkdownAST?) -> Bool {
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
            ast: ast
        )
        guard let mutation = formattingEngine.evaluate(context) else {
            signpost.end("keystroke")
            return false
        }
        applyMutation(mutation, to: textView)
        return true
    }

    // MARK: - Interactive Elements (FEAT-049)

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
}

// MARK: - macOS Key Command Handler

#elseif canImport(AppKit)

@MainActor
final class TextViewKeyCommandHandler {

    /// Signpost log for measuring keystroke-to-render per [D-PERF-2].
    let signpost: OSSignpost

    /// Editor state reference.
    private let editorState: EditorState

    /// Formatting engine for auto-formatting per FEAT-004, FEAT-052, and [A-051].
    private var formattingEngine = FormattingEngine.defaultFormattingEngine()

    /// Cached formatting setting values for change detection.
    private var cachedHeadingSpacing: Bool = true
    private var cachedBlankLineSeparation: Bool = true
    private var cachedTrailingWhitespaceTrim: Bool = true

    /// Called after a mutation is applied to sync binding and trigger render.
    var onMutationApplied: ((NSTextView) -> Void)?

    init(signpost: OSSignpost, editorState: EditorState) {
        self.signpost = signpost
        self.editorState = editorState
    }

    // MARK: - Formatting Settings

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

    // MARK: - Formatting Trigger Evaluation

    /// Evaluates whether a formatting trigger should consume the input.
    /// Returns true if a formatting rule was applied (caller should return false from shouldChangeTextIn).
    func evaluateFormattingTrigger(
        replacementText: String,
        rangeLength: Int,
        range: NSRange,
        in textView: NSTextView,
        ast: MarkdownAST?
    ) -> Bool {
        guard let trigger = formattingTrigger(for: replacementText, rangeLength: rangeLength) else {
            return false
        }
        let fullText = textView.string
        guard let swiftRange = Range(range, in: fullText) else { return false }
        let context = FormattingContext(
            text: fullText,
            cursorPosition: swiftRange.lowerBound,
            trigger: trigger,
            ast: ast,
            replacementRange: swiftRange
        )
        guard let mutation = formattingEngine.evaluate(context) else { return false }
        applyMutation(mutation, to: textView)
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

    // MARK: - Mutation Application

    /// Applies a TextMutation to the text view as a discrete undo group per [A-022].
    func applyMutation(_ mutation: TextMutation, to textView: NSTextView) {
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
        onMutationApplied?(textView)

        signpost.end("keystroke")
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

    /// Handles Shift-Tab for list outdent per FEAT-004.
    /// Returns true if the event was consumed by a formatting rule.
    func handleShiftTab(in textView: NSTextView, ast: MarkdownAST?) -> Bool {
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
            ast: ast
        )
        guard let mutation = formattingEngine.evaluate(context) else {
            signpost.end("keystroke")
            return false
        }
        applyMutation(mutation, to: textView)
        return true
    }

    // MARK: - Interactive Elements (FEAT-049)

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
