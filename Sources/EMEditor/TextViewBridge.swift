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
    /// Handler for link taps per FEAT-049. Receives the URL when a link is tapped.
    /// When nil, links open in the system browser by default.
    public var onLinkTap: ((URL) -> Void)?
    /// Optional improve writing coordinator to wire as text view delegate per FEAT-011.
    public var improveCoordinator: ImproveWritingCoordinator?
    /// Optional tone adjustment coordinator per FEAT-023.
    public var toneCoordinator: ToneAdjustmentCoordinator?
    /// Optional ghost text coordinator for AI continue writing per FEAT-056.
    public var ghostTextCoordinator: GhostTextCoordinator?

    // MARK: - Formatting settings per FEAT-053 AC-6

    /// Whether heading spacing auto-format is enabled.
    public var isAutoFormatHeadingSpacing: Bool
    /// Whether blank line separation auto-format is enabled.
    public var isAutoFormatBlankLineSeparation: Bool
    /// Whether trailing whitespace trimming on Enter is enabled.
    public var isAutoFormatTrailingWhitespaceTrim: Bool

    /// Whether prose suggestion doctor rules are enabled per FEAT-022.
    public var isProseSuggestionsEnabled: Bool

    // MARK: - App-level keyboard shortcut handlers per FEAT-009

    /// Called when Cmd+J is pressed (AI assist).
    public var onAIAssist: (() -> Void)?
    /// Called when Cmd+Shift+P is pressed (toggle source view).
    public var onToggleSourceView: (() -> Void)?
    /// Called when Cmd+O is pressed (open file).
    public var onOpenFile: (() -> Void)?
    /// Called when Cmd+N is pressed (new file).
    public var onNewFile: (() -> Void)?
    /// Called when Cmd+W is pressed (close file).
    public var onCloseFile: (() -> Void)?
    /// Called when Cmd+F is pressed (find and replace) per FEAT-017.
    public var onFindReplace: (() -> Void)?

    /// Called when an image is dropped or pasted per FEAT-020 (F-015).
    /// Receives raw image data and a suggested filename.
    public var onImageReceived: ((_ imageData: Data, _ suggestedName: String) -> Void)?

    // MARK: - Context menu AI actions per FEAT-058

    /// Whether AI actions should appear in the right-click context menu.
    public var showAIContextMenuActions: Bool
    /// Called when Improve Writing is selected from the context menu.
    public var onContextMenuImprove: (() -> Void)?
    /// Called when Summarize is selected from the context menu.
    public var onContextMenuSummarize: (() -> Void)?

    public init(
        text: SwiftUI.Binding<String>,
        editorState: EditorState,
        renderConfig: RenderConfiguration? = nil,
        isEditable: Bool = true,
        isSpellCheckEnabled: Bool = true,
        onTextChange: ((String) -> Void)? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
        improveCoordinator: ImproveWritingCoordinator? = nil,
        toneCoordinator: ToneAdjustmentCoordinator? = nil,
        ghostTextCoordinator: GhostTextCoordinator? = nil,
        isAutoFormatHeadingSpacing: Bool = true,
        isAutoFormatBlankLineSeparation: Bool = true,
        isAutoFormatTrailingWhitespaceTrim: Bool = true,
        isProseSuggestionsEnabled: Bool = false,
        onAIAssist: (() -> Void)? = nil,
        onToggleSourceView: (() -> Void)? = nil,
        onOpenFile: (() -> Void)? = nil,
        onNewFile: (() -> Void)? = nil,
        onCloseFile: (() -> Void)? = nil,
        onFindReplace: (() -> Void)? = nil,
        onImageReceived: ((_ imageData: Data, _ suggestedName: String) -> Void)? = nil,
        showAIContextMenuActions: Bool = false,
        onContextMenuImprove: (() -> Void)? = nil,
        onContextMenuSummarize: (() -> Void)? = nil
    ) {
        self._text = text
        self.editorState = editorState
        self.renderConfig = renderConfig
        self.isEditable = isEditable
        self.isSpellCheckEnabled = isSpellCheckEnabled
        self.onTextChange = onTextChange
        self.onLinkTap = onLinkTap
        self.improveCoordinator = improveCoordinator
        self.toneCoordinator = toneCoordinator
        self.ghostTextCoordinator = ghostTextCoordinator
        self.isAutoFormatHeadingSpacing = isAutoFormatHeadingSpacing
        self.isAutoFormatBlankLineSeparation = isAutoFormatBlankLineSeparation
        self.isAutoFormatTrailingWhitespaceTrim = isAutoFormatTrailingWhitespaceTrim
        self.isProseSuggestionsEnabled = isProseSuggestionsEnabled
        self.onAIAssist = onAIAssist
        self.onToggleSourceView = onToggleSourceView
        self.onOpenFile = onOpenFile
        self.onNewFile = onNewFile
        self.onCloseFile = onCloseFile
        self.onFindReplace = onFindReplace
        self.onImageReceived = onImageReceived
        self.showAIContextMenuActions = showAIContextMenuActions
        self.onContextMenuImprove = onContextMenuImprove
        self.onContextMenuSummarize = onContextMenuSummarize
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
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.renderConfig = renderConfig
        context.coordinator.managedTextView = textView

        // Wire improve writing coordinator per FEAT-011
        if let improveCoordinator {
            improveCoordinator.textViewDelegate = context.coordinator
        }

        // Wire tone adjustment coordinator per FEAT-023
        if let toneCoordinator {
            toneCoordinator.textViewDelegate = context.coordinator
        }

        // Wire ghost text coordinator per FEAT-056
        if let ghostTextCoordinator {
            ghostTextCoordinator.textViewDelegate = context.coordinator
            context.coordinator.ghostTextCoordinator = ghostTextCoordinator
        }

        // Wire Shift-Tab handler for list outdent per FEAT-004
        textView.onShiftTab = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            return coordinator.handleShiftTab(in: textView)
        }

        // Wire interactive element handlers per FEAT-049
        textView.onCheckboxTap = { [weak coordinator = context.coordinator, weak textView] range in
            guard let coordinator, let textView else { return }
            coordinator.toggleCheckbox(at: range, in: textView)
        }
        textView.onLinkTap = { [weak coordinator = context.coordinator] url in
            coordinator?.handleLinkTap(url: url)
        }

        // Wire formatting shortcut handlers per FEAT-009
        // Stored as named closures so EditorState can also expose them
        // to the floating action bar per FEAT-054.
        let boldAction: () -> Void = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleBold(in: textView)
        }
        let italicAction: () -> Void = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleItalic(in: textView)
        }
        let linkAction: () -> Void = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleLinkInsert(in: textView)
        }
        textView.onBold = boldAction
        textView.onItalic = italicAction
        textView.onCode = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleCode(in: textView)
        }
        textView.onInsertLink = linkAction

        // Expose formatting actions on EditorState so the floating action bar
        // can dispatch them without direct text view access per FEAT-054.
        editorState.performBold = boldAction
        editorState.performItalic = italicAction
        editorState.performLink = linkAction

        // Expose replace-text action for find/replace per FEAT-017 AC-3.
        editorState.performReplaceText = { [weak coordinator = context.coordinator, weak textView] newText in
            guard let coordinator, let textView else { return }
            coordinator.handleReplaceText(newText, in: textView)
        }

        // Expose find highlight action per FEAT-017.
        editorState.applyFindHighlights = { [weak coordinator = context.coordinator, weak textView] matches, currentIndex in
            guard let coordinator, let textView else { return }
            coordinator.applyFindHighlights(matches, currentIndex: currentIndex, in: textView)
        }

        // Wire app-level shortcut handlers per FEAT-009
        textView.onAIAssist = onAIAssist
        textView.onToggleSourceView = onToggleSourceView
        textView.onOpenFile = onOpenFile
        textView.onNewFile = onNewFile
        textView.onCloseFile = onCloseFile
        textView.onFindReplace = onFindReplace

        // Wire image drop/paste handler per FEAT-020
        textView.onImageReceived = onImageReceived

        // Wire context menu AI actions per FEAT-058
        context.coordinator.showAIContextMenuActions = showAIContextMenuActions
        context.coordinator.onContextMenuImprove = onContextMenuImprove
        context.coordinator.onContextMenuSummarize = onContextMenuSummarize

        // Apply initial layout metrics per FEAT-010
        if let config = renderConfig {
            textView.layoutMetrics = config.layoutMetrics
        }

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

        // Ensure managed text view and improve coordinator are wired per FEAT-011
        coordinator.managedTextView = textView
        if let improveCoordinator, improveCoordinator.textViewDelegate == nil {
            improveCoordinator.textViewDelegate = coordinator
        }

        // Ensure tone adjustment coordinator stays wired per FEAT-023
        if let toneCoordinator, toneCoordinator.textViewDelegate == nil {
            toneCoordinator.textViewDelegate = coordinator
        }

        // Ensure ghost text coordinator stays wired per FEAT-056
        if let ghostTextCoordinator, ghostTextCoordinator.textViewDelegate == nil {
            ghostTextCoordinator.textViewDelegate = coordinator
            coordinator.ghostTextCoordinator = ghostTextCoordinator
        }

        // Track whether we need to re-render
        let textChanged = coordinator.updateTextView(textView, with: text)
        let previousVariant = coordinator.renderConfig?.colorVariant
        let viewModeChanged = coordinator.renderConfig?.isSourceView != renderConfig?.isSourceView
        let colorChanged = previousVariant != nil && previousVariant != renderConfig?.colorVariant
        let configChanged = viewModeChanged || colorChanged

        // Update render configuration
        coordinator.renderConfig = renderConfig

        // Update layout metrics per FEAT-010
        if let config = renderConfig {
            textView.layoutMetrics = config.layoutMetrics
        }

        // Update editable state
        textView.isEditable = isEditable

        // Update spell check per [A-054]
        let spellType: UITextSpellCheckingType = isSpellCheckEnabled ? .yes : .no
        if textView.spellCheckingType != spellType {
            textView.spellCheckingType = spellType
        }

        // Update formatting settings per FEAT-053 AC-6
        coordinator.updateFormattingSettings(
            isHeadingSpacingEnabled: isAutoFormatHeadingSpacing,
            isBlankLineSeparationEnabled: isAutoFormatBlankLineSeparation,
            isTrailingWhitespaceTrimEnabled: isAutoFormatTrailingWhitespaceTrim
        )

        // Update prose suggestions setting per FEAT-022
        coordinator.doctorCoordinator.proseSuggestionsEnabled = isProseSuggestionsEnabled

        // Apply theme background color per FEAT-007
        if let colors = renderConfig?.colors {
            textView.applyThemeBackground(colors.background, animated: colorChanged)
        }

        // Re-render if text loaded from binding or view/theme changed
        if viewModeChanged, renderConfig != nil {
            // Use cursor-mapping toggle path per FEAT-050
            coordinator.handleViewModeToggle(
                for: textView,
                toSourceView: renderConfig?.isSourceView ?? false
            )
        } else if (textChanged || configChanged), renderConfig != nil {
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
    /// Handler for link clicks per FEAT-049. Receives the URL when a link is clicked.
    /// When nil, links open in the system browser by default.
    public var onLinkTap: ((URL) -> Void)?
    /// Optional improve writing coordinator to wire as text view delegate per FEAT-011.
    public var improveCoordinator: ImproveWritingCoordinator?
    /// Optional tone adjustment coordinator per FEAT-023.
    public var toneCoordinator: ToneAdjustmentCoordinator?
    /// Optional ghost text coordinator for AI continue writing per FEAT-056.
    public var ghostTextCoordinator: GhostTextCoordinator?

    // MARK: - Formatting settings per FEAT-053 AC-6

    /// Whether heading spacing auto-format is enabled.
    public var isAutoFormatHeadingSpacing: Bool
    /// Whether blank line separation auto-format is enabled.
    public var isAutoFormatBlankLineSeparation: Bool
    /// Whether trailing whitespace trimming on Enter is enabled.
    public var isAutoFormatTrailingWhitespaceTrim: Bool

    /// Whether prose suggestion doctor rules are enabled per FEAT-022.
    public var isProseSuggestionsEnabled: Bool

    // MARK: - App-level keyboard shortcut handlers per FEAT-009

    /// Called when Cmd+J is pressed (AI assist).
    public var onAIAssist: (() -> Void)?
    /// Called when Cmd+Shift+P is pressed (toggle source view).
    public var onToggleSourceView: (() -> Void)?
    /// Called when Cmd+O is pressed (open file).
    public var onOpenFile: (() -> Void)?
    /// Called when Cmd+N is pressed (new file).
    public var onNewFile: (() -> Void)?
    /// Called when Cmd+W is pressed (close file).
    public var onCloseFile: (() -> Void)?
    /// Called when Cmd+F is pressed (find and replace) per FEAT-017.
    public var onFindReplace: (() -> Void)?

    /// Called when an image is dropped or pasted per FEAT-020 (F-015).
    /// Receives raw image data and a suggested filename.
    public var onImageReceived: ((_ imageData: Data, _ suggestedName: String) -> Void)?

    // MARK: - Context menu AI actions per FEAT-058

    /// Whether AI actions should appear in the right-click context menu.
    public var showAIContextMenuActions: Bool
    /// Called when Improve Writing is selected from the context menu.
    public var onContextMenuImprove: (() -> Void)?
    /// Called when Summarize is selected from the context menu.
    public var onContextMenuSummarize: (() -> Void)?

    public init(
        text: SwiftUI.Binding<String>,
        editorState: EditorState,
        renderConfig: RenderConfiguration? = nil,
        isEditable: Bool = true,
        isSpellCheckEnabled: Bool = true,
        onTextChange: ((String) -> Void)? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
        improveCoordinator: ImproveWritingCoordinator? = nil,
        toneCoordinator: ToneAdjustmentCoordinator? = nil,
        ghostTextCoordinator: GhostTextCoordinator? = nil,
        isAutoFormatHeadingSpacing: Bool = true,
        isAutoFormatBlankLineSeparation: Bool = true,
        isAutoFormatTrailingWhitespaceTrim: Bool = true,
        isProseSuggestionsEnabled: Bool = false,
        onAIAssist: (() -> Void)? = nil,
        onToggleSourceView: (() -> Void)? = nil,
        onOpenFile: (() -> Void)? = nil,
        onNewFile: (() -> Void)? = nil,
        onCloseFile: (() -> Void)? = nil,
        onFindReplace: (() -> Void)? = nil,
        onImageReceived: ((_ imageData: Data, _ suggestedName: String) -> Void)? = nil,
        showAIContextMenuActions: Bool = false,
        onContextMenuImprove: (() -> Void)? = nil,
        onContextMenuSummarize: (() -> Void)? = nil
    ) {
        self._text = text
        self.editorState = editorState
        self.renderConfig = renderConfig
        self.isEditable = isEditable
        self.isSpellCheckEnabled = isSpellCheckEnabled
        self.onTextChange = onTextChange
        self.onLinkTap = onLinkTap
        self.improveCoordinator = improveCoordinator
        self.toneCoordinator = toneCoordinator
        self.ghostTextCoordinator = ghostTextCoordinator
        self.isAutoFormatHeadingSpacing = isAutoFormatHeadingSpacing
        self.isAutoFormatBlankLineSeparation = isAutoFormatBlankLineSeparation
        self.isAutoFormatTrailingWhitespaceTrim = isAutoFormatTrailingWhitespaceTrim
        self.isProseSuggestionsEnabled = isProseSuggestionsEnabled
        self.onAIAssist = onAIAssist
        self.onToggleSourceView = onToggleSourceView
        self.onOpenFile = onOpenFile
        self.onNewFile = onNewFile
        self.onCloseFile = onCloseFile
        self.onFindReplace = onFindReplace
        self.onImageReceived = onImageReceived
        self.showAIContextMenuActions = showAIContextMenuActions
        self.onContextMenuImprove = onContextMenuImprove
        self.onContextMenuSummarize = onContextMenuSummarize
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
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.renderConfig = renderConfig
        context.coordinator.managedTextView = textView

        // Wire improve writing coordinator per FEAT-011
        if let improveCoordinator {
            improveCoordinator.textViewDelegate = context.coordinator
        }

        // Wire tone adjustment coordinator per FEAT-023
        if let toneCoordinator {
            toneCoordinator.textViewDelegate = context.coordinator
        }

        // Wire ghost text coordinator per FEAT-056
        if let ghostTextCoordinator {
            ghostTextCoordinator.textViewDelegate = context.coordinator
            context.coordinator.ghostTextCoordinator = ghostTextCoordinator
        }

        // Wire Shift-Tab handler for list outdent per FEAT-004
        textView.onShiftTab = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            return coordinator.handleShiftTab(in: textView)
        }

        // Wire interactive element handlers per FEAT-049
        textView.onCheckboxTap = { [weak coordinator = context.coordinator, weak textView] range in
            guard let coordinator, let textView else { return }
            coordinator.toggleCheckbox(at: range, in: textView)
        }
        textView.onLinkTap = { [weak coordinator = context.coordinator] url in
            coordinator?.handleLinkTap(url: url)
        }

        // Wire formatting shortcut handlers per FEAT-009
        // Stored as named closures so EditorState can also expose them
        // to the floating action bar per FEAT-054.
        let boldAction: () -> Void = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleBold(in: textView)
        }
        let italicAction: () -> Void = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleItalic(in: textView)
        }
        let linkAction: () -> Void = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleLinkInsert(in: textView)
        }
        textView.onBold = boldAction
        textView.onItalic = italicAction
        textView.onCode = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.handleCode(in: textView)
        }
        textView.onInsertLink = linkAction

        // Expose formatting actions on EditorState so the floating action bar
        // can dispatch them without direct text view access per FEAT-054.
        editorState.performBold = boldAction
        editorState.performItalic = italicAction
        editorState.performLink = linkAction

        // Expose replace-text action for find/replace per FEAT-017 AC-3.
        editorState.performReplaceText = { [weak coordinator = context.coordinator, weak textView] newText in
            guard let coordinator, let textView else { return }
            coordinator.handleReplaceText(newText, in: textView)
        }

        // Expose find highlight action per FEAT-017.
        editorState.applyFindHighlights = { [weak coordinator = context.coordinator, weak textView] matches, currentIndex in
            guard let coordinator, let textView else { return }
            coordinator.applyFindHighlights(matches, currentIndex: currentIndex, in: textView)
        }

        // Wire app-level shortcut handlers per FEAT-009
        textView.onAIAssist = onAIAssist
        textView.onToggleSourceView = onToggleSourceView
        textView.onOpenFile = onOpenFile
        textView.onNewFile = onNewFile
        textView.onCloseFile = onCloseFile
        textView.onFindReplace = onFindReplace

        // Wire image drop/paste handler per FEAT-020
        textView.onImageReceived = onImageReceived

        // Wire context menu AI actions per FEAT-058
        textView.showAIContextMenuActions = showAIContextMenuActions
        textView.onContextMenuImprove = onContextMenuImprove
        textView.onContextMenuSummarize = onContextMenuSummarize

        // Apply initial layout metrics per FEAT-010
        if let config = renderConfig {
            textView.layoutMetrics = config.layoutMetrics
        }

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

        // Ensure managed text view and improve coordinator are wired per FEAT-011
        coordinator.managedTextView = textView
        if let improveCoordinator, improveCoordinator.textViewDelegate == nil {
            improveCoordinator.textViewDelegate = coordinator
        }

        // Ensure tone adjustment coordinator stays wired per FEAT-023
        if let toneCoordinator, toneCoordinator.textViewDelegate == nil {
            toneCoordinator.textViewDelegate = coordinator
        }

        // Ensure ghost text coordinator stays wired per FEAT-056
        if let ghostTextCoordinator, ghostTextCoordinator.textViewDelegate == nil {
            ghostTextCoordinator.textViewDelegate = coordinator
            coordinator.ghostTextCoordinator = ghostTextCoordinator
        }

        let textChanged = coordinator.updateTextView(textView, with: text)
        let previousVariant = coordinator.renderConfig?.colorVariant
        let viewModeChanged = coordinator.renderConfig?.isSourceView != renderConfig?.isSourceView
        let colorChanged = previousVariant != nil && previousVariant != renderConfig?.colorVariant
        let configChanged = viewModeChanged || colorChanged

        coordinator.renderConfig = renderConfig

        // Update layout metrics per FEAT-010
        if let config = renderConfig {
            textView.layoutMetrics = config.layoutMetrics
        }

        textView.isEditable = isEditable
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled

        // Update formatting settings per FEAT-053 AC-6
        coordinator.updateFormattingSettings(
            isHeadingSpacingEnabled: isAutoFormatHeadingSpacing,
            isBlankLineSeparationEnabled: isAutoFormatBlankLineSeparation,
            isTrailingWhitespaceTrimEnabled: isAutoFormatTrailingWhitespaceTrim
        )

        // Update prose suggestions setting per FEAT-022
        coordinator.doctorCoordinator.proseSuggestionsEnabled = isProseSuggestionsEnabled

        // Apply theme background color per FEAT-007
        if let colors = renderConfig?.colors {
            textView.applyThemeBackground(colors.background, animated: colorChanged)
        }

        if viewModeChanged, renderConfig != nil {
            // Use cursor-mapping toggle path per FEAT-050
            coordinator.handleViewModeToggle(
                for: textView,
                toSourceView: renderConfig?.isSourceView ?? false
            )
        } else if (textChanged || configChanged), renderConfig != nil {
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
