/// SwiftUI bridge for EMTextView per [A-004].
/// Wraps the TextKit 2 text view as a UIViewRepresentable (iOS) / NSViewRepresentable (macOS)
/// for embedding in the SwiftUI view hierarchy.

import SwiftUI
import EMCore

// MARK: - iOS Bridge

#if canImport(UIKit)

/// SwiftUI wrapper for the TextKit 2 editor on iOS.
///
/// Usage:
/// ```swift
/// TextViewBridge(
///     text: $text,
///     editorState: editorState,
///     isEditable: true,
///     onTextChange: { newText in ... }
/// )
/// ```
public struct TextViewBridge: UIViewRepresentable {
    @SwiftUI.Binding public var text: String
    public var editorState: EditorState
    public var isEditable: Bool
    public var isSpellCheckEnabled: Bool
    public var onTextChange: ((String) -> Void)?

    public init(
        text: SwiftUI.Binding<String>,
        editorState: EditorState,
        isEditable: Bool = true,
        isSpellCheckEnabled: Bool = true,
        onTextChange: ((String) -> Void)? = nil
    ) {
        self._text = text
        self.editorState = editorState
        self.isEditable = isEditable
        self.isSpellCheckEnabled = isSpellCheckEnabled
        self.onTextChange = onTextChange
    }

    public func makeUIView(context: Context) -> EMTextView {
        let textView = EMTextView(editorState: editorState)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.spellCheckingType = isSpellCheckEnabled ? .yes : .no
        textView.text = text

        // Accessibility hint per [A-043]
        textView.accessibilityHint = NSLocalizedString(
            "Edit your markdown document here",
            comment: "Accessibility hint for editor"
        )

        context.coordinator.onTextChange = onTextChange
        return textView
    }

    public func updateUIView(_ textView: EMTextView, context: Context) {
        // Update text from binding (e.g., file load)
        context.coordinator.updateTextView(textView, with: text)

        // Update editable state
        textView.isEditable = isEditable

        // Update spell check per [A-054]
        let spellType: UITextSpellCheckingType = isSpellCheckEnabled ? .yes : .no
        if textView.spellCheckingType != spellType {
            textView.spellCheckingType = spellType
        }
    }

    public func makeCoordinator() -> TextViewCoordinator {
        TextViewCoordinator(
            text: ValueBinding(
                get: { self.text },
                set: { self.text = $0 }
            ),
            editorState: editorState
        )
    }
}

// MARK: - macOS Bridge

#elseif canImport(AppKit)

/// SwiftUI wrapper for the TextKit 2 editor on macOS.
public struct TextViewBridge: NSViewRepresentable {
    @SwiftUI.Binding public var text: String
    public var editorState: EditorState
    public var isEditable: Bool
    public var isSpellCheckEnabled: Bool
    public var onTextChange: ((String) -> Void)?

    public init(
        text: SwiftUI.Binding<String>,
        editorState: EditorState,
        isEditable: Bool = true,
        isSpellCheckEnabled: Bool = true,
        onTextChange: ((String) -> Void)? = nil
    ) {
        self._text = text
        self.editorState = editorState
        self.isEditable = isEditable
        self.isSpellCheckEnabled = isSpellCheckEnabled
        self.onTextChange = onTextChange
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let textView = EMTextView(editorState: editorState)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.string = text

        // Wrap in scroll view for macOS
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView

        // Accessibility
        textView.setAccessibilityLabel(NSLocalizedString(
            "Document editor",
            comment: "Accessibility label for the main text editing area"
        ))

        context.coordinator.onTextChange = onTextChange

        // Observe scroll position changes
        context.coordinator.observeScrollView(scrollView)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EMTextView else { return }

        context.coordinator.updateTextView(textView, with: text)
        textView.isEditable = isEditable
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
    }

    public func makeCoordinator() -> TextViewCoordinator {
        TextViewCoordinator(
            text: ValueBinding(
                get: { self.text },
                set: { self.text = $0 }
            ),
            editorState: editorState
        )
    }
}

#endif
