/// Coordinates the AI Translation flow between EMAI and the text view per FEAT-024.
/// Handles: starting translation, streaming diff updates, accept, dismiss, undo.
/// On mid-stream failure, keeps partial result visible with retry/cancel per AC-4.
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

/// Coordinates the full AI Translation lifecycle per FEAT-024.
///
/// Usage flow:
/// 1. User selects text and taps "Translate" → picks a language
/// 2. Coordinator calls `startTranslation()` — begins streaming from EMAI
/// 3. Tokens stream in, diff preview updates progressively
/// 4. User taps Accept → text replaced, undo registered (AC-2), haptic fires
/// 5. User taps Dismiss → diff removed, original text restored
/// 6. On failure mid-stream → partial result stays visible (AC-4), retry/cancel offered
@MainActor
@Observable
public final class TranslationCoordinator {
    /// The inline diff state (observable by the UI layer).
    public let diffState = InlineDiffState()

    /// Whether the translation failed mid-stream with partial results per AC-4.
    public var hasPartialFailure: Bool = false

    /// The error from a mid-stream failure, if any.
    public private(set) var partialFailureError: EMError?

    /// Weak reference to the text view delegate.
    /// Reuses ImproveWritingTextViewDelegate — same interface needed.
    public weak var textViewDelegate: ImproveWritingTextViewDelegate?

    /// The editor state for undo manager access.
    private let editorState: EditorState

    /// The streaming task.
    private var streamingTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "translation-coordinator")

    /// Signpost for measuring translation flow latency per [A-037].
    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "translation"
    )

    /// Creates a translation coordinator.
    /// - Parameter editorState: The editor state for undo manager access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    /// Starts the translation flow.
    /// Takes the current selection, begins streaming from the translation service,
    /// and updates the inline diff progressively.
    ///
    /// - Parameter updateStream: An `AsyncStream` of translation updates from EMAI.
    ///   The caller (EMApp composition root) is responsible for starting the EMAI service
    ///   and passing the stream here — this keeps EMEditor decoupled from EMAI per [A-015].
    public func startTranslation(
        updateStream: AsyncStream<TranslationUpdate>
    ) {
        guard let delegate = textViewDelegate else {
            logger.warning("No text view delegate set — cannot start translation")
            return
        }

        let selectedRange = delegate.currentSelectedRange()
        guard selectedRange.length > 0 else {
            logger.debug("No text selected — ignoring translation request")
            return
        }

        let text = delegate.currentText()
        guard let swiftRange = Range(selectedRange, in: text) else { return }
        let selectedText = String(text[swiftRange])

        // Cancel any existing session
        cancel()

        // Reset partial failure state
        hasPartialFailure = false
        partialFailureError = nil

        // Begin the diff session
        diffState.begin(originalText: selectedText, range: selectedRange)

        signpost.begin("translation-flow")

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
                    self.signpost.end("translation-flow")

                case .failed(let error):
                    // AC-4: If we have partial results, keep them visible with retry/cancel
                    if !self.diffState.improvedText.isEmpty {
                        self.hasPartialFailure = true
                        self.partialFailureError = error
                        self.diffState.markReady()
                        self.logger.warning("Translation failed mid-stream with partial result: \(error.localizedDescription)")
                    } else {
                        // No partial results — remove diff and report error
                        self.logger.error("Translation failed with no results: \(error.localizedDescription)")
                        self.removeDiffVisuals()
                        self.textViewDelegate?.requestRerender()
                        self.diffState.reset()
                    }
                    self.signpost.end("translation-flow")
                }
            }
        }
    }

    /// Accepts the AI translation per FEAT-024 AC-1.
    /// Replaces the original text with the translated text,
    /// registers a single undo group per [A-022] (AC-2: undo restores original),
    /// and triggers haptic confirmation.
    public func accept() {
        guard diffState.isActive || diffState.phase == .ready else { return }
        guard let delegate = textViewDelegate else { return }

        let translatedText = diffState.improvedText
        let originalRange = diffState.originalRange
        let originalText = diffState.originalText

        // Step 1: Remove diff visuals
        removeDiffVisuals()

        // Step 2: Register undo as a single group per [A-022] — AC-2: undo restores original
        let undoManager = editorState.undoManager
        let translatedLength = (translatedText as NSString).length
        let translatedNSRange = NSRange(
            location: originalRange.location,
            length: translatedLength
        )

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { coordinator in
            guard let delegate = coordinator.textViewDelegate else { return }
            delegate.replaceText(in: translatedNSRange, with: originalText)
            delegate.requestRerender()
        }
        undoManager.endUndoGrouping()

        // Step 3: Replace original text with translated text
        delegate.replaceText(in: originalRange, with: translatedText)

        // Step 4: Re-render once to restore markdown styling
        delegate.requestRerender()

        diffState.markAccepted()

        // Clear partial failure state
        hasPartialFailure = false
        partialFailureError = nil

        // Step 5: Haptic feedback per [A-062]
        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Translation accepted: replaced \(originalText.count) chars with \(translatedText.count) chars")

        // Reset after a brief delay to allow UI to settle
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
        }
    }

    /// Dismisses the AI translation.
    /// Returns to original text with no modifications.
    public func dismiss() {
        streamingTask?.cancel()
        streamingTask = nil

        // Remove all diff visuals — original text remains untouched
        removeDiffVisuals()
        textViewDelegate?.requestRerender()

        diffState.markDismissed()

        // Clear partial failure state
        hasPartialFailure = false
        partialFailureError = nil

        logger.debug("Translation dismissed — original text unchanged")

        // Reset state
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
        }
    }

    /// Cancels the current translation session.
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil

        if diffState.isActive {
            removeDiffVisuals()
            textViewDelegate?.requestRerender()
        }

        hasPartialFailure = false
        partialFailureError = nil
        diffState.reset()
    }

    // MARK: - Private

    /// Updates the diff preview with the latest accumulated translated text.
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
