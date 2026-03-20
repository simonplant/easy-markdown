/// TextKit 2 text view configuration per [A-004].
/// Configures UITextView (iOS) / NSTextView (macOS) with TextKit 2,
/// Dynamic Type support, RTL/CJK handling, and performance instrumentation.

import Foundation
import os
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
    /// Handler for source view toggle (Cmd+Shift+P).
    public var onToggleSourceView: (() -> Void)?
    /// Handler for open file (Cmd+O).
    public var onOpenFile: (() -> Void)?
    /// Handler for new file (Cmd+N).
    public var onNewFile: (() -> Void)?
    /// Handler for close file (Cmd+W).
    public var onCloseFile: (() -> Void)?

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

        // CJK IME: UITextView handles markedText natively.
        // We must not interfere with the input system's composition state.

        // RTL: enable natural text alignment so the system
        // picks the correct direction based on content per AC-4.
        textAlignment = .natural

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
    @objc private func handleToggleSource() { onToggleSourceView?() }
    @objc private func handleOpenFile() { onOpenFile?() }
    @objc private func handleNewFile() { onNewFile?() }
    @objc private func handleCloseFile() { onCloseFile?() }

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

    /// Applies current layout metrics to text container insets per FEAT-010.
    private func applyLayoutMetrics() {
        textContainerInset = layoutMetrics.textContainerInsets
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Compute effective insets: if a maxContentWidth is set and the view is wider,
        // center the content by increasing horizontal insets per FEAT-010 AC-3.
        var insets = layoutMetrics.textContainerInsets
        let lineFragPadding = textContainer.lineFragmentPadding * 2

        if let maxWidth = layoutMetrics.maxContentWidth {
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
        // This ensures proper line wrapping without horizontal scrolling.
        let containerWidth = bounds.width - insets.left - insets.right - lineFragPadding
        if containerWidth > 0, textContainer.size.width != containerWidth {
            textContainer.size = CGSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
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
    /// Handler for source view toggle (Cmd+Shift+P).
    public var onToggleSourceView: (() -> Void)?
    /// Handler for open file (Cmd+O).
    public var onOpenFile: (() -> Void)?
    /// Handler for new file (Cmd+N).
    public var onNewFile: (() -> Void)?
    /// Handler for close file (Cmd+W).
    public var onCloseFile: (() -> Void)?

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

        // RTL: natural alignment
        alignment = .natural

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
        case ("p", [.command, .shift]):
            onToggleSourceView?(); return true
        case ("o", .command):
            onOpenFile?(); return true
        case ("n", .command):
            onNewFile?(); return true
        case ("w", .command):
            onCloseFile?(); return true
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
    public override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
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
        return super.menu(for: event)
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
