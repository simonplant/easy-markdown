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

    /// Selected theme ID per FEAT-019. Matches a Theme.id from the built-in theme list.
    public var themeID: String {
        didSet { defaults.set(themeID, forKey: Keys.themeID) }
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

    /// Normalize heading spacing (add space after #, remove trailing #).
    public var isAutoFormatHeadingSpacing: Bool {
        didSet { defaults.set(isAutoFormatHeadingSpacing, forKey: Keys.autoFormatHeadingSpacing) }
    }

    /// Auto-insert blank line between block elements (headings, horizontal rules).
    public var isAutoFormatBlankLineSeparation: Bool {
        didSet { defaults.set(isAutoFormatBlankLineSeparation, forKey: Keys.autoFormatBlankLineSeparation) }
    }

    /// Ensure file ends with exactly one newline on save.
    public var isAutoFormatEnsureTrailingNewline: Bool {
        didSet { defaults.set(isAutoFormatEnsureTrailingNewline, forKey: Keys.autoFormatEnsureTrailingNewline) }
    }

    /// How trailing whitespace is handled.
    public var trailingWhitespaceBehavior: TrailingWhitespaceBehavior {
        didSet { defaults.set(trailingWhitespaceBehavior.rawValue, forKey: Keys.trailingWhitespace) }
    }

    // MARK: - Extended Doctor per FEAT-022

    /// Whether prose suggestions (long sentences, passive voice, repeated words) are enabled.
    /// Opt-in per FEAT-022 — disabled by default.
    public var isProseSuggestionsEnabled: Bool {
        didSet { defaults.set(isProseSuggestionsEnabled, forKey: Keys.proseSuggestions) }
    }

    /// Target word count for the writing goal. Zero means no goal is set.
    public var writingGoalWordCount: Int {
        didSet { defaults.set(writingGoalWordCount, forKey: Keys.writingGoalWordCount) }
    }

    // MARK: - AI

    /// Whether AI ghost text (inline completions) is shown.
    public var isGhostTextEnabled: Bool {
        didSet { defaults.set(isGhostTextEnabled, forKey: Keys.ghostText) }
    }

    // MARK: - Model Download per [D-AI-9]

    /// Current state of the on-device AI model download.
    public var modelDownloadState: ModelDownloadState {
        didSet { defaults.set(modelDownloadState.rawValue, forKey: Keys.modelDownloadState) }
    }

    /// Whether the user has been shown the model download prompt.
    /// When dismissed, the prompt reappears on next launch per spec.
    public var hasSeenModelDownloadPrompt: Bool {
        didSet { defaults.set(hasSeenModelDownloadPrompt, forKey: Keys.hasSeenModelDownloadPrompt) }
    }

    // MARK: - On-Device Aggregate Counters per [D-BIZ-6]

    /// Number of times AI Improve Writing has been used.
    public private(set) var aiImproveCount: Int {
        didSet { defaults.set(aiImproveCount, forKey: Keys.aiImproveCount) }
    }

    /// Number of times AI Summarize has been used.
    public private(set) var aiSummarizeCount: Int {
        didSet { defaults.set(aiSummarizeCount, forKey: Keys.aiSummarizeCount) }
    }

    /// Number of times an AI Continue Writing suggestion was accepted.
    public private(set) var aiContinueAcceptCount: Int {
        didSet { defaults.set(aiContinueAcceptCount, forKey: Keys.aiContinueAcceptCount) }
    }

    /// Number of times a Document Doctor fix was accepted.
    public private(set) var doctorFixAcceptCount: Int {
        didSet { defaults.set(doctorFixAcceptCount, forKey: Keys.doctorFixAcceptCount) }
    }

    /// Number of documents opened (cumulative across launches).
    public private(set) var documentsOpenedCount: Int {
        didSet { defaults.set(documentsOpenedCount, forKey: Keys.documentsOpenedCount) }
    }

    /// Number of distinct days the app has been actively used.
    public private(set) var daysActiveCount: Int {
        didSet { defaults.set(daysActiveCount, forKey: Keys.daysActiveCount) }
    }

    /// Date string (yyyy-MM-dd) of the last day the app was recorded as active.
    private var lastActiveDateString: String? {
        didSet { defaults.set(lastActiveDateString, forKey: Keys.lastActiveDateString) }
    }

    /// Increments the specified counter by one.
    public func recordAIImprove() { aiImproveCount += 1 }

    /// Increments the specified counter by one.
    public func recordAISummarize() { aiSummarizeCount += 1 }

    /// Increments the specified counter by one.
    public func recordAIContinueAccept() { aiContinueAcceptCount += 1 }

    /// Increments the specified counter by one.
    public func recordDoctorFixAccept() { doctorFixAcceptCount += 1 }

    /// Increments the specified counter by one.
    public func recordDocumentOpened() { documentsOpenedCount += 1 }

    /// Records the app as active today. Increments `daysActiveCount` only on the first call per calendar day.
    public func recordDayActive() {
        let today = Self.todayString()
        guard today != lastActiveDateString else { return }
        lastActiveDateString = today
        daysActiveCount += 1
    }

    /// Date formatter for day-active tracking. Uses fixed POSIX locale to avoid calendar/locale ambiguity.
    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - App Store Review Prompt per FEAT-069

    /// Whether the user has already been prompted for an App Store review.
    /// Once true, the prompt never appears again per FEAT-069.
    public var hasPromptedForReview: Bool {
        didSet { defaults.set(hasPromptedForReview, forKey: Keys.hasPromptedForReview) }
    }

    /// Total AI feature usage count across all AI actions.
    /// Used to evaluate review prompt eligibility (≥ 10 uses required).
    public var totalAIUsageCount: Int {
        aiImproveCount + aiSummarizeCount + aiContinueAcceptCount + doctorFixAcceptCount
    }

    // MARK: - Export per FEAT-061

    /// Whether exported PDFs include a "Made with easy-markdown" footer watermark.
    /// Enabled by default for PDF export per [A-056].
    public var isPDFExportWatermarkEnabled: Bool {
        didSet { defaults.set(isPDFExportWatermarkEnabled, forKey: Keys.pdfExportWatermark) }
    }

    // MARK: - State Restoration per [A-061]

    /// Security-scoped bookmark data for the last open file.
    public var lastOpenFileBookmark: Data? {
        didSet { defaults.set(lastOpenFileBookmark, forKey: Keys.lastOpenFileBookmark) }
    }

    /// Cursor position (character offset) in the last open file.
    public var lastCursorPosition: Int {
        didSet { defaults.set(lastCursorPosition, forKey: Keys.lastCursorPosition) }
    }

    /// Whether the editor was in source view mode.
    public var lastViewModeIsSource: Bool {
        didSet { defaults.set(lastViewModeIsSource, forKey: Keys.lastViewModeIsSource) }
    }

    /// Scroll offset as a fractional position (0.0–1.0 of document height).
    public var lastScrollFraction: Double {
        didSet { defaults.set(lastScrollFraction, forKey: Keys.lastScrollFraction) }
    }

    /// Clears all state restoration data (e.g., when file is closed or bookmark becomes stale).
    public func clearStateRestoration() {
        lastOpenFileBookmark = nil
        lastCursorPosition = 0
        lastViewModeIsSource = false
        lastScrollFraction = 0.0
    }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.preferredColorScheme = ColorSchemePreference(
            rawValue: defaults.string(forKey: Keys.colorScheme) ?? ""
        ) ?? .system

        self.themeID = defaults.string(forKey: Keys.themeID) ?? "default"
        self.fontName = defaults.string(forKey: Keys.fontName) ?? FontName.sourceSerif
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 17.0

        self.isSpellCheckEnabled = defaults.object(forKey: Keys.spellCheck) as? Bool ?? true
        self.isAutoFormatEnabled = defaults.object(forKey: Keys.autoFormat) as? Bool ?? true
        self.isAutoFormatListContinuation = defaults.object(forKey: Keys.autoFormatListContinuation) as? Bool ?? true
        self.isAutoFormatListRenumber = defaults.object(forKey: Keys.autoFormatListRenumber) as? Bool ?? true
        self.isAutoFormatTableAlignment = defaults.object(forKey: Keys.autoFormatTableAlignment) as? Bool ?? true
        self.isAutoFormatHeadingSpacing = defaults.object(forKey: Keys.autoFormatHeadingSpacing) as? Bool ?? true
        self.isAutoFormatBlankLineSeparation = defaults.object(forKey: Keys.autoFormatBlankLineSeparation) as? Bool ?? true
        self.isAutoFormatEnsureTrailingNewline = defaults.object(forKey: Keys.autoFormatEnsureTrailingNewline) as? Bool ?? true
        self.trailingWhitespaceBehavior = TrailingWhitespaceBehavior(
            rawValue: defaults.string(forKey: Keys.trailingWhitespace) ?? ""
        ) ?? .strip
        self.isProseSuggestionsEnabled = defaults.object(forKey: Keys.proseSuggestions) as? Bool ?? false
        self.writingGoalWordCount = defaults.object(forKey: Keys.writingGoalWordCount) as? Int ?? 0
        self.isGhostTextEnabled = defaults.object(forKey: Keys.ghostText) as? Bool ?? true

        self.modelDownloadState = ModelDownloadState(
            rawValue: defaults.string(forKey: Keys.modelDownloadState) ?? ""
        ) ?? .notDownloaded
        self.hasSeenModelDownloadPrompt = defaults.object(forKey: Keys.hasSeenModelDownloadPrompt) as? Bool ?? false

        // On-device aggregate counters
        self.aiImproveCount = defaults.integer(forKey: Keys.aiImproveCount)
        self.aiSummarizeCount = defaults.integer(forKey: Keys.aiSummarizeCount)
        self.aiContinueAcceptCount = defaults.integer(forKey: Keys.aiContinueAcceptCount)
        self.doctorFixAcceptCount = defaults.integer(forKey: Keys.doctorFixAcceptCount)
        self.documentsOpenedCount = defaults.integer(forKey: Keys.documentsOpenedCount)
        self.daysActiveCount = defaults.integer(forKey: Keys.daysActiveCount)
        self.lastActiveDateString = defaults.string(forKey: Keys.lastActiveDateString)

        // Export
        self.isPDFExportWatermarkEnabled = defaults.object(forKey: Keys.pdfExportWatermark) as? Bool ?? true

        // Review prompt
        self.hasPromptedForReview = defaults.object(forKey: Keys.hasPromptedForReview) as? Bool ?? false

        // State restoration
        self.lastOpenFileBookmark = defaults.data(forKey: Keys.lastOpenFileBookmark)
        self.lastCursorPosition = defaults.object(forKey: Keys.lastCursorPosition) as? Int ?? 0
        self.lastViewModeIsSource = defaults.object(forKey: Keys.lastViewModeIsSource) as? Bool ?? false
        self.lastScrollFraction = defaults.object(forKey: Keys.lastScrollFraction) as? Double ?? 0.0
    }

    private enum Keys {
        static let colorScheme = "em_colorScheme"
        static let themeID = "em_themeID"
        static let fontName = "em_fontName"
        static let fontSize = "em_fontSize"
        static let spellCheck = "em_spellCheck"
        static let autoFormat = "em_autoFormat"
        static let autoFormatListContinuation = "em_autoFormatListContinuation"
        static let autoFormatListRenumber = "em_autoFormatListRenumber"
        static let autoFormatTableAlignment = "em_autoFormatTableAlignment"
        static let autoFormatHeadingSpacing = "em_autoFormatHeadingSpacing"
        static let autoFormatBlankLineSeparation = "em_autoFormatBlankLineSeparation"
        static let autoFormatEnsureTrailingNewline = "em_autoFormatEnsureTrailingNewline"
        static let trailingWhitespace = "em_trailingWhitespace"
        static let proseSuggestions = "em_proseSuggestions"
        static let writingGoalWordCount = "em_writingGoalWordCount"
        static let ghostText = "em_ghostText"
        static let modelDownloadState = "em_modelDownloadState"
        static let hasSeenModelDownloadPrompt = "em_hasSeenModelDownloadPrompt"
        static let aiImproveCount = "em_counter_aiImprove"
        static let aiSummarizeCount = "em_counter_aiSummarize"
        static let aiContinueAcceptCount = "em_counter_aiContinueAccept"
        static let doctorFixAcceptCount = "em_counter_doctorFixAccept"
        static let documentsOpenedCount = "em_counter_documentsOpened"
        static let daysActiveCount = "em_counter_daysActive"
        static let lastActiveDateString = "em_counter_lastActiveDate"
        static let pdfExportWatermark = "em_pdfExportWatermark"
        static let hasPromptedForReview = "em_hasPromptedForReview"
        static let lastOpenFileBookmark = "em_lastOpenFileBookmark"
        static let lastCursorPosition = "em_lastCursorPosition"
        static let lastViewModeIsSource = "em_lastViewModeIsSource"
        static let lastScrollFraction = "em_lastScrollFraction"
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

/// State of the on-device AI model download per [D-AI-9].
public enum ModelDownloadState: String, Sendable, CaseIterable {
    /// Model has not been downloaded yet.
    case notDownloaded
    /// Model is currently downloading.
    case downloading
    /// Model has been downloaded and is ready.
    case downloaded
}

/// Known font name constants per FEAT-019.
/// Curated list — we control quality, not the system font picker.
public enum FontName {
    /// Source Serif 4 — bundled serif typeface, the default.
    public static let sourceSerif = "Source Serif"
    /// The platform system font (San Francisco on Apple platforms).
    public static let system = "System"
    /// A monospaced system font.
    public static let monospaced = "Monospaced"
    /// A rounded system font variant.
    public static let rounded = "Rounded"

    /// All available font choices in display order.
    public static let allChoices: [String] = [sourceSerif, system, monospaced, rounded]

    /// Human-readable display name for a font choice.
    public static func displayName(_ choice: String) -> String {
        switch choice {
        case sourceSerif: return "Source Serif"
        case system: return "System"
        case monospaced: return "Monospaced"
        case rounded: return "Rounded"
        default: return choice
        }
    }
}
