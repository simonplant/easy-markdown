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
        textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

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

    // MARK: - Undo Manager

    /// Return the EditorState's undo manager for unlimited depth per [A-022].
    public override var undoManager: UndoManager? {
        editorState?.undoManager ?? super.undoManager
    }

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

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Update text container width to match view width minus insets.
        // This ensures proper line wrapping without horizontal scrolling.
        let insets = textContainerInset
        let containerWidth = bounds.width - insets.left - insets.right
            - textContainer.lineFragmentPadding * 2
        if containerWidth > 0, textContainer.size.width != containerWidth {
            textContainer.size = CGSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
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
        textContainerInset = NSSize(width: 16, height: 16)

        // Scrolling
        isVerticallyResizable = true
        isHorizontallyResizable = false

        // Accessibility
        setAccessibilityLabel(NSLocalizedString(
            "Document editor",
            comment: "Accessibility label for the main text editing area"
        ))
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
}

#endif

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
