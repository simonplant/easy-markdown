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

// MARK: - Built-in Themes per FEAT-019

extension Theme {
    /// The default theme using semantic system colors.
    public static let `default`: Theme = Theme(
        id: "default",
        name: "Default",
        light: .defaultLight,
        dark: .defaultDark
    )

    /// Warm sepia theme inspired by aged paper — easy on the eyes for long reading sessions.
    public static let sepia: Theme = Theme(
        id: "sepia",
        name: "Sepia",
        light: .sepiaLight,
        dark: .sepiaDark
    )

    /// Solarized color palette by Ethan Schoonover — carefully balanced for readability.
    public static let solarized: Theme = Theme(
        id: "solarized",
        name: "Solarized",
        light: .solarizedLight,
        dark: .solarizedDark
    )

    /// Nord theme — Arctic, north-bluish color palette for comfortable reading.
    public static let nord: Theme = Theme(
        id: "nord",
        name: "Nord",
        light: .nordLight,
        dark: .nordDark
    )

    /// Ink theme — high-contrast monochrome for distraction-free writing.
    public static let ink: Theme = Theme(
        id: "ink",
        name: "Ink",
        light: .inkLight,
        dark: .inkDark
    )

    /// All built-in themes in display order.
    public static let allBuiltIn: [Theme] = [.default, .sepia, .solarized, .nord, .ink]

    /// Looks up a built-in theme by ID. Returns `.default` if not found.
    public static func builtIn(id: String) -> Theme {
        allBuiltIn.first { $0.id == id } ?? .default
    }
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

// MARK: - Sepia Theme

extension ThemeColors {
    /// Sepia light palette — warm cream background with brown-tinted text.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let sepiaLight: ThemeColors = ThemeColors(
        // Editor — warm cream background, dark brown text (12.5:1)
        background: PlatformColor(red: 0.976, green: 0.949, blue: 0.906, alpha: 1.0),
        foreground: PlatformColor(red: 0.180, green: 0.141, blue: 0.102, alpha: 1.0),
        heading: PlatformColor(red: 0.180, green: 0.141, blue: 0.102, alpha: 1.0),
        link: PlatformColor(red: 0.494, green: 0.220, blue: 0.082, alpha: 1.0),
        codeBackground: PlatformColor(red: 0.949, green: 0.918, blue: 0.871, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.180, green: 0.141, blue: 0.102, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.784, green: 0.737, blue: 0.667, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.380, green: 0.341, blue: 0.290, alpha: 1.0),
        selection: PlatformColor(red: 0.494, green: 0.220, blue: 0.082, alpha: 0.2),
        thematicBreak: PlatformColor(red: 0.784, green: 0.737, blue: 0.667, alpha: 1.0),
        listMarker: PlatformColor(red: 0.380, green: 0.341, blue: 0.290, alpha: 1.0),
        syntaxKeyword: PlatformColor(red: 0.584, green: 0.157, blue: 0.306, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.494, green: 0.220, blue: 0.082, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.380, green: 0.345, blue: 0.298, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.400, green: 0.200, blue: 0.600, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.180, green: 0.380, blue: 0.420, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.310, green: 0.400, blue: 0.220, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.976, green: 0.949, blue: 0.906, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.949, green: 0.918, blue: 0.871, alpha: 1.0),
        divider: PlatformColor(red: 0.843, green: 0.808, blue: 0.749, alpha: 1.0),
        warningIndicator: PlatformColor(red: 0.886, green: 0.533, blue: 0.082, alpha: 1.0),
        errorIndicator: PlatformColor(red: 0.835, green: 0.200, blue: 0.180, alpha: 1.0)
    )

    /// Sepia dark palette — warm dark brown background with warm light text.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let sepiaDark: ThemeColors = ThemeColors(
        background: PlatformColor(red: 0.157, green: 0.133, blue: 0.110, alpha: 1.0),
        foreground: PlatformColor(red: 0.890, green: 0.855, blue: 0.800, alpha: 1.0),
        heading: PlatformColor(red: 0.933, green: 0.898, blue: 0.843, alpha: 1.0),
        link: PlatformColor(red: 0.839, green: 0.561, blue: 0.337, alpha: 1.0),
        codeBackground: PlatformColor(red: 0.212, green: 0.184, blue: 0.157, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.890, green: 0.855, blue: 0.800, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.329, green: 0.298, blue: 0.259, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.698, green: 0.667, blue: 0.612, alpha: 1.0),
        selection: PlatformColor(red: 0.839, green: 0.561, blue: 0.337, alpha: 0.3),
        thematicBreak: PlatformColor(red: 0.329, green: 0.298, blue: 0.259, alpha: 1.0),
        listMarker: PlatformColor(red: 0.698, green: 0.667, blue: 0.612, alpha: 1.0),
        syntaxKeyword: PlatformColor(red: 0.878, green: 0.478, blue: 0.576, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.839, green: 0.561, blue: 0.337, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.667, green: 0.631, blue: 0.576, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.749, green: 0.541, blue: 0.878, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.490, green: 0.757, blue: 0.808, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.639, green: 0.776, blue: 0.478, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.157, green: 0.133, blue: 0.110, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.212, green: 0.184, blue: 0.157, alpha: 1.0),
        divider: PlatformColor(red: 0.267, green: 0.239, blue: 0.208, alpha: 1.0),
        warningIndicator: PlatformColor(red: 1.0, green: 0.749, blue: 0.227, alpha: 1.0),
        errorIndicator: PlatformColor(red: 1.0, green: 0.349, blue: 0.298, alpha: 1.0)
    )
}

// MARK: - Solarized Theme

extension ThemeColors {
    /// Solarized-inspired light palette — warm hues with WCAG AA contrast.
    /// Colors adjusted from Ethan Schoonover's palette to meet ≥4.5:1 text contrast.
    public static let solarizedLight: ThemeColors = ThemeColors(
        // Base3 background (#FDF6E3), darkened text for AA compliance
        background: PlatformColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1.0),
        foreground: PlatformColor(red: 0.200, green: 0.260, blue: 0.290, alpha: 1.0),
        heading: PlatformColor(red: 0.150, green: 0.200, blue: 0.260, alpha: 1.0),
        link: PlatformColor(red: 0.050, green: 0.350, blue: 0.600, alpha: 1.0),
        // Base2 code background (#EEE8D5)
        codeBackground: PlatformColor(red: 0.933, green: 0.910, blue: 0.835, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.200, green: 0.260, blue: 0.290, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.776, green: 0.761, blue: 0.694, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.260, green: 0.330, blue: 0.360, alpha: 1.0),
        selection: PlatformColor(red: 0.050, green: 0.350, blue: 0.600, alpha: 0.2),
        thematicBreak: PlatformColor(red: 0.776, green: 0.761, blue: 0.694, alpha: 1.0),
        listMarker: PlatformColor(red: 0.260, green: 0.330, blue: 0.360, alpha: 1.0),
        // Solarized accent colors — darkened for AA on code background
        syntaxKeyword: PlatformColor(red: 0.350, green: 0.420, blue: 0.000, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.100, green: 0.420, blue: 0.400, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.345, green: 0.388, blue: 0.408, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.530, green: 0.370, blue: 0.000, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.050, green: 0.350, blue: 0.600, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.280, green: 0.290, blue: 0.600, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.933, green: 0.910, blue: 0.835, alpha: 1.0),
        divider: PlatformColor(red: 0.843, green: 0.827, blue: 0.757, alpha: 1.0),
        warningIndicator: PlatformColor(red: 0.600, green: 0.420, blue: 0.000, alpha: 1.0),
        errorIndicator: PlatformColor(red: 0.750, green: 0.150, blue: 0.140, alpha: 1.0)
    )

    /// Solarized-inspired dark palette — cool hues with WCAG AA contrast.
    /// Colors adjusted from Ethan Schoonover's palette to meet ≥4.5:1 text contrast.
    public static let solarizedDark: ThemeColors = ThemeColors(
        // Base03 background (#002B36), lightened text for AA compliance
        background: PlatformColor(red: 0.000, green: 0.169, blue: 0.212, alpha: 1.0),
        foreground: PlatformColor(red: 0.663, green: 0.729, blue: 0.737, alpha: 1.0),
        heading: PlatformColor(red: 0.733, green: 0.784, blue: 0.784, alpha: 1.0),
        link: PlatformColor(red: 0.345, green: 0.667, blue: 0.922, alpha: 1.0),
        // Base02 code background (#073642)
        codeBackground: PlatformColor(red: 0.027, green: 0.212, blue: 0.259, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.663, green: 0.729, blue: 0.737, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.098, green: 0.298, blue: 0.345, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.576, green: 0.643, blue: 0.655, alpha: 1.0),
        selection: PlatformColor(red: 0.345, green: 0.667, blue: 0.922, alpha: 0.3),
        thematicBreak: PlatformColor(red: 0.098, green: 0.298, blue: 0.345, alpha: 1.0),
        listMarker: PlatformColor(red: 0.663, green: 0.729, blue: 0.737, alpha: 1.0),
        // Solarized accent colors — lightened for AA on dark code background
        syntaxKeyword: PlatformColor(red: 0.655, green: 0.733, blue: 0.133, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.310, green: 0.761, blue: 0.725, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.565, green: 0.631, blue: 0.647, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.835, green: 0.667, blue: 0.173, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.345, green: 0.667, blue: 0.922, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.588, green: 0.604, blue: 0.910, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.000, green: 0.169, blue: 0.212, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.027, green: 0.212, blue: 0.259, alpha: 1.0),
        divider: PlatformColor(red: 0.059, green: 0.255, blue: 0.302, alpha: 1.0),
        warningIndicator: PlatformColor(red: 0.835, green: 0.667, blue: 0.173, alpha: 1.0),
        errorIndicator: PlatformColor(red: 0.863, green: 0.282, blue: 0.271, alpha: 1.0)
    )
}

// MARK: - Nord Theme

extension ThemeColors {
    /// Nord light (Snow Storm) palette — clean, arctic-inspired light theme.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let nordLight: ThemeColors = ThemeColors(
        // Snow Storm background (#ECEFF4), Polar Night text (#2E3440) — 12.6:1
        background: PlatformColor(red: 0.925, green: 0.937, blue: 0.957, alpha: 1.0),
        foreground: PlatformColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0),
        heading: PlatformColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0),
        link: PlatformColor(red: 0.180, green: 0.380, blue: 0.580, alpha: 1.0),
        codeBackground: PlatformColor(red: 0.878, green: 0.894, blue: 0.918, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.710, green: 0.737, blue: 0.776, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.298, green: 0.337, blue: 0.416, alpha: 1.0),
        selection: PlatformColor(red: 0.180, green: 0.380, blue: 0.580, alpha: 0.2),
        thematicBreak: PlatformColor(red: 0.710, green: 0.737, blue: 0.776, alpha: 1.0),
        listMarker: PlatformColor(red: 0.298, green: 0.337, blue: 0.416, alpha: 1.0),
        // Syntax — darkened for AA on Snow Storm code background
        syntaxKeyword: PlatformColor(red: 0.475, green: 0.180, blue: 0.400, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.345, green: 0.400, blue: 0.050, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.345, green: 0.380, blue: 0.435, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.530, green: 0.310, blue: 0.150, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.180, green: 0.380, blue: 0.580, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.380, green: 0.220, blue: 0.480, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.925, green: 0.937, blue: 0.957, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.878, green: 0.894, blue: 0.918, alpha: 1.0),
        divider: PlatformColor(red: 0.788, green: 0.808, blue: 0.839, alpha: 1.0),
        warningIndicator: PlatformColor(red: 0.922, green: 0.796, blue: 0.545, alpha: 1.0),
        errorIndicator: PlatformColor(red: 0.749, green: 0.380, blue: 0.416, alpha: 1.0)
    )

    /// Nord dark (Polar Night) palette — deep arctic blue-gray.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let nordDark: ThemeColors = ThemeColors(
        // Polar Night background (#2E3440), Snow Storm text (#D8DEE9) — 9.3:1
        background: PlatformColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0),
        foreground: PlatformColor(red: 0.847, green: 0.871, blue: 0.914, alpha: 1.0),
        heading: PlatformColor(red: 0.925, green: 0.937, blue: 0.957, alpha: 1.0),
        link: PlatformColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 1.0),
        codeBackground: PlatformColor(red: 0.231, green: 0.259, blue: 0.322, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.847, green: 0.871, blue: 0.914, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.298, green: 0.337, blue: 0.416, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.678, green: 0.710, blue: 0.761, alpha: 1.0),
        selection: PlatformColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 0.3),
        thematicBreak: PlatformColor(red: 0.298, green: 0.337, blue: 0.416, alpha: 1.0),
        listMarker: PlatformColor(red: 0.678, green: 0.710, blue: 0.761, alpha: 1.0),
        // Syntax — lightened for AA on Polar Night code background
        syntaxKeyword: PlatformColor(red: 0.812, green: 0.671, blue: 0.773, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.639, green: 0.745, blue: 0.549, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.655, green: 0.686, blue: 0.757, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.886, green: 0.710, blue: 0.624, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.812, green: 0.671, blue: 0.773, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.231, green: 0.259, blue: 0.322, alpha: 1.0),
        divider: PlatformColor(red: 0.263, green: 0.298, blue: 0.369, alpha: 1.0),
        warningIndicator: PlatformColor(red: 0.922, green: 0.796, blue: 0.545, alpha: 1.0),
        errorIndicator: PlatformColor(red: 0.749, green: 0.380, blue: 0.416, alpha: 1.0)
    )
}

// MARK: - Ink Theme

extension ThemeColors {
    /// Ink light palette — high-contrast black-on-white for distraction-free writing.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let inkLight: ThemeColors = ThemeColors(
        // Pure white background, near-black text (21:1)
        background: PlatformColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        foreground: PlatformColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0),
        heading: PlatformColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        link: PlatformColor(red: 0.0, green: 0.333, blue: 0.667, alpha: 1.0),
        codeBackground: PlatformColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0),
        selection: PlatformColor(red: 0.0, green: 0.333, blue: 0.667, alpha: 0.15),
        thematicBreak: PlatformColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0),
        listMarker: PlatformColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0),
        syntaxKeyword: PlatformColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.380, green: 0.380, blue: 0.380, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.200, green: 0.200, blue: 0.200, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1.0),
        divider: PlatformColor(red: 0.800, green: 0.800, blue: 0.800, alpha: 1.0),
        warningIndicator: PlatformColor(red: 0.867, green: 0.533, blue: 0.0, alpha: 1.0),
        errorIndicator: PlatformColor(red: 0.800, green: 0.133, blue: 0.133, alpha: 1.0)
    )

    /// Ink dark palette — high-contrast light-on-dark for distraction-free writing.
    /// All text colors meet WCAG AA contrast ratios against their background.
    public static let inkDark: ThemeColors = ThemeColors(
        background: PlatformColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0),
        foreground: PlatformColor(red: 0.910, green: 0.910, blue: 0.910, alpha: 1.0),
        heading: PlatformColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        link: PlatformColor(red: 0.467, green: 0.667, blue: 0.933, alpha: 1.0),
        codeBackground: PlatformColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1.0),
        codeForeground: PlatformColor(red: 0.910, green: 0.910, blue: 0.910, alpha: 1.0),
        blockquoteBorder: PlatformColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1.0),
        blockquoteForeground: PlatformColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0),
        selection: PlatformColor(red: 0.467, green: 0.667, blue: 0.933, alpha: 0.25),
        thematicBreak: PlatformColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1.0),
        listMarker: PlatformColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0),
        syntaxKeyword: PlatformColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        syntaxString: PlatformColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0),
        syntaxComment: PlatformColor(red: 0.545, green: 0.545, blue: 0.545, alpha: 1.0),
        syntaxNumber: PlatformColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0),
        syntaxType: PlatformColor(red: 0.800, green: 0.800, blue: 0.800, alpha: 1.0),
        syntaxFunction: PlatformColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0),
        toolbarBackground: PlatformColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0),
        statusBarBackground: PlatformColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1.0),
        divider: PlatformColor(red: 0.200, green: 0.200, blue: 0.200, alpha: 1.0),
        warningIndicator: PlatformColor(red: 1.0, green: 0.800, blue: 0.267, alpha: 1.0),
        errorIndicator: PlatformColor(red: 1.0, green: 0.333, blue: 0.333, alpha: 1.0)
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
