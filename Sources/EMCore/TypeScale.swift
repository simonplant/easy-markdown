/// Type scale for all text sizes in the editor per [A-052].
///
/// Uses custom bundled typefaces:
/// - **Source Serif 4** — body text and headings (transitional serif, optimized for reading)
/// - **Source Serif 4 Display** — large headings (display optical size for H1/H2)
/// - **JetBrains Mono** — code blocks and inline code
///
/// All fonts are wrapped with `UIFontMetrics` (iOS) for Dynamic Type scaling per [D-A11Y-2].
/// Font cascading handles CJK, Arabic, and Devanagari scripts automatically.
///
/// Fonts must be registered via `FontRegistration.registerFonts()` before creating
/// a `TypeScale` instance.

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Defines the font scale for all editor text per [A-052].
///
/// Each font is wrapped with `UIFontMetrics` (iOS) so Dynamic Type
/// scales editor content automatically. On macOS, fonts use the registered
/// custom typefaces at fixed sizes that respond to system text size settings.
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

    /// Returns the body font's point size for use in spacing calculations.
    public var bodyFontSize: CGFloat {
        body.pointSize
    }
}

// MARK: - Default Type Scale

extension TypeScale {
    /// Default type scale using custom bundled typefaces with Dynamic Type support.
    ///
    /// Typeface choices:
    /// - **H1–H2**: Source Serif 4 Display Bold — display optical size for large text
    /// - **H3**: Source Serif 4 Display Semibold — display optical size, lighter weight
    /// - **H4–H6**: Source Serif 4 Semibold/Regular — text optical size for smaller headings
    /// - **Body**: Source Serif 4 Regular — optimized for long-form reading
    /// - **Code**: JetBrains Mono Regular — clear monospace with coding ligatures
    /// - **Caption/UI**: System font — for chrome elements that should match the OS
    ///
    /// Heading sizes follow a clear visual hierarchy:
    /// H1 (28pt bold) > H2 (24pt bold) > H3 (20pt semibold) >
    /// H4 (17pt semibold) > H5 (15pt medium) > H6 (13pt medium)
    public static let `default`: TypeScale = {
        // Ensure custom fonts are registered before first access.
        // Idempotent — safe to call even if AppShell already registered.
        FontRegistration.registerFonts()

        #if canImport(UIKit)
        return TypeScale(
            heading1: scaledCustomFont(FontRegistration.FontName.serifDisplayBold, size: 28, style: .title1),
            heading2: scaledCustomFont(FontRegistration.FontName.serifDisplayBold, size: 24, style: .title2),
            heading3: scaledCustomFont(FontRegistration.FontName.serifDisplaySemibold, size: 20, style: .title3),
            heading4: scaledCustomFont(FontRegistration.FontName.serifSemibold, size: 17, style: .headline),
            heading5: scaledCustomFont(FontRegistration.FontName.serifSemibold, size: 15, style: .subheadline),
            heading6: scaledCustomFont(FontRegistration.FontName.serifRegular, size: 13, style: .footnote),
            body: scaledCustomFont(FontRegistration.FontName.serifRegular, size: 17, style: .body),
            code: scaledCustomFont(FontRegistration.FontName.monoRegular, size: 15, style: .body),
            caption: UIFont.preferredFont(forTextStyle: .caption1),
            ui: UIFont.preferredFont(forTextStyle: .footnote)
        )
        #elseif canImport(AppKit)
        return TypeScale(
            heading1: FontRegistration.font(named: FontRegistration.FontName.serifDisplayBold, size: 28),
            heading2: FontRegistration.font(named: FontRegistration.FontName.serifDisplayBold, size: 24),
            heading3: FontRegistration.font(named: FontRegistration.FontName.serifDisplaySemibold, size: 20),
            heading4: FontRegistration.font(named: FontRegistration.FontName.serifSemibold, size: 17),
            heading5: FontRegistration.font(named: FontRegistration.FontName.serifSemibold, size: 15),
            heading6: FontRegistration.font(named: FontRegistration.FontName.serifRegular, size: 13),
            body: FontRegistration.font(named: FontRegistration.FontName.serifRegular, size: 17),
            code: FontRegistration.font(named: FontRegistration.FontName.monoRegular, size: 15),
            caption: NSFont.preferredFont(forTextStyle: .body), // macOS lacks .caption
            ui: NSFont.preferredFont(forTextStyle: .body)
        )
        #endif
    }()

    #if canImport(UIKit)
    /// Creates a custom font wrapped with UIFontMetrics for Dynamic Type scaling.
    ///
    /// Falls back to system font if the custom font is not available.
    private static func scaledCustomFont(_ name: String, size: CGFloat, style: UIFont.TextStyle) -> UIFont {
        let font = FontRegistration.font(named: name, size: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
    #endif
}
