/// Type scale for all text sizes in the editor per [A-052].
/// Wraps system fonts with UIFontMetrics for Dynamic Type scaling per [D-A11Y-2].
/// Custom font loading deferred to theme customization (FEAT-019).

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Defines the font scale for all editor text per [A-052].
///
/// Each font is wrapped with `UIFontMetrics` (iOS) so Dynamic Type
/// scales editor content automatically. On macOS, fonts use preferred
/// font descriptors that respond to system text size settings.
public struct TypeScale: Sendable {
    public let heading1: PlatformFont
    public let heading2: PlatformFont
    public let heading3: PlatformFont
    public let heading4: PlatformFont
    public let heading5: PlatformFont
    public let heading6: PlatformFont
    public let body: PlatformFont
    public let code: PlatformFont
    public let caption: PlatformFont
    public let ui: PlatformFont

    public init(
        heading1: PlatformFont,
        heading2: PlatformFont,
        heading3: PlatformFont,
        heading4: PlatformFont,
        heading5: PlatformFont,
        heading6: PlatformFont,
        body: PlatformFont,
        code: PlatformFont,
        caption: PlatformFont,
        ui: PlatformFont
    ) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.heading3 = heading3
        self.heading4 = heading4
        self.heading5 = heading5
        self.heading6 = heading6
        self.body = body
        self.code = code
        self.caption = caption
        self.ui = ui
    }

    /// Returns the font for a given heading level (1–6).
    /// Returns body font for out-of-range levels.
    public func headingFont(level: Int) -> PlatformFont {
        switch level {
        case 1: return heading1
        case 2: return heading2
        case 3: return heading3
        case 4: return heading4
        case 5: return heading5
        case 6: return heading6
        default: return body
        }
    }
}

// MARK: - Default Type Scale

extension TypeScale {
    /// Default type scale using system fonts with Dynamic Type support.
    ///
    /// Heading sizes follow a clear visual hierarchy:
    /// H1 (28pt bold) > H2 (24pt bold) > H3 (20pt semibold) >
    /// H4 (17pt semibold) > H5 (15pt medium) > H6 (13pt medium)
    public static let `default`: TypeScale = {
        #if canImport(UIKit)
        return TypeScale(
            heading1: scaledFont(.systemFont(ofSize: 28, weight: .bold), style: .title1),
            heading2: scaledFont(.systemFont(ofSize: 24, weight: .bold), style: .title2),
            heading3: scaledFont(.systemFont(ofSize: 20, weight: .semibold), style: .title3),
            heading4: scaledFont(.systemFont(ofSize: 17, weight: .semibold), style: .headline),
            heading5: scaledFont(.systemFont(ofSize: 15, weight: .medium), style: .subheadline),
            heading6: scaledFont(.systemFont(ofSize: 13, weight: .medium), style: .footnote),
            body: UIFont.preferredFont(forTextStyle: .body),
            code: scaledMonospaceFont(size: 15, style: .body),
            caption: UIFont.preferredFont(forTextStyle: .caption1),
            ui: UIFont.preferredFont(forTextStyle: .footnote)
        )
        #elseif canImport(AppKit)
        return TypeScale(
            heading1: NSFont.systemFont(ofSize: 28, weight: .bold),
            heading2: NSFont.systemFont(ofSize: 24, weight: .bold),
            heading3: NSFont.systemFont(ofSize: 20, weight: .semibold),
            heading4: NSFont.systemFont(ofSize: 17, weight: .semibold),
            heading5: NSFont.systemFont(ofSize: 15, weight: .medium),
            heading6: NSFont.systemFont(ofSize: 13, weight: .medium),
            body: NSFont.preferredFont(forTextStyle: .body),
            code: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            caption: NSFont.preferredFont(forTextStyle: .body), // macOS lacks .caption
            ui: NSFont.preferredFont(forTextStyle: .body)
        )
        #endif
    }()

    #if canImport(UIKit)
    /// Wraps a custom font with UIFontMetrics for Dynamic Type scaling.
    private static func scaledFont(_ font: UIFont, style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    /// Creates a monospace font that scales with Dynamic Type.
    private static func scaledMonospaceFont(size: CGFloat, style: UIFont.TextStyle) -> UIFont {
        let mono = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: mono)
    }
    #endif
}
