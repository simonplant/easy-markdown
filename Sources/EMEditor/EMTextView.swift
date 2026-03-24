/// TextKit 2 text view configuration per [A-004].
/// Configures UITextView (iOS) / NSTextView (macOS) with TextKit 2,
/// Dynamic Type support, RTL/CJK handling, and performance instrumentation.

import Foundation
import os
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "textview")

// MARK: - iOS

#if canImport(UIKit)

/// TextKit 2-backed text view for iOS per [A-004].
///
/// Uses `NSTextLayoutManager` and `NSTextContentStorage` for modern text layout.
/// Supports CJK IME composition, RTL text, Dynamic Type, and unlimited undo.
public final class EMTextView: UITextView {

    /// The editor state this view reports changes to.
    public weak var editorState: EditorState?

    /// Handler for Shift-Tab key. Returns true if the event was consumed.
    /// Set by TextViewCoordinator for list outdent per FEAT-004.
    public var onShiftTab: (() -> Bool)?

    /// Handler for task list checkbox tap per FEAT-049.
    /// Called with the NSRange of the `[ ]` or `[x]` marker in the text storage.
    public var onCheckboxTap: ((NSRange) -> Void)?

    /// Handler for link tap per FEAT-049.
    /// Called with the link URL when a link is tapped in rich view.
    public var onLinkTap: ((URL) -> Void)?

    /// Handler for link long-press per FEAT-049 AC-4.
    /// Called with the link URL when a link is long-pressed.
    /// The view shows the URL and a copy option.
    public var onLinkLongPress: ((URL) -> Void)?

    // MARK: - Keyboard Shortcut Handlers per FEAT-009

    /// Handler for bold formatting (Cmd+B).
    public var onBold: (() -> Void)?
    /// Handler for italic formatting (Cmd+I).
    public var onItalic: (() -> Void)?
    /// Handler for code formatting (Cmd+Shift+K).
    public var onCode: (() -> Void)?
    /// Handler for link insertion (Cmd+K).
    public var onInsertLink: (() -> Void)?
    /// Handler for AI assist (Cmd+J) per [A-023].
    public var onAIAssist: (() -> Void)?
    /// Handler for voice control (Cmd+Shift+J) per FEAT-068 AC-7.
    public var onVoiceControl: (() -> Void)?
    /// Handler for source view toggle (Cmd+Shift+P).
    public var onToggleSourceView: (() -> Void)?
    /// Handler for open file (Cmd+O).
    public var onOpenFile: (() -> Void)?
    /// Handler for new file (Cmd+N).
    public var onNewFile: (() -> Void)?
    /// Handler for close file (Cmd+W).
    public var onCloseFile: (() -> Void)?
    /// Handler for find/replace (Cmd+F) per FEAT-017.
    public var onFindReplace: (() -> Void)?

    /// Handler for Tab key when ghost text is active per FEAT-056.
    /// Returns true if ghost text was accepted (Tab consumed), false otherwise.
    public var onGhostTextAccept: (() -> Bool)?

    /// Handler for image drop/paste per FEAT-020 (F-015).
    /// Called with raw image data and a suggested filename.
    /// The receiver should prompt for save location and insert markdown.
    public var onImageReceived: ((_ imageData: Data, _ suggestedName: String) -> Void)?

    /// Current layout metrics for device-aware spacing per FEAT-010.
    public var layoutMetrics: LayoutMetrics = .current {
        didSet { applyLayoutMetrics() }
    }

    /// Creates a TextKit 2-configured text view.
    ///
    /// - Parameter editorState: The editor state to synchronize with.
    public init(editorState: EditorState?) {
        self.editorState = editorState

        // TextKit 2 setup: create NSTextContentStorage + NSTextLayoutManager
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(
            width: 0, // Will be updated by Auto Layout
            height: CGFloat.greatestFiniteMagnitude
        ))
        layoutManager.textContainer = container

        super.init(frame: .zero, textContainer: container)

        configureTextView()
        setupInteractiveGestures()
        setupImageDropInteraction()
        logger.debug("EMTextView initialized with TextKit 2")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(editorState:)")
    }

    private func configureTextView() {
        // Typography: Dynamic Type support per [D-A11Y-2]
        font = UIFont.preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true

        // Text behavior
        autocorrectionType = .default
        spellCheckingType = .yes
        smartQuotesType = .default
        smartDashesType = .default
        smartInsertDeleteType = .default

        // CJK IME: UITextView handles markedText natively per FEAT-051 AC-5.
        // We must not interfere with the input system's composition state.
        // The text view's insertText/markedText pipeline handles composition display.

        // RTL: enable natural text alignment so the system picks the correct
        // direction based on content per FEAT-051 AC-2/AC-3. The actual per-paragraph
        // writing direction is set via NSParagraphStyle.baseWritingDirection = .natural
        // in the MarkdownRenderer, which allows the Unicode BiDi algorithm to determine
        // direction from the text content.
        textAlignment = .natural

        // CJK line breaking: TextKit 2 with byWordWrapping (the default) respects
        // character-boundary breaking for CJK text per FEAT-051 AC-1. CJK ideographs
        // can break at any character boundary, while Latin text breaks at word boundaries.
        textContainer.lineBreakMode = .byWordWrapping

        // Appearance — default background, overridden by applyThemeBackground
        backgroundColor = .systemBackground

        // Apply device-aware margins per FEAT-010
        applyLayoutMetrics()

        // Scrolling: enable for large documents.
        // TextKit 2's viewport-based layout supports 120fps on ProMotion per [D-PERF-3].
        isScrollEnabled = true
        alwaysBounceVertical = true

        // Accessibility
        accessibilityLabel = NSLocalizedString(
            "Document editor",
            comment: "Accessibility label for the main text editing area"
        )

        // Keyboard
        keyboardDismissMode = .interactive
    }

    // MARK: - Image Drop/Paste per FEAT-020

    /// Registers this text view as a drop target for images per FEAT-020 AC-1.
    private func setupImageDropInteraction() {
        let dropInteraction = UIDropInteraction(delegate: self)
        addInteraction(dropInteraction)
    }

    /// Intercepts paste to handle image data from clipboard per FEAT-020 AC-3.
    /// Text paste takes priority — only intercepts when clipboard has images but no text.
    public override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general

        // Only intercept for images when there is no text on the pasteboard.
        // This prevents hijacking rich text paste that happens to include image data.
        if !pasteboard.hasStrings, pasteboard.hasImages, let image = pasteboard.image {
            if let data = image.pngData() {
                let suggestedName = Self.suggestedImageFilename(extension: "png")
                onImageReceived?(data, suggestedName)
                return
            }
        }

        // Fall through to normal paste for text
        super.paste(sender)
    }

    /// Generates a suggested filename for a pasted/dropped image.
    static func suggestedImageFilename(extension ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "image-\(formatter.string(from: Date())).\(ext)"
    }

    // MARK: - Interactive Elements (FEAT-049)

    /// Sets up tap and long-press gestures for interactive elements (checkboxes and links).
    /// Uses a custom gesture recognizer that only fires when the tap lands
    /// on a checkbox or link, avoiding interference with normal editing.
    private func setupInteractiveGestures() {
        let tap = InteractiveTapGesture(target: self, action: #selector(handleInteractiveTap(_:)))
        tap.targetTextView = self
        addGestureRecognizer(tap)

        // Long-press gesture for link preview per FEAT-049 AC-4
        let longPress = InteractiveLongPressGesture(
            target: self,
            action: #selector(handleInteractiveLongPress(_:))
        )
        longPress.targetTextView = self
        longPress.minimumPressDuration = 0.5
        addGestureRecognizer(longPress)
    }

    /// Returns the interactive element (checkbox or link) at the given point, if any.
    func interactiveElement(at point: CGPoint) -> InteractiveElement? {
        guard let position = closestPosition(to: point) else { return nil }
        let index = offset(from: beginningOfDocument, to: position)
        guard index >= 0, index < textStorage.length else { return nil }

        // Check for checkbox first (higher priority — smaller target)
        if let state = textStorage.attribute(.taskListCheckbox, at: index, effectiveRange: nil) as? String {
            var range = NSRange()
            textStorage.attribute(.taskListCheckbox, at: index, effectiveRange: &range)
            return .checkbox(range: range, isChecked: state == "checked")
        }

        // Check for link
        if let url = textStorage.attribute(.link, at: index, effectiveRange: nil) as? URL {
            return .link(url: url)
        }

        return nil
    }

    @objc private func handleInteractiveTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard let element = interactiveElement(at: point) else { return }

        switch element {
        case .checkbox(let range, _):
            onCheckboxTap?(range)
        case .link(let url):
            onLinkTap?(url)
        }
    }

    /// Shows a URL preview alert with a copy option on long-press per FEAT-049 AC-4.
    @objc private func handleInteractiveLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let point = recognizer.location(in: self)
        guard let element = interactiveElement(at: point),
              case .link(let url) = element else { return }

        let urlString = url.absoluteString
        let alert = UIAlertController(
            title: urlString,
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Copy URL", comment: "Copy link URL action"),
            style: .default
        ) { _ in
            UIPasteboard.general.string = urlString
        })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Open Link", comment: "Open link in browser action"),
            style: .default
        ) { [weak self] _ in
            self?.onLinkTap?(url)
        })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel action"),
            style: .cancel
        ))

        // Configure popover for iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = CGRect(origin: point, size: .zero)
        }

        // Present from the nearest view controller
        if let viewController = self.findViewController() {
            viewController.present(alert, animated: true)
        }
    }

    /// Walks the responder chain to find the nearest UIViewController.
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }

    // MARK: - Undo Manager

    /// Return the EditorState's undo manager for unlimited depth per [A-022].
    public override var undoManager: UndoManager? {
        editorState?.undoManager ?? super.undoManager
    }

    // MARK: - Key Commands per [A-060] and FEAT-009

    /// All keyboard shortcuts registered via UIKeyCommand.
    /// The system Cmd-hold overlay on iPad lists these automatically via `discoverabilityTitle`.
    public override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []

        // List outdent (FEAT-004)
        let shiftTab = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleShiftTab))
        shiftTab.discoverabilityTitle = NSLocalizedString("Outdent List Item", comment: "Keyboard shortcut")
        commands.append(shiftTab)

        // Text formatting per FEAT-009
        let bold = UIKeyCommand(input: "B", modifierFlags: .command, action: #selector(handleBold))
        bold.discoverabilityTitle = NSLocalizedString("Bold", comment: "Keyboard shortcut")
        commands.append(bold)

        let italic = UIKeyCommand(input: "I", modifierFlags: .command, action: #selector(handleItalic))
        italic.discoverabilityTitle = NSLocalizedString("Italic", comment: "Keyboard shortcut")
        commands.append(italic)

        let link = UIKeyCommand(input: "K", modifierFlags: .command, action: #selector(handleInsertLink))
        link.discoverabilityTitle = NSLocalizedString("Insert Link", comment: "Keyboard shortcut")
        commands.append(link)

        let code = UIKeyCommand(input: "K", modifierFlags: [.command, .shift], action: #selector(handleCode))
        code.discoverabilityTitle = NSLocalizedString("Code", comment: "Keyboard shortcut")
        commands.append(code)

        // AI per FEAT-009 and [A-023]
        let ai = UIKeyCommand(input: "J", modifierFlags: .command, action: #selector(handleAIAssist))
        ai.discoverabilityTitle = NSLocalizedString("AI Assist", comment: "Keyboard shortcut")
        commands.append(ai)

        // Voice control per FEAT-068 AC-7
        let voice = UIKeyCommand(input: "J", modifierFlags: [.command, .shift], action: #selector(handleVoiceControl))
        voice.discoverabilityTitle = NSLocalizedString("Voice Command", comment: "Keyboard shortcut")
        commands.append(voice)

        // App navigation per FEAT-009
        let toggleSource = UIKeyCommand(input: "P", modifierFlags: [.command, .shift], action: #selector(handleToggleSource))
        toggleSource.discoverabilityTitle = NSLocalizedString("Toggle Source View", comment: "Keyboard shortcut")
        commands.append(toggleSource)

        let openFile = UIKeyCommand(input: "O", modifierFlags: .command, action: #selector(handleOpenFile))
        openFile.discoverabilityTitle = NSLocalizedString("Open File", comment: "Keyboard shortcut")
        commands.append(openFile)

        let newFile = UIKeyCommand(input: "N", modifierFlags: .command, action: #selector(handleNewFile))
        newFile.discoverabilityTitle = NSLocalizedString("New File", comment: "Keyboard shortcut")
        commands.append(newFile)

        let closeFile = UIKeyCommand(input: "W", modifierFlags: .command, action: #selector(handleCloseFile))
        closeFile.discoverabilityTitle = NSLocalizedString("Close File", comment: "Keyboard shortcut")
        commands.append(closeFile)

        // Find and replace per FEAT-017
        let find = UIKeyCommand(input: "F", modifierFlags: .command, action: #selector(handleFindReplace))
        find.discoverabilityTitle = NSLocalizedString("Find and Replace", comment: "Keyboard shortcut")
        commands.append(find)

        return commands
    }

    @objc private func handleShiftTab() {
        if onShiftTab?() != true { /* Not consumed */ }
    }

    @objc private func handleBold() { onBold?() }
    @objc private func handleItalic() { onItalic?() }
    @objc private func handleInsertLink() { onInsertLink?() }
    @objc private func handleCode() { onCode?() }
    @objc private func handleAIAssist() { onAIAssist?() }
    @objc private func handleVoiceControl() { onVoiceControl?() }
    @objc private func handleToggleSource() { onToggleSourceView?() }
    @objc private func handleOpenFile() { onOpenFile?() }
    @objc private func handleNewFile() { onNewFile?() }
    @objc private func handleCloseFile() { onCloseFile?() }
    @objc private func handleFindReplace() { onFindReplace?() }

    // MARK: - Theme

    /// Updates the text view's background color to match the current theme per FEAT-007.
    /// Animated with a 200ms crossfade unless Reduced Motion is enabled.
    public func applyThemeBackground(_ color: PlatformColor, animated: Bool) {
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(
                with: self,
                duration: 0.2,
                options: .transitionCrossDissolve,
                animations: { self.backgroundColor = color }
            )
        } else {
            backgroundColor = color
        }
    }

    // MARK: - Layout

    /// Triggers a layout pass to recompute width-adaptive insets per FEAT-057.
    private func applyLayoutMetrics() {
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Use width-adaptive metrics for smooth Split View / Slide Over reflow per FEAT-057.
        // This runs on every frame during resize, computing margins from actual view width
        // rather than discrete size class thresholds. Prevents jumpiness at the
        // compact/regular boundary during Split View resize drag.
        let adaptedMetrics = LayoutMetrics.forAvailableWidth(bounds.width)
        var insets = adaptedMetrics.textContainerInsets
        let lineFragPadding = textContainer.lineFragmentPadding * 2

        // Center content if maxContentWidth is set and the view is wider per FEAT-010 AC-3.
        // On external displays and wide Split Views, this constrains content to ~65–80
        // characters for readability without letterboxing.
        if let maxWidth = adaptedMetrics.maxContentWidth {
            let availableWidth = bounds.width - lineFragPadding
            if availableWidth > maxWidth + insets.left + insets.right {
                let extraMargin = (availableWidth - maxWidth) / 2
                insets.left = max(insets.left, extraMargin)
                insets.right = max(insets.right, extraMargin)
            }
        }

        if textContainerInset != insets {
            textContainerInset = insets
        }

        // Update text container width to match view width minus insets.
        // This ensures proper line wrapping without horizontal scrolling,
        // including at Slide Over's minimum ~320pt width.
        let containerWidth = bounds.width - insets.left - insets.right - lineFragPadding
        if containerWidth > 0, textContainer.size.width != containerWidth {
            textContainer.size = CGSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }
}

// MARK: - UIDropInteractionDelegate per FEAT-020

extension EMTextView: UIDropInteractionDelegate {

    /// Accepts image drops per FEAT-020 AC-1.
    public func dropInteraction(
        _ interaction: UIDropInteraction,
        canHandle session: UIDropSession
    ) -> Bool {
        session.canLoadObjects(ofClass: UIImage.self)
    }

    /// Shows copy indicator for image drops.
    public func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidUpdate session: UIDropSession
    ) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    /// Loads dropped image data and invokes `onImageReceived` per FEAT-020 AC-1.
    public func dropInteraction(
        _ interaction: UIDropInteraction,
        performDrop session: UIDropSession
    ) {
        // Try to load file URL first to get the original filename
        for provider in session.items.map(\.itemProvider) {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // Try to get the original file data with filename
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                    guard let url, error == nil,
                          let data = try? Data(contentsOf: url) else {
                        // Fallback: load as UIImage and convert to PNG
                        provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                            guard let image = image as? UIImage,
                                  let pngData = image.pngData() else { return }
                            let name = EMTextView.suggestedImageFilename(extension: "png")
                            Task { @MainActor in
                                self?.onImageReceived?(pngData, name)
                            }
                        }
                        return
                    }

                    let filename = url.lastPathComponent
                    Task { @MainActor in
                        self?.onImageReceived?(data, filename)
                    }
                }
                return // Handle first image only
            }
        }
    }
}

/// Custom tap gesture recognizer that only fires when the tap lands
/// on an interactive element (checkbox or link) per FEAT-049.
/// When the tap is not on an interactive element, the gesture fails
/// immediately, allowing the text view's editing gestures to proceed.
class InteractiveTapGesture: UITapGestureRecognizer {
    weak var targetTextView: EMTextView?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let tv = targetTextView else {
            state = .failed
            return
        }

        let point = touch.location(in: tv)
        if tv.interactiveElement(at: point) != nil {
            super.touchesBegan(touches, with: event)
        } else {
            state = .failed
        }
    }
}

/// Custom long-press gesture recognizer that only fires on links per FEAT-049 AC-4.
/// Fails immediately if the touch is not on a link, preserving normal editing gestures.
class InteractiveLongPressGesture: UILongPressGestureRecognizer {
    weak var targetTextView: EMTextView?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let tv = targetTextView else {
            state = .failed
            return
        }

        let point = touch.location(in: tv)
        if let element = tv.interactiveElement(at: point), case .link = element {
            super.touchesBegan(touches, with: event)
        } else {
            state = .failed
        }
    }
}

// MARK: - macOS

#elseif canImport(AppKit)

/// TextKit 2-backed text view for macOS per [A-004].
///
/// Uses `NSTextLayoutManager` and `NSTextContentStorage` for modern text layout.
/// Supports CJK IME composition, RTL text, and unlimited undo.
public final class EMTextView: NSTextView {

    /// The editor state this view reports changes to.
    public weak var editorState: EditorState?

    /// Handler for Shift-Tab key. Returns true if the event was consumed.
    /// Set by TextViewCoordinator for list outdent per FEAT-004.
    public var onShiftTab: (() -> Bool)?

    /// Handler for task list checkbox click per FEAT-049.
    /// Called with the NSRange of the `[ ]` or `[x]` marker in the text storage.
    public var onCheckboxTap: ((NSRange) -> Void)?

    /// Handler for link click per FEAT-049.
    /// Called with the link URL when a link is clicked in rich view.
    public var onLinkTap: ((URL) -> Void)?

    /// Handler for link long-press per FEAT-049 AC-4 (unused on macOS, right-click menu used instead).
    public var onLinkLongPress: ((URL) -> Void)?

    // MARK: - Keyboard Shortcut Handlers per FEAT-009

    /// Handler for bold formatting (Cmd+B).
    public var onBold: (() -> Void)?
    /// Handler for italic formatting (Cmd+I).
    public var onItalic: (() -> Void)?
    /// Handler for code formatting (Cmd+Shift+K).
    public var onCode: (() -> Void)?
    /// Handler for link insertion (Cmd+K).
    public var onInsertLink: (() -> Void)?
    /// Handler for AI assist (Cmd+J) per [A-023].
    public var onAIAssist: (() -> Void)?
    /// Handler for voice control (Cmd+Shift+J) per FEAT-068 AC-7.
    public var onVoiceControl: (() -> Void)?
    /// Handler for source view toggle (Cmd+Shift+P).
    public var onToggleSourceView: (() -> Void)?
    /// Handler for open file (Cmd+O).
    public var onOpenFile: (() -> Void)?
    /// Handler for new file (Cmd+N).
    public var onNewFile: (() -> Void)?
    /// Handler for close file (Cmd+W).
    public var onCloseFile: (() -> Void)?
    /// Handler for find/replace (Cmd+F) per FEAT-017.
    public var onFindReplace: (() -> Void)?

    /// Handler for Tab key when ghost text is active per FEAT-056.
    /// Returns true if ghost text was accepted (Tab consumed), false otherwise.
    public var onGhostTextAccept: (() -> Bool)?

    /// Handler for image drop/paste per FEAT-020 (F-015).
    /// Called with raw image data and a suggested filename.
    public var onImageReceived: ((_ imageData: Data, _ suggestedName: String) -> Void)?

    // MARK: - Context Menu AI Actions per FEAT-058

    /// Whether AI actions should appear in the right-click context menu.
    public var showAIContextMenuActions: Bool = false
    /// Handler for AI Improve from context menu per FEAT-058.
    public var onContextMenuImprove: (() -> Void)?
    /// Handler for AI Summarize from context menu per FEAT-058.
    public var onContextMenuSummarize: (() -> Void)?

    /// Current layout metrics for device-aware spacing per FEAT-010.
    public var layoutMetrics: LayoutMetrics = .current {
        didSet { applyLayoutMetrics() }
    }

    /// Creates a TextKit 2-configured text view for macOS.
    public init(editorState: EditorState?) {
        self.editorState = editorState

        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        ))
        layoutManager.textContainer = container

        super.init(frame: .zero, textContainer: container)

        configureTextView()
        setupImageDragTypes()
        logger.debug("EMTextView initialized with TextKit 2 (macOS)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(editorState:)")
    }

    private func configureTextView() {
        // Typography
        font = NSFont.preferredFont(forTextStyle: .body)

        // Text behavior
        isAutomaticSpellingCorrectionEnabled = true
        isAutomaticQuoteSubstitutionEnabled = true
        isAutomaticDashSubstitutionEnabled = true

        // RTL: natural alignment per FEAT-051 AC-2/AC-3. Per-paragraph writing
        // direction is set via NSParagraphStyle.baseWritingDirection = .natural
        // in the MarkdownRenderer, allowing Unicode BiDi to determine direction.
        alignment = .natural

        // CJK IME: NSTextView handles marked text natively per FEAT-051 AC-5.
        // CJK line breaking at character boundaries is handled by TextKit 2's
        // default line break mode (.byWordWrapping) which breaks CJK at any
        // ideograph boundary per FEAT-051 AC-1.

        // Appearance — default background, overridden by applyThemeBackground
        backgroundColor = .textBackgroundColor

        // Apply device-aware margins per FEAT-010
        applyLayoutMetrics()

        // Scrolling
        isVerticallyResizable = true
        isHorizontallyResizable = false

        // Accessibility
        setAccessibilityLabel(NSLocalizedString(
            "Document editor",
            comment: "Accessibility label for the main text editing area"
        ))
    }

    /// Applies current layout metrics to text container inset per FEAT-010.
    private func applyLayoutMetrics() {
        textContainerInset = layoutMetrics.textContainerInset
    }

    // MARK: - Image Drop/Paste per FEAT-020

    /// Registers image drop types for macOS drag-and-drop per FEAT-020 AC-1.
    private func setupImageDragTypes() {
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    /// Accepts image file drops per FEAT-020 AC-1.
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) {
            return .copy
        }
        // Check for image data directly (e.g., from Preview or other apps)
        if pasteboard.types?.contains(.png) == true ||
           pasteboard.types?.contains(.tiff) == true {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    /// Handles dropped image files per FEAT-020 AC-1.
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Try to read a file URL for an image
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], let imageURL = urls.first {
            if let data = try? Data(contentsOf: imageURL) {
                onImageReceived?(data, imageURL.lastPathComponent)
                return true
            }
        }

        // Try to read image data directly (PNG or TIFF)
        if let pngData = pasteboard.data(forType: .png) {
            let name = Self.suggestedImageFilename(extension: "png")
            onImageReceived?(pngData, name)
            return true
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.tiffRepresentation.flatMap({
               NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
           }) {
            let name = Self.suggestedImageFilename(extension: "png")
            onImageReceived?(pngData, name)
            return true
        }

        return super.performDragOperation(sender)
    }

    /// Intercepts paste to handle image data from clipboard per FEAT-020 AC-3.
    /// Text paste takes priority — only intercepts when clipboard has images but no text.
    public override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Only intercept for images when there is no text on the pasteboard.
        // This prevents hijacking rich text paste that happens to include image data.
        let hasText = pasteboard.string(forType: .string) != nil ||
                      pasteboard.data(forType: .rtf) != nil ||
                      pasteboard.data(forType: .html) != nil

        if !hasText {
            if let pngData = pasteboard.data(forType: .png) {
                let name = Self.suggestedImageFilename(extension: "png")
                onImageReceived?(pngData, name)
                return
            }
            if let tiffData = pasteboard.data(forType: .tiff),
               let image = NSImage(data: tiffData),
               let pngData = image.tiffRepresentation.flatMap({
                   NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
               }) {
                let name = Self.suggestedImageFilename(extension: "png")
                onImageReceived?(pngData, name)
                return
            }

            // Check for image file URLs
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]) as? [URL], let imageURL = urls.first {
                if let data = try? Data(contentsOf: imageURL) {
                    onImageReceived?(data, imageURL.lastPathComponent)
                    return
                }
            }
        }

        // Fall through to normal paste
        super.paste(sender)
    }

    /// Generates a suggested filename for a pasted/dropped image.
    static func suggestedImageFilename(extension ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "image-\(formatter.string(from: Date())).\(ext)"
    }

    // MARK: - Key Commands per [A-060] and FEAT-009

    /// Override backtab (Shift-Tab) for list outdent per FEAT-004.
    public override func insertBacktab(_ sender: Any?) {
        if onShiftTab?() != true {
            super.insertBacktab(sender)
        }
    }

    /// Intercepts keyboard shortcuts for formatting, AI, and navigation per FEAT-009.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch (key, flags) {
        case ("b", .command):
            onBold?(); return true
        case ("i", .command):
            onItalic?(); return true
        case ("k", .command):
            onInsertLink?(); return true
        case ("k", [.command, .shift]):
            onCode?(); return true
        case ("j", .command):
            onAIAssist?(); return true
        case ("j", [.command, .shift]):
            onVoiceControl?(); return true
        case ("p", [.command, .shift]):
            onToggleSourceView?(); return true
        case ("o", .command):
            onOpenFile?(); return true
        case ("n", .command):
            onNewFile?(); return true
        case ("w", .command):
            onCloseFile?(); return true
        case ("f", .command):
            onFindReplace?(); return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Theme

    /// Updates the text view's background color to match the current theme per FEAT-007.
    /// Animated with a 200ms crossfade unless Reduced Motion is enabled.
    public func applyThemeBackground(_ color: PlatformColor, animated: Bool) {
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.animator().backgroundColor = color
            }
        } else {
            backgroundColor = color
        }
    }

    /// Return the EditorState's undo manager for unlimited depth per [A-022].
    public override var undoManager: UndoManager? {
        editorState?.undoManager ?? super.undoManager
    }

    // MARK: - Interactive Elements (FEAT-049)

    /// Returns the interactive element at the given point, if any.
    func interactiveElement(at point: CGPoint) -> InteractiveElement? {
        guard let textStorage else { return nil }
        let index = characterIndexForInsertion(at: point)
        guard index >= 0, index < textStorage.length else { return nil }

        if let state = textStorage.attribute(.taskListCheckbox, at: index, effectiveRange: nil) as? String {
            var range = NSRange()
            textStorage.attribute(.taskListCheckbox, at: index, effectiveRange: &range)
            return .checkbox(range: range, isChecked: state == "checked")
        }

        if let url = textStorage.attribute(.link, at: index, effectiveRange: nil) as? URL {
            return .link(url: url)
        }

        return nil
    }

    /// Intercepts mouse clicks on interactive elements (checkboxes and links).
    /// For non-interactive areas, passes through to normal text editing.
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let element = interactiveElement(at: point) {
            switch element {
            case .checkbox(let range, _):
                onCheckboxTap?(range)
                return
            case .link(let url):
                onLinkTap?(url)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Shows a context menu with URL preview and copy option on right-click per FEAT-049 AC-4.
    /// Adds AI actions when text is selected per FEAT-058 AC-3.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)

        // Link-specific context menu per FEAT-049 AC-4
        if let element = interactiveElement(at: point), case .link(let url) = element {
            let menu = NSMenu()

            // Show URL as disabled title item
            let titleItem = NSMenuItem(title: url.absoluteString, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())

            // Copy URL action
            let copyItem = NSMenuItem(
                title: NSLocalizedString("Copy URL", comment: "Copy link URL action"),
                action: #selector(copyLinkURL(_:)),
                keyEquivalent: ""
            )
            copyItem.representedObject = url.absoluteString
            copyItem.target = self
            menu.addItem(copyItem)

            // Open Link action
            let openItem = NSMenuItem(
                title: NSLocalizedString("Open Link", comment: "Open link in browser action"),
                action: #selector(openLinkURL(_:)),
                keyEquivalent: ""
            )
            openItem.representedObject = url
            openItem.target = self
            menu.addItem(openItem)

            return menu
        }

        // Standard context menu with AI actions per FEAT-058
        let menu = super.menu(for: event) ?? NSMenu()

        if selectedRange().length > 0 && showAIContextMenuActions {
            menu.addItem(NSMenuItem.separator())

            // AI submenu per FEAT-058 AC-3
            let aiMenu = NSMenu(title: NSLocalizedString("AI", comment: "AI context menu section"))

            let improveItem = NSMenuItem(
                title: NSLocalizedString("Improve Writing", comment: "Context menu AI action"),
                action: #selector(handleContextMenuImprove),
                keyEquivalent: ""
            )
            improveItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Improve Writing")
            improveItem.target = self
            aiMenu.addItem(improveItem)

            let summarizeItem = NSMenuItem(
                title: NSLocalizedString("Summarize", comment: "Context menu AI action"),
                action: #selector(handleContextMenuSummarize),
                keyEquivalent: ""
            )
            summarizeItem.image = NSImage(systemSymbolName: "text.badge.minus", accessibilityDescription: "Summarize")
            summarizeItem.target = self
            aiMenu.addItem(summarizeItem)

            let aiMenuItem = NSMenuItem(
                title: NSLocalizedString("AI", comment: "AI context menu section"),
                action: nil,
                keyEquivalent: ""
            )
            aiMenuItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI")
            aiMenuItem.submenu = aiMenu
            menu.addItem(aiMenuItem)
        }

        return menu
    }

    @objc private func handleContextMenuImprove() {
        onContextMenuImprove?()
    }

    @objc private func handleContextMenuSummarize() {
        onContextMenuSummarize?()
    }

    @objc private func copyLinkURL(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    @objc private func openLinkURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onLinkTap?(url)
    }

    // MARK: - Spell Check Suppression per [A-054]

    /// Overrides the system spell check indicator to skip ranges marked
    /// with `.spellCheckExcluded` (code blocks, code spans, URLs, images).
    public override func setSpellingState(_ value: Int, range charRange: NSRange) {
        guard let textStorage else {
            super.setSpellingState(value, range: charRange)
            return
        }

        // Check if the target range overlaps with any spell-check-excluded range.
        // If so, don't apply the spelling state (effectively suppressing the underline).
        var isExcluded = false
        textStorage.enumerateAttribute(
            .spellCheckExcluded,
            in: charRange,
            options: []
        ) { attrValue, _, stop in
            if attrValue as? Bool == true {
                isExcluded = true
                stop.pointee = true
            }
        }

        guard !isExcluded else { return }
        super.setSpellingState(value, range: charRange)
    }
}

#endif

// MARK: - Interactive Element Types

/// An interactive element detected at a tap/click location per FEAT-049.
enum InteractiveElement {
    /// A task list checkbox with its range and current state.
    case checkbox(range: NSRange, isChecked: Bool)
    /// A tappable link with its destination URL.
    case link(url: URL)
}

// MARK: - os_signpost helper

/// Lightweight wrapper for performance signposting per [A-037].
struct OSSignpost {
    let log: OSLog

    init(subsystem: String, category: String) {
        self.log = OSLog(subsystem: subsystem, category: category)
    }

    func begin(_ name: StaticString) {
        os_signpost(.begin, log: log, name: name)
    }

    func end(_ name: StaticString) {
        os_signpost(.end, log: log, name: name)
    }
}
