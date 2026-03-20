import Foundation
import Observation
import EMCore

/// App-wide settings persisted in UserDefaults per [A-011].
/// Observable for SwiftUI binding per [A-010].
/// Opinionated defaults — settings exist to turn things OFF, not to configure complexity.
@MainActor
@Observable
public final class SettingsManager {
    private let defaults: UserDefaults

    // MARK: - Appearance

    /// User's preferred color scheme override. Nil means follow system.
    public var preferredColorScheme: ColorSchemePreference {
        didSet { defaults.set(preferredColorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    /// Selected font name for the editor body text.
    public var fontName: String {
        didSet { defaults.set(fontName, forKey: Keys.fontName) }
    }

    /// Editor body font size in points (before Dynamic Type scaling).
    public var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    // MARK: - Editor

    /// Whether spell checking is enabled.
    public var isSpellCheckEnabled: Bool {
        didSet { defaults.set(isSpellCheckEnabled, forKey: Keys.spellCheck) }
    }

    /// Master auto-format toggle.
    public var isAutoFormatEnabled: Bool {
        didSet { defaults.set(isAutoFormatEnabled, forKey: Keys.autoFormat) }
    }

    /// Auto-continue lists on Enter.
    public var isAutoFormatListContinuation: Bool {
        didSet { defaults.set(isAutoFormatListContinuation, forKey: Keys.autoFormatListContinuation) }
    }

    /// Auto-renumber ordered lists.
    public var isAutoFormatListRenumber: Bool {
        didSet { defaults.set(isAutoFormatListRenumber, forKey: Keys.autoFormatListRenumber) }
    }

    /// Auto-align table columns.
    public var isAutoFormatTableAlignment: Bool {
        didSet { defaults.set(isAutoFormatTableAlignment, forKey: Keys.autoFormatTableAlignment) }
    }

    /// Normalize heading spacing.
    public var isAutoFormatHeadingSpacing: Bool {
        didSet { defaults.set(isAutoFormatHeadingSpacing, forKey: Keys.autoFormatHeadingSpacing) }
    }

    /// How trailing whitespace is handled.
    public var trailingWhitespaceBehavior: TrailingWhitespaceBehavior {
        didSet { defaults.set(trailingWhitespaceBehavior.rawValue, forKey: Keys.trailingWhitespace) }
    }

    // MARK: - AI

    /// Whether AI ghost text (inline completions) is shown.
    public var isGhostTextEnabled: Bool {
        didSet { defaults.set(isGhostTextEnabled, forKey: Keys.ghostText) }
    }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.preferredColorScheme = ColorSchemePreference(
            rawValue: defaults.string(forKey: Keys.colorScheme) ?? ""
        ) ?? .system

        self.fontName = defaults.string(forKey: Keys.fontName) ?? FontName.system
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 17.0

        self.isSpellCheckEnabled = defaults.object(forKey: Keys.spellCheck) as? Bool ?? true
        self.isAutoFormatEnabled = defaults.object(forKey: Keys.autoFormat) as? Bool ?? true
        self.isAutoFormatListContinuation = defaults.object(forKey: Keys.autoFormatListContinuation) as? Bool ?? true
        self.isAutoFormatListRenumber = defaults.object(forKey: Keys.autoFormatListRenumber) as? Bool ?? true
        self.isAutoFormatTableAlignment = defaults.object(forKey: Keys.autoFormatTableAlignment) as? Bool ?? true
        self.isAutoFormatHeadingSpacing = defaults.object(forKey: Keys.autoFormatHeadingSpacing) as? Bool ?? true
        self.trailingWhitespaceBehavior = TrailingWhitespaceBehavior(
            rawValue: defaults.string(forKey: Keys.trailingWhitespace) ?? ""
        ) ?? .strip
        self.isGhostTextEnabled = defaults.object(forKey: Keys.ghostText) as? Bool ?? true
    }

    private enum Keys {
        static let colorScheme = "em_colorScheme"
        static let fontName = "em_fontName"
        static let fontSize = "em_fontSize"
        static let spellCheck = "em_spellCheck"
        static let autoFormat = "em_autoFormat"
        static let autoFormatListContinuation = "em_autoFormatListContinuation"
        static let autoFormatListRenumber = "em_autoFormatListRenumber"
        static let autoFormatTableAlignment = "em_autoFormatTableAlignment"
        static let autoFormatHeadingSpacing = "em_autoFormatHeadingSpacing"
        static let trailingWhitespace = "em_trailingWhitespace"
        static let ghostText = "em_ghostText"
    }
}

/// User's color scheme preference.
public enum ColorSchemePreference: String, Sendable, CaseIterable {
    case system
    case light
    case dark
}

/// How trailing whitespace is handled on save.
public enum TrailingWhitespaceBehavior: String, Sendable, CaseIterable {
    /// Strip trailing whitespace from all lines.
    case strip
    /// Leave trailing whitespace as-is.
    case keep
}

/// Known font name constants.
public enum FontName {
    /// The platform system font.
    public static let system = "System"
    /// A monospaced system font.
    public static let monospaced = "Monospaced"
}
