/// Coordinates the AI Improve Writing flow between EMAI and the text view per FEAT-011.
/// Handles: starting improve, streaming diff updates, accept, dismiss, undo.
/// Lives in EMEditor (supporting package per [A-050]).

import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// Callback protocol for the improve coordinator to communicate with the text view.
/// Implemented by TextViewCoordinator or a similar bridge.
@MainActor
public protocol ImproveWritingTextViewDelegate: AnyObject {
    /// Returns the current text content of the text view.
    func currentText() -> String

    /// Returns the current selected range.
    func currentSelectedRange() -> NSRange

    /// Returns the text storage for direct manipulation.
    func textStorage() -> NSMutableAttributedString?

    /// Returns the base font for the current rendering configuration.
    func baseFont() -> PlatformFont

    /// Replaces text in the given range.
    /// - Parameters:
    ///   - range: The NSRange to replace.
    ///   - replacement: The replacement text.
    func replaceText(in range: NSRange, with replacement: String)

    /// Triggers a re-render of the document after diff cleanup.
    func requestRerender()
}

/// Coordinates the full AI Improve Writing lifecycle per FEAT-011.
///
/// Usage flow:
/// 1. User selects text and taps "Improve"
/// 2. Coordinator calls `startImprove()` — begins streaming from EMAI
/// 3. Tokens stream in, diff preview updates progressively
/// 4. User taps Accept → text replaced, undo registered, haptic fires
/// 5. User taps Dismiss → diff removed, original text restored
@MainActor
@Observable
public final class ImproveWritingCoordinator {
    /// The inline diff state (observable by the UI layer).
    public let diffState = InlineDiffState()

    /// Weak reference to the text view delegate.
    public weak var textViewDelegate: ImproveWritingTextViewDelegate?

    /// The editor state for undo manager access.
    private let editorState: EditorState

    /// The streaming task.
    private var streamingTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "improve-coordinator")

    /// Signpost for measuring improve flow latency per [A-037].
    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "improve"
    )

    /// Creates an improve writing coordinator.
    /// - Parameter editorState: The editor state for undo manager access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    /// Starts the improve writing flow.
    /// Takes the current selection, begins streaming from the improve service,
    /// and updates the inline diff progressively.
    ///
    /// - Parameter updateStream: An `AsyncStream` of improve writing updates from EMAI.
    ///   The caller (EMApp composition root) is responsible for starting the EMAI service
    ///   and passing the stream here — this keeps EMEditor decoupled from EMAI per [A-015].
    public func startImprove(
        updateStream: AsyncStream<ImproveWritingUpdate>
    ) {
        guard let delegate = textViewDelegate else {
            logger.warning("No text view delegate set — cannot start improve")
            return
        }

        let selectedRange = delegate.currentSelectedRange()
        guard selectedRange.length > 0 else {
            logger.debug("No text selected — ignoring improve request")
            return
        }

        let text = delegate.currentText()
        guard let swiftRange = Range(selectedRange, in: text) else { return }
        let selectedText = String(text[swiftRange])

        // Cancel any existing session
        cancel()

        // Begin the diff session
        diffState.begin(originalText: selectedText, range: selectedRange)

        signpost.begin("improve-flow")

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
                    self.signpost.end("improve-flow")

                case .failed(let error):
                    self.logger.error("Improve failed: \(error.localizedDescription)")
                    self.removeDiffVisuals()
                    self.textViewDelegate?.requestRerender()
                    self.diffState.reset()
                    self.signpost.end("improve-flow")
                }
            }
        }
    }

    /// Accepts the AI suggestion per AC-6.
    /// Replaces the original text with the improved text,
    /// registers a single undo group per [A-022],
    /// and triggers haptic confirmation per AC-6.
    public func accept() {
        guard diffState.isActive || diffState.phase == .ready else { return }
        guard let delegate = textViewDelegate else { return }

        let improvedText = diffState.improvedText
        let originalRange = diffState.originalRange
        let originalText = diffState.originalText

        // Step 1: Remove diff visuals (inserted suggestion + deletion styling)
        // without triggering a re-render yet.
        removeDiffVisuals()

        // Step 2: Register undo as a single group per [A-022] and [AC-4].
        // The undo action replaces improved text back with original.
        let undoManager = editorState.undoManager
        let improvedLength = (improvedText as NSString).length
        let improvedNSRange = NSRange(
            location: originalRange.location,
            length: improvedLength
        )

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { coordinator in
            guard let delegate = coordinator.textViewDelegate else { return }
            delegate.replaceText(in: improvedNSRange, with: originalText)
            delegate.requestRerender()
        }
        undoManager.endUndoGrouping()

        // Step 3: Replace original text with improved text.
        delegate.replaceText(in: originalRange, with: improvedText)

        // Step 4: Re-render once to restore markdown styling.
        delegate.requestRerender()

        diffState.markAccepted()

        // Step 5: Haptic feedback per AC-6 and [A-062].
        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Improve accepted: replaced \(originalText.count) chars with \(improvedText.count) chars")

        // Reset after a brief delay to allow UI to settle
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
        }
    }

    /// Dismisses the AI suggestion per AC-7.
    /// Returns to original text with no modifications.
    public func dismiss() {
        streamingTask?.cancel()
        streamingTask = nil

        // Remove all diff visuals — original text remains untouched
        removeDiffVisuals()
        textViewDelegate?.requestRerender()

        diffState.markDismissed()

        logger.debug("Improve dismissed — original text unchanged")

        // Reset state
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.diffState.reset()
        }
    }

    /// Cancels the current improve session (e.g., on deselect or new selection).
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

    /// Updates the diff preview with the latest accumulated improved text.
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

    /// Removes diff visual artifacts from the text storage without triggering a re-render.
    /// Used by accept/dismiss/cancel before applying further changes.
    private func removeDiffVisuals() {
        guard let storage = textViewDelegate?.textStorage() else { return }

        storage.beginEditing()
        InlineDiffRenderer.removeDiff(from: storage)
        storage.endEditing()
    }
}
