/// SwiftUI bridge for EMTextView per [A-004].
/// Wraps the TextKit 2 text view as a UIViewRepresentable (iOS) / NSViewRepresentable (macOS)
/// for embedding in the SwiftUI view hierarchy.
/// Integrates MarkdownRenderer for rich text rendering per FEAT-003 and [A-018].

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
///     renderConfig: config,
///     isEditable: true,
///     onTextChange: { newText in ... }
/// )
/// ```
public struct TextViewBridge: UIViewRepresentable {
    @SwiftUI.Binding public var text: String
    public var editorState: EditorState
    public var renderConfig: RenderConfiguration?
    public var isEditable: Bool
    public var isSpellCheckEnabled: Bool
    public var onTextChange: ((String) -> Void)?

    public init(
        text: SwiftUI.Binding<String>,
        editorState: EditorState,
        renderConfig: RenderConfiguration? = nil,
        isEditable: Bool = true,
        isSpellCheckEnabled: Bool = true,
        onTextChange: ((String) -> Void)? = nil
    ) {
        self._text = text
        self.editorState = editorState
        self.renderConfig = renderConfig
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
        context.coordinator.renderConfig = renderConfig

        // Apply initial theme background per FEAT-007
        if let colors = renderConfig?.colors {
            textView.backgroundColor = colors.background
        }

        // Initial render if config is available
        if renderConfig != nil {
            context.coordinator.requestRender(for: textView)
        }

        return textView
    }

    public func updateUIView(_ textView: EMTextView, context: Context) {
        let coordinator = context.coordinator

        // Track whether we need to re-render
        let textChanged = coordinator.updateTextView(textView, with: text)
        let previousVariant = coordinator.renderConfig?.colorVariant
        let viewModeChanged = coordinator.renderConfig?.isSourceView != renderConfig?.isSourceView
        let colorChanged = previousVariant != nil && previousVariant != renderConfig?.colorVariant
        let configChanged = viewModeChanged || colorChanged

        // Update render configuration
        coordinator.renderConfig = renderConfig

        // Update editable state
        textView.isEditable = isEditable

        // Update spell check per [A-054]
        let spellType: UITextSpellCheckingType = isSpellCheckEnabled ? .yes : .no
        if textView.spellCheckingType != spellType {
            textView.spellCheckingType = spellType
        }

        // Apply theme background color per FEAT-007
        if let colors = renderConfig?.colors {
            textView.applyThemeBackground(colors.background, animated: colorChanged)
        }

        // Re-render if text loaded from binding or view/theme changed
        if (textChanged || configChanged), renderConfig != nil {
            coordinator.requestRender(for: textView)
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
    public var renderConfig: RenderConfiguration?
    public var isEditable: Bool
    public var isSpellCheckEnabled: Bool
    public var onTextChange: ((String) -> Void)?

    public init(
        text: SwiftUI.Binding<String>,
        editorState: EditorState,
        renderConfig: RenderConfiguration? = nil,
        isEditable: Bool = true,
        isSpellCheckEnabled: Bool = true,
        onTextChange: ((String) -> Void)? = nil
    ) {
        self._text = text
        self.editorState = editorState
        self.renderConfig = renderConfig
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
        context.coordinator.renderConfig = renderConfig

        // Apply initial theme background per FEAT-007
        if let colors = renderConfig?.colors {
            textView.backgroundColor = colors.background
        }

        // Observe scroll position changes
        context.coordinator.observeScrollView(scrollView)

        // Initial render if config is available
        if renderConfig != nil {
            context.coordinator.requestRender(for: textView)
        }

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EMTextView else { return }

        let coordinator = context.coordinator
        let textChanged = coordinator.updateTextView(textView, with: text)
        let previousVariant = coordinator.renderConfig?.colorVariant
        let viewModeChanged = coordinator.renderConfig?.isSourceView != renderConfig?.isSourceView
        let colorChanged = previousVariant != nil && previousVariant != renderConfig?.colorVariant
        let configChanged = viewModeChanged || colorChanged

        coordinator.renderConfig = renderConfig
        textView.isEditable = isEditable
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled

        // Apply theme background color per FEAT-007
        if let colors = renderConfig?.colors {
            textView.applyThemeBackground(colors.background, animated: colorChanged)
        }

        if (textChanged || configChanged), renderConfig != nil {
            coordinator.requestRender(for: textView)
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

#endif
