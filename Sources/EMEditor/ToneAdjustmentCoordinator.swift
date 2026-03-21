/// Coordinates the AI Tone Adjustment flow between EMAI and the text view per FEAT-023.
/// Handles: starting tone adjustment, streaming diff updates, accept, dismiss, undo.
/// Reuses the same inline diff preview as Improve Writing per the spec.
/// Lives in EMEditor (supporting package per feature-to-package mapping).

import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// Coordinates the full AI Tone Adjustment lifecycle per FEAT-023.
///
/// Usage flow:
/// 1. User selects text and taps "Tone" → picks a tone style
/// 2. Coordinator calls `startToneAdjustment()` — begins streaming from EMAI
/// 3. Tokens stream in, diff preview updates progressively
/// 4. User taps Accept → text replaced, undo registered, haptic fires (AC-1)
/// 5. User taps Dismiss → diff removed, original text restored
@MainActor
@Observable
public final class ToneAdjustmentCoordinator {
    /// The inline diff state (observable by the UI layer).
    public let diffState = InlineDiffState()

    /// Weak reference to the text view delegate.
    /// Reuses ImproveWritingTextViewDelegate — same interface needed.
    public weak var textViewDelegate: ImproveWritingTextViewDelegate?

    /// The editor state for undo manager access.
    private let editorState: EditorState

    /// The streaming task.
    private var streamingTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "tone-coordinator")

    /// Signpost for measuring tone adjustment flow latency per [A-037].
    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "tone"
    )

    /// Creates a tone adjustment coordinator.
    /// - Parameter editorState: The editor state for undo manager access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    /// Starts the tone adjustment flow.
    /// Takes the current selection, begins streaming from the tone service,
    /// and updates the inline diff progressively.
    ///
    /// - Parameter updateStream: An `AsyncStream` of tone adjustment updates from EMAI.
    ///   The caller (EMApp composition root) is responsible for starting the EMAI service
    ///   and passing the stream here — this keeps EMEditor decoupled from EMAI per [A-015].
    public func startToneAdjustment(
        updateStream: AsyncStream<ToneAdjustmentUpdate>
    ) {
        guard let delegate = textViewDelegate else {
            logger.warning("No text view delegate set — cannot start tone adjustment")
            return
        }

        let selectedRange = delegate.currentSelectedRange()
        guard selectedRange.length > 0 else {
            logger.debug("No text selected — ignoring tone adjustment request")
            return
        }

        let text = delegate.currentText()
        guard let swiftRange = Range(selectedRange, in: text) else { return }
        let selectedText = String(text[swiftRange])

        // Cancel any existing session
        cancel()

        // Begin the diff session
        diffState.begin(originalText: selectedText, range: selectedRange)

        signpost.begin("tone-flow")

        // Apply initial diff styling (original with strikethrough, no suggestion yet)
        if let storage = delegate.textStorage() {
            storage.beginEditing()
            InlineDiffRenderer.applyDiff(
                to: storage,
                originalRange: selectedRange,
                originalText: selectedText,
                improvedText: "",
                baseFont: delegate.baseFont()
            )
            storage.endEditing()
        }

        // Start consuming the token stream
        streamingTask = Task { [weak self] in
            for await update in updateStream {
                guard let self, !Task.isCancelled else { break }

                switch update {
                case .token(let token):
                    self.diffState.appendToken(token)
                    self.updateDiffPreview()

                case .completed:
                    self.diffState.markReady()
                    self.signpost.end("tone-flow")

                case .failed(let error):
                    self.logger.error("Tone adjustment failed: \(error.localizedDescription)")
                    self.removeDiffVisuals()
                    self.textViewDelegate?.requestRerender()
                    self.diffState.reset()
                    self.signpost.end("tone-flow")
                }
            }
        }
    }

    /// Accepts the AI suggestion per FEAT-023 AC-1.
    /// Replaces the original text with the tone-adjusted text,
    /// registers a single undo group per [A-022],
    /// and triggers haptic confirmation.
    public func accept() {
        guard diffState.isActive || diffState.phase == .ready else { return }
        guard let delegate = textViewDelegate else { return }

        let adjustedText = diffState.improvedText
        let originalRange = diffState.originalRange
        let originalText = diffState.originalText

        // Step 1: Remove diff visuals
        removeDiffVisuals()

        // Step 2: Register undo as a single group per [A-022]
        let undoManager = editorState.undoManager
        let adjustedLength = (adjustedText as NSString).length
        let adjustedNSRange = NSRange(
            location: originalRange.location,
            length: adjustedLength
        )

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { coordinator in
            guard let delegate = coordinator.textViewDelegate else { return }
            delegate.replaceText(in: adjustedNSRange, with: originalText)
            delegate.requestRerender()
        }
        undoManager.endUndoGrouping()

        // Step 3: Replace original text with tone-adjusted text
        delegate.replaceText(in: originalRange, with: adjustedText)

        // Step 4: Re-render once to restore markdown styling
        delegate.requestRerender()

        diffState.markAccepted()

        // Step 5: Haptic feedback per [A-062]
        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Tone adjustment accepted: replaced \(originalText.count) chars with \(adjustedText.count) chars")

        // Reset after a brief delay to allow UI to settle
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
        }
    }

    /// Dismisses the AI suggestion.
    /// Returns to original text with no modifications.
    public func dismiss() {
        streamingTask?.cancel()
        streamingTask = nil

        // Remove all diff visuals — original text remains untouched
        removeDiffVisuals()
        textViewDelegate?.requestRerender()

        diffState.markDismissed()

        logger.debug("Tone adjustment dismissed — original text unchanged")

        // Reset state
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
        }
    }

    /// Cancels the current tone adjustment session.
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil

        if diffState.isActive {
            removeDiffVisuals()
            textViewDelegate?.requestRerender()
        }

        diffState.reset()
    }

    // MARK: - Private

    /// Updates the diff preview with the latest accumulated adjusted text.
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
}
