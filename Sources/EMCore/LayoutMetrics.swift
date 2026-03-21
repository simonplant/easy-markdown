/// Device-aware layout metrics for typography and spacing per FEAT-010 and [A-052].
///
/// Provides responsive margins, content width constraints, line height, and paragraph
/// spacing that adapt per device class. iPhone gets compact margins (16pt),
/// iPad gets comfortable margins (32pt), and large screens constrain content width
/// to 65–80 characters for optimal readability.

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Layout metrics that adapt to device class and screen size per FEAT-010.
///
/// Usage:
/// ```swift
/// let metrics = LayoutMetrics.current
/// textView.textContainerInset = metrics.textContainerInsets
/// ```
public struct LayoutMetrics: Sendable {

    // MARK: - Margins

    /// Horizontal margin for text content (leading/trailing).
    public let horizontalMargin: CGFloat

    /// Vertical margin for text content (top/bottom).
    public let verticalMargin: CGFloat

    // MARK: - Content Width

    /// Maximum content width in points. `nil` means no constraint (use full width).
    /// On iPad landscape and external displays, constrains to ~65–80 characters.
    public let maxContentWidth: CGFloat?

    // MARK: - Typography Spacing

    /// Line height multiplier relative to font size (1.5–1.7x per AC-4).
    public let lineHeightMultiplier: CGFloat

    /// Paragraph spacing multiplier relative to computed line height (≥0.5x per AC-4).
    public let paragraphSpacingMultiplier: CGFloat

    // MARK: - Computed Spacing

    /// Computes the line spacing (extra leading) for a given font size.
    ///
    /// Line spacing is the additional space between baselines beyond the font's
    /// natural line height. For a body font at 17pt with multiplier 1.6:
    /// desired line height = 17 × 1.6 = 27.2pt; if the font's line height is ~20pt,
    /// extra spacing = ~7.2pt.
    public func lineSpacing(forFontSize fontSize: CGFloat) -> CGFloat {
        let desiredLineHeight = fontSize * lineHeightMultiplier
        // NSParagraphStyle.lineSpacing is added to the font's natural line height.
        // Approximate the font's natural line height as ~1.2x the font size.
        let naturalLineHeight = fontSize * 1.2
        return max(0, desiredLineHeight - naturalLineHeight)
    }

    /// Computes paragraph spacing for a given font size.
    public func paragraphSpacing(forFontSize fontSize: CGFloat) -> CGFloat {
        let lineHeight = fontSize * lineHeightMultiplier
        return lineHeight * paragraphSpacingMultiplier
    }

    // MARK: - Platform Insets

    #if canImport(UIKit)
    /// Text container insets for UITextView.
    public var textContainerInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: verticalMargin,
            left: horizontalMargin,
            bottom: verticalMargin,
            right: horizontalMargin
        )
    }
    #elseif canImport(AppKit)
    /// Text container inset for NSTextView.
    public var textContainerInset: NSSize {
        NSSize(width: horizontalMargin, height: verticalMargin)
    }
    #endif

    // MARK: - Initializer

    public init(
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat,
        maxContentWidth: CGFloat?,
        lineHeightMultiplier: CGFloat,
        paragraphSpacingMultiplier: CGFloat
    ) {
        self.horizontalMargin = horizontalMargin
        self.verticalMargin = verticalMargin
        self.maxContentWidth = maxContentWidth
        self.lineHeightMultiplier = lineHeightMultiplier
        self.paragraphSpacingMultiplier = paragraphSpacingMultiplier
    }
}

// MARK: - Device-Aware Defaults

extension LayoutMetrics {

    /// iPhone metrics: compact margins, no content width constraint.
    public static let iPhone = LayoutMetrics(
        horizontalMargin: 16,
        verticalMargin: 16,
        maxContentWidth: nil,
        lineHeightMultiplier: 1.6,
        paragraphSpacingMultiplier: 0.6
    )

    /// iPad metrics: comfortable margins, content width constrained for readability.
    /// At 17pt body font, ~80 characters ≈ 680pt. We use 700pt to allow some breathing room.
    public static let iPad = LayoutMetrics(
        horizontalMargin: 32,
        verticalMargin: 24,
        maxContentWidth: 700,
        lineHeightMultiplier: 1.6,
        paragraphSpacingMultiplier: 0.6
    )

    /// macOS metrics: comfortable margins, content width constrained.
    public static let mac = LayoutMetrics(
        horizontalMargin: 32,
        verticalMargin: 24,
        maxContentWidth: 700,
        lineHeightMultiplier: 1.6,
        paragraphSpacingMultiplier: 0.6
    )

    /// Returns the appropriate metrics for the current device.
    ///
    /// On iOS, distinguishes between iPhone (compact) and iPad (regular).
    /// On macOS, returns mac metrics.
    public static var current: LayoutMetrics {
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPad
        } else {
            return .iPhone
        }
        #elseif canImport(AppKit)
        return .mac
        #endif
    }

    /// Returns metrics appropriate for a given horizontal size class.
    ///
    /// Compact size class → iPhone metrics (even on iPad in Slide Over).
    /// Regular size class → iPad metrics.
    public static func forSizeClass(_ horizontalSizeClass: SizeClass) -> LayoutMetrics {
        switch horizontalSizeClass {
        case .compact:
            return .iPhone
        case .regular:
            return .iPad
        }
    }

    /// Returns metrics adapted to a specific available width in points per FEAT-057.
    ///
    /// Provides continuous adaptation for iPad Split View resize, Slide Over,
    /// and external display scenarios. Unlike `forSizeClass(_:)`, which jumps
    /// at the compact/regular threshold, this method adapts margins smoothly
    /// based on actual view width.
    ///
    /// Width behavior:
    /// - Below 400pt (Slide Over, ~320pt): tight margins (12pt), no content width constraint
    /// - 400–599pt (narrow Split View): compact margins (16pt), no content width constraint
    /// - 600pt+ (wide Split View, full screen, external display): comfortable margins (32pt),
    ///   700pt max content width for 65–80 character readability per [D-PERF] typography spec
    public static func forAvailableWidth(_ width: CGFloat) -> LayoutMetrics {
        if width < 400 {
            // Slide Over / very narrow: minimize margins to maximize content area.
            // At 320pt with 12pt margins, content area is ~296pt — sufficient for wrapped text.
            return LayoutMetrics(
                horizontalMargin: 12,
                verticalMargin: 12,
                maxContentWidth: nil,
                lineHeightMultiplier: 1.6,
                paragraphSpacingMultiplier: 0.6
            )
        } else if width < 600 {
            return .iPhone
        } else {
            return .iPad
        }
    }
}

/// Size class abstraction for cross-platform layout decisions.
public enum SizeClass: Sendable {
    case compact
    case regular
}
