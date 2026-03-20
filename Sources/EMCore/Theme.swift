/// Theme and color palette types for the editor per [A-052].
/// Theme types live in EMCore. Theme application lives in EMEditor and EMApp.

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Color palette for a theme variant (light or dark) per [A-052].
public struct ThemeColors: Sendable {
    // Editor
    public let background: PlatformColor
    public let foreground: PlatformColor
    public let heading: PlatformColor
    public let link: PlatformColor
    public let codeBackground: PlatformColor
    public let codeForeground: PlatformColor
    public let blockquoteBorder: PlatformColor
    public let blockquoteForeground: PlatformColor
    public let selection: PlatformColor
    public let thematicBreak: PlatformColor
    public let listMarker: PlatformColor

    // Syntax highlighting (code blocks — FEAT-006, stubbed here)
    public let syntaxKeyword: PlatformColor
    public let syntaxString: PlatformColor
    public let syntaxComment: PlatformColor
    public let syntaxNumber: PlatformColor
    public let syntaxType: PlatformColor
    public let syntaxFunction: PlatformColor

    // UI chrome
    public let toolbarBackground: PlatformColor
    public let statusBarBackground: PlatformColor
    public let divider: PlatformColor

    // Doctor / diagnostics
    public let warningIndicator: PlatformColor
    public let errorIndicator: PlatformColor

    public init(
        background: PlatformColor,
        foreground: PlatformColor,
        heading: PlatformColor,
        link: PlatformColor,
        codeBackground: PlatformColor,
        codeForeground: PlatformColor,
        blockquoteBorder: PlatformColor,
        blockquoteForeground: PlatformColor,
        selection: PlatformColor,
        thematicBreak: PlatformColor,
        listMarker: PlatformColor,
        syntaxKeyword: PlatformColor,
        syntaxString: PlatformColor,
        syntaxComment: PlatformColor,
        syntaxNumber: PlatformColor,
        syntaxType: PlatformColor,
        syntaxFunction: PlatformColor,
        toolbarBackground: PlatformColor,
        statusBarBackground: PlatformColor,
        divider: PlatformColor,
        warningIndicator: PlatformColor,
        errorIndicator: PlatformColor
    ) {
        self.background = background
        self.foreground = foreground
        self.heading = heading
        self.link = link
        self.codeBackground = codeBackground
        self.codeForeground = codeForeground
        self.blockquoteBorder = blockquoteBorder
        self.blockquoteForeground = blockquoteForeground
        self.selection = selection
        self.thematicBreak = thematicBreak
        self.listMarker = listMarker
        self.syntaxKeyword = syntaxKeyword
        self.syntaxString = syntaxString
        self.syntaxComment = syntaxComment
        self.syntaxNumber = syntaxNumber
        self.syntaxType = syntaxType
        self.syntaxFunction = syntaxFunction
        self.toolbarBackground = toolbarBackground
        self.statusBarBackground = statusBarBackground
        self.divider = divider
        self.warningIndicator = warningIndicator
        self.errorIndicator = errorIndicator
    }
}

/// A complete theme with light and dark variants per [A-052].
public struct Theme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let light: ThemeColors
    public let dark: ThemeColors

    public init(id: String, name: String, light: ThemeColors, dark: ThemeColors) {
        self.id = id
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// Returns the appropriate color set for the current interface style.
    #if canImport(UIKit)
    public func colors(for traitCollection: UITraitCollection) -> ThemeColors {
        traitCollection.userInterfaceStyle == .dark ? dark : light
    }
    #endif

    /// Returns colors for a specific style.
    public func colors(isDark: Bool) -> ThemeColors {
        isDark ? dark : light
    }
}

// MARK: - Default Theme

extension Theme {
    /// The default theme using semantic system colors.
    public static let `default`: Theme = Theme(
        id: "default",
        name: "Default",
        light: .defaultLight,
        dark: .defaultDark
    )
}

extension ThemeColors {
    /// Intentionally designed light palette per FEAT-007.
    /// Warm, high-contrast colors optimized for daylight reading.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let defaultLight: ThemeColors = ThemeColors(
        // Editor — white background with near-black text (17.4:1 contrast)
        background: PlatformColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        foreground: PlatformColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0),
        heading: PlatformColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0),
        link: PlatformColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0),
        // Code — light warm gray background, near-black text (15.3:1)
        codeBackground: PlatformColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.78, green: 0.78, blue: 0.8, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.388, green: 0.388, blue: 0.4, alpha: 1.0),
        selection: PlatformColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 0.2),
        thematicBreak: PlatformColor(red: 0.78, green: 0.78, blue: 0.8, alpha: 1.0),
        listMarker: PlatformColor(red: 0.388, green: 0.388, blue: 0.4, alpha: 1.0),
        // Syntax — Xcode-inspired light palette, all ≥4.5:1 on code background
        syntaxKeyword: PlatformColor(red: 0.607, green: 0.137, blue: 0.576, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.769, green: 0.102, blue: 0.086, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.388, green: 0.388, blue: 0.4, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.11, green: 0.0, blue: 0.81, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.043, green: 0.31, blue: 0.475, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.196, green: 0.427, blue: 0.455, alpha: 1.0),
        // Chrome — clean, minimal separation
        toolbarBackground: PlatformColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0),
        divider: PlatformColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1.0),
        // Diagnostics — vivid indicators
        warningIndicator: PlatformColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0),
        errorIndicator: PlatformColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
    )

    /// Intentionally designed dark palette per FEAT-007.
    /// Muted, eye-friendly colors optimized for low-light environments.
    /// Not simply inverted — each color is chosen for dark background legibility.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let defaultDark: ThemeColors = ThemeColors(
        // Editor — dark gray (not pure black) with warm light text (13.2:1 contrast)
        background: PlatformColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0),
        foreground: PlatformColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1.0),
        heading: PlatformColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1.0),
        link: PlatformColor(red: 0.345, green: 0.651, blue: 1.0, alpha: 1.0),
        // Code — slightly lighter dark, light text (11.5:1)
        codeBackground: PlatformColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.282, green: 0.282, blue: 0.29, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.682, green: 0.682, blue: 0.698, alpha: 1.0),
        selection: PlatformColor(red: 0.345, green: 0.651, blue: 1.0, alpha: 0.3),
        thematicBreak: PlatformColor(red: 0.282, green: 0.282, blue: 0.29, alpha: 1.0),
        listMarker: PlatformColor(red: 0.682, green: 0.682, blue: 0.698, alpha: 1.0),
        // Syntax — softer, warmer tones to reduce eye strain in dark mode
        syntaxKeyword: PlatformColor(red: 0.8, green: 0.42, blue: 0.98, alpha: 1.0),
        syntaxString: PlatformColor(red: 1.0, green: 0.412, blue: 0.38, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.596, green: 0.596, blue: 0.612, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.392, green: 0.824, blue: 1.0, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.353, green: 0.784, blue: 0.98, alpha: 1.0),
        // Chrome — subtle separation without harsh contrast
        toolbarBackground: PlatformColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1.0),
        divider: PlatformColor(red: 0.22, green: 0.22, blue: 0.227, alpha: 1.0),
        // Diagnostics — slightly brighter for dark background visibility
        warningIndicator: PlatformColor(red: 1.0, green: 0.839, blue: 0.039, alpha: 1.0),
        errorIndicator: PlatformColor(red: 1.0, green: 0.271, blue: 0.227, alpha: 1.0)
    )
}

// MARK: - Platform compatibility

#if canImport(AppKit) && !canImport(UIKit)
extension NSColor {
    /// UIKit-compatible name for window background.
    static var systemBackground: NSColor { .windowBackgroundColor }
    /// UIKit-compatible name for control background.
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    /// UIKit-compatible name for system gray 3.
    static var systemGray3: NSColor { .tertiaryLabelColor }
}
#endif
