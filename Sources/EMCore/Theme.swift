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
    /// Default light theme colors using system semantic colors.
    public static let defaultLight: ThemeColors = ThemeColors(
        background: PlatformColor.systemBackground,
        foreground: PlatformColor.label,
        heading: PlatformColor.label,
        link: PlatformColor.systemBlue,
        codeBackground: PlatformColor.secondarySystemBackground,
        codeForeground: PlatformColor.label,
        blockquoteBorder: PlatformColor.systemGray3,
        blockquoteForeground: PlatformColor.secondaryLabel,
        selection: PlatformColor.systemBlue.withAlphaComponent(0.2),
        thematicBreak: PlatformColor.separator,
        listMarker: PlatformColor.secondaryLabel,
        syntaxKeyword: PlatformColor.systemPurple,
        syntaxString: PlatformColor.systemRed,
        syntaxComment: PlatformColor.systemGray,
        syntaxNumber: PlatformColor.systemOrange,
        syntaxType: PlatformColor.systemTeal,
        syntaxFunction: PlatformColor.systemBlue,
        toolbarBackground: PlatformColor.systemBackground,
        statusBarBackground: PlatformColor.secondarySystemBackground,
        divider: PlatformColor.separator,
        warningIndicator: PlatformColor.systemYellow,
        errorIndicator: PlatformColor.systemRed
    )

    /// Default dark theme colors using system semantic colors.
    public static let defaultDark: ThemeColors = ThemeColors(
        background: PlatformColor.systemBackground,
        foreground: PlatformColor.label,
        heading: PlatformColor.label,
        link: PlatformColor.systemBlue,
        codeBackground: PlatformColor.secondarySystemBackground,
        codeForeground: PlatformColor.label,
        blockquoteBorder: PlatformColor.systemGray3,
        blockquoteForeground: PlatformColor.secondaryLabel,
        selection: PlatformColor.systemBlue.withAlphaComponent(0.3),
        thematicBreak: PlatformColor.separator,
        listMarker: PlatformColor.secondaryLabel,
        syntaxKeyword: PlatformColor.systemPurple,
        syntaxString: PlatformColor.systemRed,
        syntaxComment: PlatformColor.systemGray,
        syntaxNumber: PlatformColor.systemOrange,
        syntaxType: PlatformColor.systemTeal,
        syntaxFunction: PlatformColor.systemBlue,
        toolbarBackground: PlatformColor.systemBackground,
        statusBarBackground: PlatformColor.secondarySystemBackground,
        divider: PlatformColor.separator,
        warningIndicator: PlatformColor.systemYellow,
        errorIndicator: PlatformColor.systemRed
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
