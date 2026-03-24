import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMCore

/// Verifies WCAG AA contrast ratios for all built-in theme palettes per FEAT-007 AC-3 and FEAT-019 AC-3.
/// WCAG AA requires ≥4.5:1 for normal text and ≥3:1 for large text (≥18pt or ≥14pt bold).
@Suite("Theme WCAG AA Contrast")
struct ThemeContrastTests {

    // MARK: - All Themes parametric tests

    /// All theme light/dark palette pairs to validate.
    private static let allPalettes: [(name: String, light: ThemeColors, dark: ThemeColors)] = [
        ("Default", .defaultLight, .defaultDark),
        ("Sepia", .sepiaLight, .sepiaDark),
        ("Solarized", .solarizedLight, .solarizedDark),
        ("Nord", .nordLight, .nordDark),
        ("Ink", .inkLight, .inkDark),
    ]

    @Test("All light palettes: body text meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allLightBodyContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.light.foreground, palette.light.background)
        #expect(ratio >= 4.5, "\(name) light body text contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All dark palettes: body text meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allDarkBodyContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.dark.foreground, palette.dark.background)
        #expect(ratio >= 4.5, "\(name) dark body text contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All light palettes: heading meets WCAG AA large text (≥3:1)", arguments: allPalettes.map(\.name))
    func allLightHeadingContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.light.heading, palette.light.background)
        #expect(ratio >= 3.0, "\(name) light heading contrast \(ratio):1 is below WCAG AA 3:1")
    }

    @Test("All dark palettes: heading meets WCAG AA large text (≥3:1)", arguments: allPalettes.map(\.name))
    func allDarkHeadingContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.dark.heading, palette.dark.background)
        #expect(ratio >= 3.0, "\(name) dark heading contrast \(ratio):1 is below WCAG AA 3:1")
    }

    @Test("All light palettes: link meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allLightLinkContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.light.link, palette.light.background)
        #expect(ratio >= 4.5, "\(name) light link contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All dark palettes: link meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allDarkLinkContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.dark.link, palette.dark.background)
        #expect(ratio >= 4.5, "\(name) dark link contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All light palettes: code text meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allLightCodeContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.light.codeForeground, palette.light.codeBackground)
        #expect(ratio >= 4.5, "\(name) light code contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All dark palettes: code text meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allDarkCodeContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.dark.codeForeground, palette.dark.codeBackground)
        #expect(ratio >= 4.5, "\(name) dark code contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All light palettes: blockquote meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allLightBlockquoteContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.light.blockquoteForeground, palette.light.background)
        #expect(ratio >= 4.5, "\(name) light blockquote contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All dark palettes: blockquote meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allDarkBlockquoteContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.dark.blockquoteForeground, palette.dark.background)
        #expect(ratio >= 4.5, "\(name) dark blockquote contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All light palettes: list marker meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allLightListMarkerContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.light.listMarker, palette.light.background)
        #expect(ratio >= 4.5, "\(name) light list marker contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All dark palettes: list marker meets WCAG AA (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allDarkListMarkerContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let ratio = contrastRatio(palette.dark.listMarker, palette.dark.background)
        #expect(ratio >= 4.5, "\(name) dark list marker contrast \(ratio):1 is below WCAG AA 4.5:1")
    }

    @Test("All light palettes: syntax colors meet WCAG AA on code background (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allLightSyntaxContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let colors = palette.light
        let bg = colors.codeBackground
        let cases: [(String, PlatformColor)] = [
            ("keyword", colors.syntaxKeyword),
            ("string", colors.syntaxString),
            ("comment", colors.syntaxComment),
            ("number", colors.syntaxNumber),
            ("type", colors.syntaxType),
            ("function", colors.syntaxFunction),
        ]
        for (label, fg) in cases {
            let ratio = contrastRatio(fg, bg)
            #expect(ratio >= 4.5, "\(name) light syntax.\(label) contrast \(ratio):1 is below WCAG AA 4.5:1")
        }
    }

    @Test("All dark palettes: syntax colors meet WCAG AA on code background (≥4.5:1)", arguments: allPalettes.map(\.name))
    func allDarkSyntaxContrast(name: String) {
        let palette = Self.allPalettes.first { $0.name == name }!
        let colors = palette.dark
        let bg = colors.codeBackground
        let cases: [(String, PlatformColor)] = [
            ("keyword", colors.syntaxKeyword),
            ("string", colors.syntaxString),
            ("comment", colors.syntaxComment),
            ("number", colors.syntaxNumber),
            ("type", colors.syntaxType),
            ("function", colors.syntaxFunction),
        ]
        for (label, fg) in cases {
            let ratio = contrastRatio(fg, bg)
            #expect(ratio >= 4.5, "\(name) dark syntax.\(label) contrast \(ratio):1 is below WCAG AA 4.5:1")
        }
    }

    // MARK: - Theme structure

    @Test("All built-in themes have distinct light and dark palettes")
    func allDistinctPalettes() {
        for theme in Theme.allBuiltIn {
            let bgRatio = contrastRatio(theme.light.background, theme.dark.background)
            #expect(bgRatio > 2.0, "\(theme.name) light and dark backgrounds should differ significantly")
        }
    }

    @Test("Theme.builtIn(id:) returns correct theme or default fallback")
    func themeBuiltInLookup() {
        #expect(Theme.builtIn(id: "sepia").id == "sepia")
        #expect(Theme.builtIn(id: "solarized").id == "solarized")
        #expect(Theme.builtIn(id: "nord").id == "nord")
        #expect(Theme.builtIn(id: "ink").id == "ink")
        #expect(Theme.builtIn(id: "nonexistent").id == "default")
    }

    @Test("allBuiltIn contains exactly 5 themes")
    func allBuiltInCount() {
        #expect(Theme.allBuiltIn.count == 5)
    }

    @Test("Theme.colors(isDark:) returns correct variant")
    func themeVariantSelection() {
        for theme in Theme.allBuiltIn {
            let lightBg = rgbComponents(theme.colors(isDark: false).background)
            let darkBg = rgbComponents(theme.colors(isDark: true).background)
            #expect(lightBg.r > darkBg.r || lightBg.g > darkBg.g || lightBg.b > darkBg.b,
                    "\(theme.name) light background should be brighter than dark")
        }
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
