import Foundation
import Observation
import EMCore
import EMEditor
import EMAI
import EMSettings

/// Owns all AI-related state and coordinators per FEAT-074.
///
/// Extracted from EditorShellView to make each AI concern independently
/// testable and to reduce the view's @State count. EditorShellView holds
/// a single `@State private var aiCoordinator: AICoordinator?` instead of
/// ~20 separate AI properties.
@MainActor
@Observable
final class AICoordinator {

    // MARK: - AI Coordinators (EMEditor layer)

    private(set) var improveCoordinator: ImproveWritingCoordinator?
    private(set) var summarizeCoordinator: SummarizeCoordinator?
    private(set) var toneCoordinator: ToneAdjustmentCoordinator?
    private(set) var translationCoordinator: TranslationCoordinator?
    private(set) var ghostTextCoordinator: GhostTextCoordinator?
    private(set) var smartCompletionCoordinator: SmartCompletionCoordinator?
    #if canImport(Speech)
    private(set) var voiceCoordinator: VoiceCoordinator?
    #endif

    // MARK: - AI Services (EMAI layer)

    private var improveService: ImproveWritingService?
    private var summarizeService: SummarizeService?
    private var toneService: ToneAdjustmentService?
    private var translationService: TranslationService?
    private var ghostTextService: GhostTextService?
    private var smartCompletionService: SmartCompletionService?
    #if canImport(Speech)
    private var voiceIntentService: VoiceIntentService?
    #endif

    // MARK: - UI State

    /// Tone picker confirmation dialog visibility.
    var showingTonePicker = false
    /// Custom tone text input alert visibility.
    var showingCustomToneInput = false
    /// Custom tone instruction text.
    var customToneInstruction = ""
    /// Language picker confirmation dialog visibility.
    var showingLanguagePicker = false
    /// Large selection warning alert visibility.
    var showingLongSelectionWarning = false
    /// Pending language code for translation after warning confirmation.
    var pendingTranslationLanguage: String = ""
    /// Last used translation language for retry per FEAT-024 AC-4.
    var lastTranslationLanguage: String = ""
    /// Whether user has Pro AI subscription for floating bar badge per FEAT-054 AC-3.
    var isProSubscriber = false
    /// Pro upgrade alert visibility.
    var showingProUpgrade = false

    // MARK: - Dependencies

    private let editorState: EditorState
    private let aiProviderManager: AIProviderManager
    private let settings: SettingsManager

    // MARK: - Init

    init(
        editorState: EditorState,
        aiProviderManager: AIProviderManager,
        settings: SettingsManager
    ) {
        self.editorState = editorState
        self.aiProviderManager = aiProviderManager
        self.settings = settings
    }

    // MARK: - Setup

    /// Creates all AI coordinators and services. Called once from onAppear.
    func setup() {
        guard aiProviderManager.shouldShowAIUI else { return }

        // FEAT-011: Improve Writing
        improveCoordinator = ImproveWritingCoordinator(editorState: editorState)
        improveService = ImproveWritingService(providerManager: aiProviderManager)

        // FEAT-055: Summarize
        summarizeCoordinator = SummarizeCoordinator(editorState: editorState)
        summarizeService = SummarizeService(providerManager: aiProviderManager)

        // FEAT-023: Tone Adjustment (Pro AI)
        toneCoordinator = ToneAdjustmentCoordinator(editorState: editorState)
        toneService = ToneAdjustmentService(providerManager: aiProviderManager)

        // FEAT-024: Translation (Pro AI)
        translationCoordinator = TranslationCoordinator(editorState: editorState)
        translationService = TranslationService(providerManager: aiProviderManager)

        // FEAT-056: Ghost Text
        setupGhostText()

        // FEAT-025: Smart Completions
        setupSmartCompletion()

        // FEAT-068: Voice Control
        #if canImport(Speech)
        setupVoiceControl()
        #endif
    }

    /// Cancels all active AI sessions. Called from onDisappear.
    func cancelAll() {
        improveCoordinator?.cancel()
        toneCoordinator?.cancel()
        translationCoordinator?.cancel()
        summarizeCoordinator?.cancel()
        ghostTextCoordinator?.cancel()
        smartCompletionCoordinator?.cancel()
        #if canImport(Speech)
        voiceCoordinator?.cancel()
        #endif
    }

    /// Updates ghost text / smart completion enabled state from settings.
    func updateGhostTextEnabled(_ enabled: Bool) {
        ghostTextCoordinator?.isEnabled = enabled
        smartCompletionCoordinator?.isEnabled = enabled
        if !enabled {
            ghostTextCoordinator?.cancel()
            smartCompletionCoordinator?.cancel()
        }
    }

    // MARK: - Improve Writing per FEAT-011

    /// Starts the AI improve flow per FEAT-011 AC-1.
    func startImprove(text: String) {
        guard let coordinator = improveCoordinator,
              let service = improveService else { return }

        let selectedRange = editorState.selection.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        // Cancel any active tone adjustment diff before starting improve
        toneCoordinator?.cancel()

        let selectedText = String(text[swiftRange])
        let stream = service.startImproving(selectedText: selectedText)
        coordinator.startImprove(updateStream: stream)
    }

    // MARK: - Summarize per FEAT-055

    /// Starts the AI summarize flow per FEAT-055 AC-1.
    func startSummarize(text: String) {
        guard let coordinator = summarizeCoordinator,
              let service = summarizeService else { return }

        let selectedRange = editorState.selection.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        let selectedText = String(text[swiftRange])
        let isFullDocument = selectedRange.length >= (text as NSString).length

        let stream = service.startSummarizing(
            selectedText: selectedText,
            isFullDocument: isFullDocument
        )
        coordinator.startSummarize(updateStream: stream)
    }

    // MARK: - Tone Adjustment per FEAT-023

    /// Starts the AI tone adjustment flow per FEAT-023 AC-1.
    func startToneAdjustment(toneStyle: ToneStyle, text: String) {
        guard let coordinator = toneCoordinator,
              let service = toneService else { return }

        let selectedRange = editorState.selection.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        let selectedText = String(text[swiftRange])

        // Cancel any active improve diff before starting tone adjustment
        improveCoordinator?.cancel()

        let stream = service.startAdjusting(
            selectedText: selectedText,
            toneStyle: toneStyle
        )
        coordinator.startToneAdjustment(updateStream: stream)
    }

    // MARK: - Translation per FEAT-024

    /// Checks selection word count and either warns (AC-5) or starts translation.
    func requestTranslation(targetLanguage: String, text: String) {
        let selectedRange = editorState.selection.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        let selectedText = String(text[swiftRange])

        // AC-5: Very long selection (5000+ words) shows warning about processing time
        let wordCount = selectedText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if wordCount >= 5000 {
            pendingTranslationLanguage = targetLanguage
            showingLongSelectionWarning = true
            return
        }

        startTranslation(targetLanguage: targetLanguage, text: text)
    }

    /// Starts the AI translation flow per FEAT-024 AC-1.
    func startTranslation(targetLanguage: String, text: String) {
        guard let coordinator = translationCoordinator,
              let service = translationService else { return }

        let selectedRange = editorState.selection.selectedRange
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text) else { return }

        let selectedText = String(text[swiftRange])

        // Store for retry per AC-4
        lastTranslationLanguage = targetLanguage

        // Cancel any active improve or tone diff before starting translation
        improveCoordinator?.cancel()
        toneCoordinator?.cancel()

        // AC-3: Only selected text is sent to cloud API per [D-AI-8]
        let stream = service.startTranslating(
            selectedText: selectedText,
            targetLanguage: targetLanguage
        )
        coordinator.startTranslation(updateStream: stream)
    }

    // MARK: - Floating Action Bar per FEAT-054

    /// Whether the floating action bar should be visible.
    var shouldShowFloatingBar: Bool {
        guard aiProviderManager.shouldShowAIUI else { return false }
        if let coordinator = improveCoordinator, coordinator.diffState.isActive {
            return true
        }
        if let coordinator = toneCoordinator, coordinator.diffState.isActive {
            return true
        }
        if let coordinator = translationCoordinator, coordinator.diffState.isActive {
            return true
        }
        #if canImport(Speech)
        if let coordinator = voiceCoordinator, coordinator.isDiffActive {
            return true
        }
        #endif
        return editorState.selection.selectedRange.length > 0
    }

    /// The active diff phase from whichever AI coordinator is currently running.
    var activeDiffPhase: InlineDiffPhase {
        if let translation = translationCoordinator, translation.diffState.isActive {
            return translation.diffState.phase
        }
        if let tone = toneCoordinator, tone.diffState.isActive {
            return tone.diffState.phase
        }
        if let improve = improveCoordinator, improve.diffState.isActive {
            return improve.diffState.phase
        }
        #if canImport(Speech)
        if let voice = voiceCoordinator, voice.isDiffActive {
            return voice.diffState.phase
        }
        #endif
        return .inactive
    }

    /// Accepts the active diff — dispatches to the correct coordinator.
    func acceptActiveDiff() {
        if let translation = translationCoordinator, translation.diffState.isActive {
            translation.accept()
        } else if let tone = toneCoordinator, tone.diffState.isActive {
            tone.accept()
        } else if let improve = improveCoordinator, improve.diffState.isActive {
            improve.accept()
        } else {
            #if canImport(Speech)
            if let voice = voiceCoordinator, voice.isDiffActive {
                voice.accept()
            }
            #endif
        }
    }

    /// Dismisses the active diff — dispatches to the correct coordinator.
    func dismissActiveDiff() {
        if let translation = translationCoordinator, translation.diffState.isActive {
            translation.dismiss()
        } else if let tone = toneCoordinator, tone.diffState.isActive {
            tone.dismiss()
        } else if let improve = improveCoordinator, improve.diffState.isActive {
            improve.dismiss()
        } else {
            #if canImport(Speech)
            if let voice = voiceCoordinator, voice.isDiffActive {
                voice.dismiss()
            }
            #endif
        }
    }

    // MARK: - Voice Control per FEAT-068

    /// Whether to show the voice mic button in the toolbar.
    var voiceMicVisible: Bool {
        #if canImport(Speech)
        return aiProviderManager.shouldShowAIUI && voiceCoordinator != nil
        #else
        return false
        #endif
    }

    /// Whether voice is currently listening.
    var voiceIsListening: Bool {
        #if canImport(Speech)
        return voiceCoordinator?.phase == .listening
        #else
        return false
        #endif
    }

    /// Whether voice is available on this device.
    var voiceIsAvailable: Bool {
        #if canImport(Speech)
        return voiceCoordinator?.isAvailable ?? false
        #else
        return false
        #endif
    }

    /// Toggles voice control — starts listening if idle, stops if listening.
    func toggleVoiceControl() {
        #if canImport(Speech)
        guard let coordinator = voiceCoordinator else { return }

        switch coordinator.phase {
        case .idle:
            // Cancel any active AI diffs before starting voice
            improveCoordinator?.cancel()
            toneCoordinator?.cancel()
            translationCoordinator?.cancel()
            coordinator.startListening()
        case .listening:
            coordinator.stopListening()
        case .interpreting, .diffStreaming:
            break
        case .diffReady:
            coordinator.accept()
        }
        #endif
    }

    /// Whether AI UI actions should be shown.
    var shouldShowAIUI: Bool {
        aiProviderManager.shouldShowAIUI
    }

    // MARK: - Private Setup

    private func setupGhostText() {
        guard aiProviderManager.shouldShowAIUI else { return }

        let service = GhostTextService(providerManager: aiProviderManager)
        ghostTextService = service

        let coordinator = GhostTextCoordinator(editorState: editorState)
        coordinator.isEnabled = settings.isGhostTextEnabled

        coordinator.onRequestGhostText = { [weak service] precedingText in
            guard let service else { return nil }
            return service.startGenerating(precedingText: precedingText)
        }

        ghostTextCoordinator = coordinator
    }

    private func setupSmartCompletion() {
        guard aiProviderManager.shouldShowAIUI else { return }

        let service = SmartCompletionService(providerManager: aiProviderManager)
        smartCompletionService = service

        let coordinator = SmartCompletionCoordinator(editorState: editorState)
        coordinator.isEnabled = settings.isGhostTextEnabled

        coordinator.onRequestSmartCompletion = { [weak service] structure, precedingText in
            guard let service else { return nil }
            let structureType: SmartCompletionPromptTemplate.StructureType = switch structure {
            case .tableHeader(let columns):
                .tableHeader(columns: columns)
            case .listItem(let prefix, let items):
                .listItem(prefix: prefix, items: items)
            case .frontMatter(let existingKeys):
                .frontMatter(existingKeys: existingKeys)
            }
            return service.startCompleting(
                structureType: structureType,
                precedingText: precedingText
            )
        }

        smartCompletionCoordinator = coordinator
    }

    #if canImport(Speech)
    private func setupVoiceControl() {
        guard aiProviderManager.shouldShowAIUI else { return }

        let service = VoiceIntentService(providerManager: aiProviderManager)
        voiceIntentService = service

        let coordinator = VoiceCoordinator(editorState: editorState)

        coordinator.onRequestVoiceIntent = { [weak service] transcript, selectedText, surroundingContext, contentType in
            guard let service else { return nil }
            return service.startInterpretingIntent(
                transcript: transcript,
                selectedText: selectedText,
                surroundingContext: surroundingContext,
                contentType: contentType
            )
        }

        voiceCoordinator = coordinator
    }
    #endif
}
