import Testing
import Foundation
@testable import EMSettings

@MainActor
@Suite("SettingsManager")
struct SettingsManagerTests {

    private func makeManager() -> (SettingsManager, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = SettingsManager(defaults: defaults)
        return (manager, defaults)
    }

    // MARK: - Defaults

    @Test("Uses opinionated defaults when UserDefaults is empty")
    func defaultValues() {
        let (m, _) = makeManager()
        #expect(m.preferredColorScheme == .system)
        #expect(m.fontName == FontName.system)
        #expect(m.fontSize == 17.0)
        #expect(m.isSpellCheckEnabled == true)
        #expect(m.isAutoFormatEnabled == true)
        #expect(m.isAutoFormatListContinuation == true)
        #expect(m.isAutoFormatListRenumber == true)
        #expect(m.isAutoFormatTableAlignment == true)
        #expect(m.isAutoFormatHeadingSpacing == true)
        #expect(m.isAutoFormatBlankLineSeparation == true)
        #expect(m.isAutoFormatEnsureTrailingNewline == true)
        #expect(m.trailingWhitespaceBehavior == .strip)
        #expect(m.isGhostTextEnabled == true)
        #expect(m.modelDownloadState == .notDownloaded)
        #expect(m.hasSeenModelDownloadPrompt == false)
        #expect(m.isPDFExportWatermarkEnabled == true)
    }

    // MARK: - Persistence

    @Test("Color scheme persists to UserDefaults")
    func colorSchemePersists() {
        let (m, d) = makeManager()
        m.preferredColorScheme = .dark
        #expect(d.string(forKey: "em_colorScheme") == "dark")
    }

    @Test("Font name persists to UserDefaults")
    func fontNamePersists() {
        let (m, d) = makeManager()
        m.fontName = FontName.monospaced
        #expect(d.string(forKey: "em_fontName") == FontName.monospaced)
    }

    @Test("Font size persists to UserDefaults")
    func fontSizePersists() {
        let (m, d) = makeManager()
        m.fontSize = 24.0
        #expect(d.double(forKey: "em_fontSize") == 24.0)
    }

    @Test("Spell check persists to UserDefaults")
    func spellCheckPersists() {
        let (m, d) = makeManager()
        m.isSpellCheckEnabled = false
        #expect(d.bool(forKey: "em_spellCheck") == false)
    }

    @Test("Auto-format master toggle persists")
    func autoFormatPersists() {
        let (m, d) = makeManager()
        m.isAutoFormatEnabled = false
        #expect(d.bool(forKey: "em_autoFormat") == false)
    }

    @Test("Per-rule auto-format toggles persist")
    func perRuleAutoFormatPersists() {
        let (m, d) = makeManager()

        m.isAutoFormatListContinuation = false
        #expect(d.bool(forKey: "em_autoFormatListContinuation") == false)

        m.isAutoFormatListRenumber = false
        #expect(d.bool(forKey: "em_autoFormatListRenumber") == false)

        m.isAutoFormatTableAlignment = false
        #expect(d.bool(forKey: "em_autoFormatTableAlignment") == false)

        m.isAutoFormatHeadingSpacing = false
        #expect(d.bool(forKey: "em_autoFormatHeadingSpacing") == false)

        m.isAutoFormatBlankLineSeparation = false
        #expect(d.bool(forKey: "em_autoFormatBlankLineSeparation") == false)

        m.isAutoFormatEnsureTrailingNewline = false
        #expect(d.bool(forKey: "em_autoFormatEnsureTrailingNewline") == false)
    }

    @Test("Trailing whitespace behavior persists")
    func trailingWhitespacePersists() {
        let (m, d) = makeManager()
        m.trailingWhitespaceBehavior = .keep
        #expect(d.string(forKey: "em_trailingWhitespace") == "keep")
    }

    @Test("Ghost text toggle persists")
    func ghostTextPersists() {
        let (m, d) = makeManager()
        m.isGhostTextEnabled = false
        #expect(d.bool(forKey: "em_ghostText") == false)
    }

    @Test("Model download state persists")
    func modelDownloadStatePersists() {
        let (m, d) = makeManager()
        m.modelDownloadState = .downloading
        #expect(d.string(forKey: "em_modelDownloadState") == "downloading")
        m.modelDownloadState = .downloaded
        #expect(d.string(forKey: "em_modelDownloadState") == "downloaded")
    }

    @Test("Model download prompt seen flag persists")
    func modelDownloadPromptPersists() {
        let (m, d) = makeManager()
        m.hasSeenModelDownloadPrompt = true
        #expect(d.bool(forKey: "em_hasSeenModelDownloadPrompt") == true)
    }

    @Test("PDF export watermark toggle persists")
    func pdfExportWatermarkPersists() {
        let (m, d) = makeManager()
        m.isPDFExportWatermarkEnabled = false
        #expect(d.bool(forKey: "em_pdfExportWatermark") == false)
    }

    // MARK: - Restoration

    @Test("Settings restore from UserDefaults on init")
    func restoresFromDefaults() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Write values before creating manager
        defaults.set("dark", forKey: "em_colorScheme")
        defaults.set(FontName.monospaced, forKey: "em_fontName")
        defaults.set(22.0, forKey: "em_fontSize")
        defaults.set(false, forKey: "em_spellCheck")
        defaults.set(false, forKey: "em_autoFormat")
        defaults.set(false, forKey: "em_autoFormatListContinuation")
        defaults.set(false, forKey: "em_autoFormatListRenumber")
        defaults.set(false, forKey: "em_autoFormatTableAlignment")
        defaults.set(false, forKey: "em_autoFormatHeadingSpacing")
        defaults.set(false, forKey: "em_autoFormatBlankLineSeparation")
        defaults.set(false, forKey: "em_autoFormatEnsureTrailingNewline")
        defaults.set("keep", forKey: "em_trailingWhitespace")
        defaults.set(false, forKey: "em_ghostText")
        defaults.set("downloaded", forKey: "em_modelDownloadState")
        defaults.set(true, forKey: "em_hasSeenModelDownloadPrompt")
        defaults.set(false, forKey: "em_pdfExportWatermark")

        let m = SettingsManager(defaults: defaults)

        #expect(m.preferredColorScheme == .dark)
        #expect(m.fontName == FontName.monospaced)
        #expect(m.fontSize == 22.0)
        #expect(m.isSpellCheckEnabled == false)
        #expect(m.isAutoFormatEnabled == false)
        #expect(m.isAutoFormatListContinuation == false)
        #expect(m.isAutoFormatListRenumber == false)
        #expect(m.isAutoFormatTableAlignment == false)
        #expect(m.isAutoFormatHeadingSpacing == false)
        #expect(m.isAutoFormatBlankLineSeparation == false)
        #expect(m.isAutoFormatEnsureTrailingNewline == false)
        #expect(m.trailingWhitespaceBehavior == .keep)
        #expect(m.isGhostTextEnabled == false)
        #expect(m.modelDownloadState == .downloaded)
        #expect(m.hasSeenModelDownloadPrompt == true)
        #expect(m.isPDFExportWatermarkEnabled == false)
    }
}
