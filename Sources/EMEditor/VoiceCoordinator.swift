/// Coordinates the Voice Control flow per FEAT-068.
/// Manages: speech recognition, transcript display, AI intent interpretation,
/// inline diff preview, accept/dismiss.
/// Lives in EMEditor (supporting package per [A-050]).
///
/// Usage flow:
/// 1. User holds mic button (or Cmd+Shift+J) → `startListening()`
/// 2. Speech streams in real-time → `liveTranscript` updates per AC-3
/// 3. User releases mic → `stopListening()` → transcript sent to AI
/// 4. AI interprets intent and streams modified text → diff preview per AC-5
/// 5. User accepts or dismisses the diff
///
/// Chained commands per AC-9: after accepting a diff, the coordinator
/// returns to idle and is immediately ready for another voice command.

#if canImport(Speech)
import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// The phase of the voice control flow.
public enum VoicePhase: Sendable, Equatable {
    /// No active voice session.
    case idle
    /// Recording and transcribing speech per AC-2.
    case listening
    /// Transcription complete, AI is interpreting intent per AC-1.
    case interpreting
    /// AI is streaming modified text, diff preview is active per AC-5.
    case diffStreaming
    /// Diff is ready for accept/dismiss.
    case diffReady
}

/// Coordinates the full Voice Control lifecycle per FEAT-068.
@MainActor
@Observable
public final class VoiceCoordinator {
    /// The current phase of the voice flow.
    public private(set) var phase: VoicePhase = .idle

    /// The inline diff state (observable by the UI layer).
    public let diffState = InlineDiffState()

    /// The live transcript text, updated as the user speaks per AC-3.
    public var liveTranscript: String {
        speechManager.liveTranscript
    }

    /// Whether voice control is available (speech + AI supported).
    public var isAvailable: Bool {
        speechManager.isAvailable
    }

    /// Whether a diff is currently active (for floating bar mode switch).
    public var isDiffActive: Bool {
        phase == .diffStreaming || phase == .diffReady
    }

    /// Weak reference to the text view delegate (same protocol as ImproveWritingCoordinator).
    public weak var textViewDelegate: ImproveWritingTextViewDelegate?

    /// Closure that bridges to VoiceIntentService in EMAI.
    /// Called with (transcript, selectedText, surroundingContext, contentType)
    /// and returns an AsyncStream of ImproveWritingUpdate.
    /// Set by EMApp composition root to maintain module isolation per [A-015].
    public var onRequestVoiceIntent: (
        (_ transcript: String,
         _ selectedText: String,
         _ surroundingContext: String?,
         _ contentType: ContentType) -> AsyncStream<ImproveWritingUpdate>?
    )?

    /// The editor state for undo manager access.
    private let editorState: EditorState

    /// Speech recognition manager.
    let speechManager = SpeechRecognitionManager()

    /// The streaming task for AI intent interpretation.
    private var streamingTask: Task<Void, Never>?

    /// Observation task for monitoring speech state changes.
    private var observationTask: Task<Void, Never>?

    /// The text range being operated on (selection or current paragraph).
    private var operatingRange: NSRange = NSRange(location: 0, length: 0)

    /// The original text before modification.
    private var originalText: String = ""

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "voice-coordinator")

    /// Creates a voice coordinator.
    /// - Parameter editorState: The editor state for undo manager and selection access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    /// Starts listening for a voice command per AC-1, AC-2.
    /// Activates speech recognition and begins streaming transcription.
    public func startListening() {
        guard phase == .idle else {
            logger.debug("Cannot start listening in phase: \(String(describing: self.phase))")
            return
        }

        // Cancel any active diff from a previous command
        if diffState.isActive {
            cancelDiff()
        }

        phase = .listening
        speechManager.startRecording()

        // Observe speech state changes to detect completion
        observationTask = Task { [weak self] in
            guard let self else { return }

            // Poll for state changes — withObservationTracking alternative for @Observable
            while !Task.isCancelled {
                let currentState = await MainActor.run { self.speechManager.state }

                switch currentState {
                case .completed(let transcript):
                    await MainActor.run {
                        self.handleTranscriptCompleted(transcript)
                    }
                    return
                case .failed(let message):
                    await MainActor.run {
                        self.logger.error("Speech recognition failed: \(message)")
                        self.phase = .idle
                    }
                    return
                case .permissionDenied:
                    await MainActor.run {
                        self.logger.warning("Speech permission denied")
                        self.phase = .idle
                    }
                    return
                default:
                    break
                }

                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
            }
        }

        #if canImport(UIKit)
        HapticFeedback.trigger(.voiceActivated)
        #endif
    }

    /// Stops listening and triggers AI interpretation per AC-1.
    /// Called when the user releases the mic button.
    public func stopListening() {
        guard phase == .listening else { return }
        speechManager.stopRecording()
    }

    /// Accepts the AI-generated modification per AC-5.
    /// Replaces the original text with the modified text,
    /// registers a single undo group per [A-022],
    /// and triggers haptic confirmation per [A-062].
    public func accept() {
        guard diffState.isActive || diffState.phase == .ready else { return }
        guard let delegate = textViewDelegate else { return }

        let modifiedText = diffState.improvedText
        let originalRange = diffState.originalRange
        let originalText = diffState.originalText

        // Remove diff visuals
        removeDiffVisuals()

        // Register undo as a single group per [A-022]
        let undoManager = editorState.undoManager
        let modifiedLength = (modifiedText as NSString).length
        let modifiedNSRange = NSRange(
            location: originalRange.location,
            length: modifiedLength
        )

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { coordinator in
            guard let delegate = coordinator.textViewDelegate else { return }
            delegate.replaceText(in: modifiedNSRange, with: originalText)
            delegate.requestRerender()
        }
        undoManager.endUndoGrouping()

        // Replace original text with modified text
        delegate.replaceText(in: originalRange, with: modifiedText)
        delegate.requestRerender()

        diffState.markAccepted()

        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Voice intent accepted: replaced \(originalText.count) chars with \(modifiedText.count) chars")

        // Reset after a brief delay — ready for chained commands per AC-9
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
            self?.phase = .idle
        }
    }

    /// Dismisses the AI suggestion per AC-5.
    /// Returns to original text with no modifications.
    public func dismiss() {
        streamingTask?.cancel()
        streamingTask = nil

        removeDiffVisuals()
        textViewDelegate?.requestRerender()

        diffState.markDismissed()

        logger.debug("Voice intent dismissed — original text unchanged")

        // Reset — ready for chained commands per AC-9
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
            self?.phase = .idle
        }
    }

    /// Cancels the current voice session entirely.
    public func cancel() {
        observationTask?.cancel()
        observationTask = nil
        streamingTask?.cancel()
        streamingTask = nil
        speechManager.cancel()

        if diffState.isActive {
            cancelDiff()
        }

        phase = .idle
    }

    // MARK: - Private

    /// Called when speech recognition completes with a final transcript.
    private func handleTranscriptCompleted(_ transcript: String) {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.debug("Empty transcript — returning to idle")
            phase = .idle
            return
        }

        phase = .interpreting

        // Determine the text to operate on per AC-4:
        // Use current selection if available, otherwise use current paragraph.
        guard let delegate = textViewDelegate else {
            phase = .idle
            return
        }

        let selectedRange = delegate.currentSelectedRange()
        let fullText = delegate.currentText()

        let targetRange: NSRange
        let targetText: String

        if selectedRange.length > 0 {
            // AC-4: Operate on current selection
            targetRange = selectedRange
            guard let swiftRange = Range(selectedRange, in: fullText) else {
                phase = .idle
                return
            }
            targetText = String(fullText[swiftRange])
        } else {
            // AC-4: No selection — operate on current paragraph
            let paragraphRange = (fullText as NSString).paragraphRange(for: NSRange(location: selectedRange.location, length: 0))
            targetRange = paragraphRange
            guard let swiftRange = Range(paragraphRange, in: fullText) else {
                phase = .idle
                return
            }
            targetText = String(fullText[swiftRange])
        }

        operatingRange = targetRange
        originalText = targetText

        // Get surrounding context (one paragraph before and after)
        let surroundingContext = extractSurroundingContext(
            fullText: fullText,
            range: targetRange
        )

        // Request AI interpretation via the bridge closure
        guard let stream = onRequestVoiceIntent?(
            transcript,
            targetText,
            surroundingContext,
            .prose // Content type detection could be enhanced
        ) else {
            logger.warning("No voice intent handler set — cannot interpret")
            phase = .idle
            return
        }

        // Begin the diff session
        diffState.begin(originalText: targetText, range: targetRange)
        phase = .diffStreaming

        // Apply initial diff styling
        if let storage = delegate.textStorage() {
            storage.beginEditing()
            InlineDiffRenderer.applyDiff(
                to: storage,
                originalRange: targetRange,
                originalText: targetText,
                improvedText: "",
                baseFont: delegate.baseFont()
            )
            storage.endEditing()
        }

        // Consume the token stream
        streamingTask = Task { [weak self] in
            for await update in stream {
                guard let self, !Task.isCancelled else { break }

                switch update {
                case .token(let token):
                    self.diffState.appendToken(token)
                    self.updateDiffPreview()

                case .completed:
                    self.diffState.markReady()
                    self.phase = .diffReady

                case .failed(let error):
                    self.logger.error("Voice intent failed: \(error.localizedDescription)")
                    self.removeDiffVisuals()
                    self.textViewDelegate?.requestRerender()
                    self.diffState.reset()
                    self.phase = .idle
                }
            }
        }
    }

    /// Extracts surrounding context (one paragraph before and after) for better AI understanding.
    private func extractSurroundingContext(fullText: String, range: NSRange) -> String? {
        let nsString = fullText as NSString
        let totalLength = nsString.length

        // One paragraph before
        var contextStart = range.location
        if contextStart > 0 {
            let beforeRange = nsString.paragraphRange(for: NSRange(location: max(contextStart - 1, 0), length: 0))
            contextStart = beforeRange.location
        }

        // One paragraph after
        var contextEnd = NSMaxRange(range)
        if contextEnd < totalLength {
            let afterRange = nsString.paragraphRange(for: NSRange(location: min(contextEnd, totalLength - 1), length: 0))
            contextEnd = NSMaxRange(afterRange)
        }

        let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
        guard contextRange.length > range.length else { return nil }

        return nsString.substring(with: contextRange)
    }

    /// Updates the diff preview with the latest accumulated text.
    private func updateDiffPreview() {
        guard let delegate = textViewDelegate,
              let storage = delegate.textStorage() else { return }

        storage.beginEditing()
        InlineDiffRenderer.updateDiff(
            in: storage,
            originalRange: diffState.originalRange,
            improvedText: diffState.improvedText,
            baseFont: delegate.baseFont()
        )
        storage.endEditing()
    }

    /// Removes diff visual artifacts from the text storage.
    private func removeDiffVisuals() {
        guard let storage = textViewDelegate?.textStorage() else { return }
        storage.beginEditing()
        InlineDiffRenderer.removeDiff(from: storage)
        storage.endEditing()
    }

    /// Cancels an active diff and cleans up visuals.
    private func cancelDiff() {
        removeDiffVisuals()
        textViewDelegate?.requestRerender()
        diffState.reset()
    }
}
#endif
