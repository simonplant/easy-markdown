import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMCore

/// Verifies WCAG AA contrast ratios for both theme palettes per FEAT-007 AC-3.
/// WCAG AA requires ≥4.5:1 for normal text and ≥3:1 for large text (≥18pt or ≥14pt bold).
@Suite("Theme WCAG AA Contrast")
struct ThemeContrastTests {

    // MARK: - Light palette

    @Test("Light: body text meets WCAG AA (≥4.5:1)")
    func lightBodyContrast() {
        let ratio = contrastRatio(.defaultLight.foreground, .defaultLight.background)
        #expect(ratio >= 4.5, "Body text contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Light: heading text meets WCAG AA (≥3:1 for large text)")
    func lightHeadingContrast() {
        let ratio = contrastRatio(.defaultLight.heading, .defaultLight.background)
        #expect(ratio >= 3.0, "Heading contrast \(ratio):1 is below WCAG AA 3:1 for large text")
    }

    @Test("Light: link text meets WCAG AA (≥4.5:1)")
    func lightLinkContrast() {
        let ratio = contrastRatio(.defaultLight.link, .defaultLight.background)
        #expect(ratio >= 4.5, "Link contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Light: code text meets WCAG AA on code background (≥4.5:1)")
    func lightCodeContrast() {
        let ratio = contrastRatio(.defaultLight.codeForeground, .defaultLight.codeBackground)
        #expect(ratio >= 4.5, "Code contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Light: blockquote text meets WCAG AA (≥4.5:1)")
    func lightBlockquoteContrast() {
        let ratio = contrastRatio(.defaultLight.blockquoteForeground, .defaultLight.background)
        #expect(ratio >= 4.5, "Blockquote contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Light: list marker meets WCAG AA (≥4.5:1)")
    func lightListMarkerContrast() {
        let ratio = contrastRatio(.defaultLight.listMarker, .defaultLight.background)
        #expect(ratio >= 4.5, "List marker contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Light: syntax colors meet WCAG AA on code background (≥4.5:1)")
    func lightSyntaxContrast() {
        let colors = ThemeColors.defaultLight
        let bg = colors.codeBackground
        let cases: [(String, PlatformColor)] = [
            ("keyword", colors.syntaxKeyword),
            ("string", colors.syntaxString),
            ("comment", colors.syntaxComment),
            ("number", colors.syntaxNumber),
            ("type", colors.syntaxType),
            ("function", colors.syntaxFunction),
        ]
        for (name, fg) in cases {
            let ratio = contrastRatio(fg, bg)
            #expect(ratio >= 4.5, "Light syntax.\(name) contrast \(ratio):1 is below WCAG AA 4.5:1")
        }
    }

    // MARK: - Dark palette

    @Test("Dark: body text meets WCAG AA (≥4.5:1)")
    func darkBodyContrast() {
        let ratio = contrastRatio(.defaultDark.foreground, .defaultDark.background)
        #expect(ratio >= 4.5, "Body text contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Dark: heading text meets WCAG AA (≥3:1 for large text)")
    func darkHeadingContrast() {
        let ratio = contrastRatio(.defaultDark.heading, .defaultDark.background)
        #expect(ratio >= 3.0, "Heading contrast \(ratio):1 is below WCAG AA 3:1 for large text")
    }

    @Test("Dark: link text meets WCAG AA (≥4.5:1)")
    func darkLinkContrast() {
        let ratio = contrastRatio(.defaultDark.link, .defaultDark.background)
        #expect(ratio >= 4.5, "Link contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Dark: code text meets WCAG AA on code background (≥4.5:1)")
    func darkCodeContrast() {
        let ratio = contrastRatio(.defaultDark.codeForeground, .defaultDark.codeBackground)
        #expect(ratio >= 4.5, "Code contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Dark: blockquote text meets WCAG AA (≥4.5:1)")
    func darkBlockquoteContrast() {
        let ratio = contrastRatio(.defaultDark.blockquoteForeground, .defaultDark.background)
        #expect(ratio >= 4.5, "Blockquote contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Dark: list marker meets WCAG AA (≥4.5:1)")
    func darkListMarkerContrast() {
        let ratio = contrastRatio(.defaultDark.listMarker, .defaultDark.background)
        #expect(ratio >= 4.5, "List marker contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("Dark: syntax colors meet WCAG AA on code background (≥4.5:1)")
    func darkSyntaxContrast() {
        let colors = ThemeColors.defaultDark
        let bg = colors.codeBackground
        let cases: [(String, PlatformColor)] = [
            ("keyword", colors.syntaxKeyword),
            ("string", colors.syntaxString),
            ("comment", colors.syntaxComment),
            ("number", colors.syntaxNumber),
            ("type", colors.syntaxType),
            ("function", colors.syntaxFunction),
        ]
        for (name, fg) in cases {
            let ratio = contrastRatio(fg, bg)
            #expect(ratio >= 4.5, "Dark syntax.\(name) contrast \(ratio):1 is below WCAG AA 4.5:1")
        }
    }

    // MARK: - Theme structure

    @Test("Default theme has distinct light and dark palettes")
    func distinctPalettes() {
        let light = ThemeColors.defaultLight
        let dark = ThemeColors.defaultDark
        // Backgrounds must be visually different
        let bgRatio = contrastRatio(light.background, dark.background)
        #expect(bgRatio > 2.0, "Light and dark backgrounds should differ significantly")
    }

    @Test("Theme.colors(isDark:) returns correct variant")
    func themeVariantSelection() {
        let theme = Theme.default
        let lightBg = rgbComponents(theme.colors(isDark: false).background)
        let darkBg = rgbComponents(theme.colors(isDark: true).background)
        // Light background should be brighter
        #expect(lightBg.r > darkBg.r, "Light background should have higher red component")
    }

    // MARK: - WCAG Contrast Ratio Calculation

    /// Computes the WCAG 2.1 contrast ratio between two colors.
    /// Returns a value ≥1.0 where 21:1 is the maximum (black on white).
    private func contrastRatio(_ color1: PlatformColor, _ color2: PlatformColor) -> Double {
        let l1 = relativeLuminance(of: color1)
        let l2 = relativeLuminance(of: color2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG 2.1 relative luminance per https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    private func relativeLuminance(of color: PlatformColor) -> Double {
        let c = rgbComponents(color)
        let r = linearize(c.r)
        let g = linearize(c.g)
        let b = linearize(c.b)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// sRGB → linear conversion per WCAG 2.1 spec.
    private func linearize(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private func rgbComponents(_ color: PlatformColor) -> (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let converted = color.usingColorSpace(.sRGB) ?? color
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (Double(r), Double(g), Double(b))
    }
}
