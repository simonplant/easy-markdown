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

// MARK: - macOS

#elseif canImport(AppKit)

/// TextKit 2-backed text view for macOS per [A-004].
///
/// Uses `NSTextLayoutManager` and `NSTextContentStorage` for modern text layout.
/// Supports CJK IME composition, RTL text, and unlimited undo.
public final class EMTextView: NSTextView {

    /// The editor state this view reports changes to.
    public weak var editorState: EditorState?

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
