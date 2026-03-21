/// Coordinates the AI Continue Writing (ghost text) flow per FEAT-056.
/// Handles: typing pause detection (3s), ghost text rendering, Tab accept, typing dismiss.
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

/// The phase of a ghost text session, driving UI state.
public enum GhostTextPhase: Sendable, Equatable {
    /// No ghost text session active.
    case inactive
    /// Waiting for the typing pause timer to fire.
    case waitingForPause
    /// AI is streaming the ghost text continuation.
    case streaming
    /// Ghost text is fully generated and displayed — user can Tab to accept.
    case ready
    /// User accepted the ghost text (Tab).
    case accepted
    /// User dismissed the ghost text (typed a character).
    case dismissed
}

/// Callback protocol for the ghost text coordinator to communicate with the text view.
/// Implemented by TextViewCoordinator or a similar bridge.
@MainActor
public protocol GhostTextViewDelegate: AnyObject {
    /// Returns the current text content of the text view.
    func currentText() -> String

    /// Returns the current selected range (cursor position).
    func currentSelectedRange() -> NSRange

    /// Returns the text storage for direct manipulation.
    func textStorage() -> NSMutableAttributedString?

    /// Returns the base font for the current rendering configuration.
    func baseFont() -> PlatformFont

    /// Replaces text in the given range.
    func replaceText(in range: NSRange, with replacement: String)

    /// Triggers a re-render of the document after ghost text cleanup.
    func requestRerender()

    /// Whether the cursor is currently inside a code block per AC-4.
    func isCursorInsideCodeBlock() -> Bool
}

/// Coordinates the full AI Continue Writing (ghost text) lifecycle per FEAT-056.
///
/// Usage flow:
/// 1. User pauses typing for 3 seconds at end of content
/// 2. Coordinator triggers AI generation via the stream provided by composition root
/// 3. Ghost text appears dimmed inline at cursor position
/// 4. Tab accepts (ghost text becomes real text, undo registered)
/// 5. Typing any character dismisses ghost text immediately
/// 6. VoiceOver announces "AI suggestion available" when ghost text appears per AC-7
@MainActor
@Observable
public final class GhostTextCoordinator {
    /// Current phase of the ghost text session.
    public private(set) var phase: GhostTextPhase = .inactive

    /// The accumulated ghost text (grows as tokens stream in).
    public private(set) var ghostText: String = ""

    /// The cursor position where ghost text was inserted.
    public private(set) var insertionPoint: Int = 0

    /// Weak reference to the text view delegate.
    public weak var textViewDelegate: GhostTextViewDelegate?

    /// Whether ghost text is enabled in settings per AC-5.
    public var isEnabled: Bool = true

    /// The editor state for undo manager access.
    private let editorState: EditorState

    /// The typing pause timer (3 seconds per spec).
    private var pauseTimer: Task<Void, Never>?

    /// The streaming task.
    private var streamingTask: Task<Void, Never>?

    /// Typing pause duration: 3 seconds per spec.
    private let pauseDuration: UInt64 = 3_000_000_000

    /// Closure called when the pause timer fires and ghost text should be generated.
    /// Set by the composition root (EMApp) to start the EMAI service and return the stream.
    /// This keeps EMEditor decoupled from EMAI per [A-015].
    public var onRequestGhostText: ((String) -> AsyncStream<GhostTextUpdate>?)?

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "ghost-text-coordinator")

    /// Creates a ghost text coordinator.
    /// - Parameter editorState: The editor state for undo manager access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    // MARK: - Typing Pause Detection

    /// Called on every text change to reset the pause timer.
    /// Starts a new 3-second timer; if the user doesn't type again, triggers ghost text.
    public func textDidChange() {
        // Dismiss any active ghost text when user types per AC-3
        if phase == .streaming || phase == .ready {
            dismiss()
        }

        // Don't start timer if disabled
        guard isEnabled else { return }

        // Cancel existing timer
        pauseTimer?.cancel()
        pauseTimer = nil

        // Start new 3-second pause timer per AC-1
        pauseTimer = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.pauseDuration ?? 3_000_000_000)
            } catch {
                return // Cancelled
            }

            guard let self, !Task.isCancelled else { return }
            self.handlePauseTimerFired()
        }
    }

    /// Called when the pause timer fires after 3 seconds of no typing.
    private func handlePauseTimerFired() {
        guard let delegate = textViewDelegate else { return }

        // AC-4: Ghost text does not appear inside code blocks
        if delegate.isCursorInsideCodeBlock() {
            logger.debug("Cursor inside code block — skipping ghost text")
            return
        }

        let text = delegate.currentText()
        let selectedRange = delegate.currentSelectedRange()

        // Only trigger at end of text or at cursor position with no selection
        guard selectedRange.length == 0 else { return }

        // Get preceding text for context (last 500 chars)
        let cursorLocation = selectedRange.location
        guard cursorLocation > 0 else { return }

        let startIndex = max(0, cursorLocation - 500)
        let nsRange = NSRange(location: startIndex, length: cursorLocation - startIndex)
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let precedingText = String(text[swiftRange])

        // Don't generate if preceding text is empty or whitespace-only
        guard !precedingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Request ghost text from the composition root
        guard let stream = onRequestGhostText?(precedingText) else {
            logger.debug("No ghost text handler configured")
            return
        }

        startStreaming(updateStream: stream, at: cursorLocation)
    }

    // MARK: - Streaming

    /// Starts streaming ghost text from EMAI.
    /// - Parameters:
    ///   - updateStream: The `AsyncStream` of ghost text updates from EMAI.
    ///   - cursorPosition: The cursor position where ghost text will appear.
    private func startStreaming(
        updateStream: AsyncStream<GhostTextUpdate>,
        at cursorPosition: Int
    ) {
        // Cancel any existing session
        cancelStreaming()

        ghostText = ""
        insertionPoint = cursorPosition
        phase = .streaming

        streamingTask = Task { [weak self] in
            for await update in updateStream {
                guard let self, !Task.isCancelled else { break }

                switch update {
                case .token(let token):
                    self.ghostText += token
                    self.updateGhostTextVisuals()

                case .completed:
                    self.phase = .ready
                    self.announceGhostTextForVoiceOver()

                case .failed(let error):
                    self.logger.error("Ghost text generation failed: \(error.localizedDescription)")
                    self.removeGhostTextVisuals()
                    self.textViewDelegate?.requestRerender()
                    self.phase = .inactive
                    self.ghostText = ""
                }
            }
        }
    }

    // MARK: - Accept (Tab)

    /// Accepts the ghost text per AC-2.
    /// Ghost text becomes real document text. Registers a single undo group per [A-022].
    public func accept() {
        guard (phase == .ready || phase == .streaming), !ghostText.isEmpty else { return }
        guard let delegate = textViewDelegate else { return }

        let acceptedText = ghostText
        let position = insertionPoint

        // Step 1: Remove ghost text visuals
        removeGhostTextVisuals()

        // Step 2: Register undo as a single group per [A-022]
        let undoManager = editorState.undoManager
        let acceptedLength = (acceptedText as NSString).length
        let acceptedRange = NSRange(location: position, length: acceptedLength)

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { coordinator in
            guard let delegate = coordinator.textViewDelegate else { return }
            delegate.replaceText(in: acceptedRange, with: "")
            delegate.requestRerender()
        }
        undoManager.endUndoGrouping()

        // Step 3: Insert the ghost text as real text
        let insertRange = NSRange(location: position, length: 0)
        delegate.replaceText(in: insertRange, with: acceptedText)

        // Step 4: Re-render
        delegate.requestRerender()

        phase = .accepted

        // Step 5: Haptic feedback per [A-062]
        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Ghost text accepted: \(acceptedText.count) chars inserted")

        // Reset after brief delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.phase = .inactive
            self?.ghostText = ""
        }
    }

    // MARK: - Dismiss

    /// Dismisses the ghost text per AC-3.
    /// Called when the user types any character while ghost text is displayed.
    public func dismiss() {
        cancelStreaming()

        if phase == .streaming || phase == .ready {
            removeGhostTextVisuals()
            textViewDelegate?.requestRerender()
        }

        phase = .dismissed
        ghostText = ""

        logger.debug("Ghost text dismissed")

        // Reset after brief delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.phase = .inactive
        }
    }

    /// Cancels the current ghost text session without dismiss visuals.
    public func cancel() {
        cancelStreaming()
        pauseTimer?.cancel()
        pauseTimer = nil

        if phase == .streaming || phase == .ready {
            removeGhostTextVisuals()
            textViewDelegate?.requestRerender()
        }

        phase = .inactive
        ghostText = ""
    }

    // MARK: - Private

    /// Cancels the streaming task.
    private func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    /// Updates the ghost text visuals in the text storage.
    private func updateGhostTextVisuals() {
        guard let delegate = textViewDelegate,
              let storage = delegate.textStorage() else { return }

        storage.beginEditing()
        GhostTextRenderer.updateGhostText(
            in: storage,
            at: insertionPoint,
            ghostText: ghostText,
            baseFont: delegate.baseFont()
        )
        storage.endEditing()
    }

    /// Removes ghost text visuals from the text storage.
    private func removeGhostTextVisuals() {
        guard let storage = textViewDelegate?.textStorage() else { return }

        storage.beginEditing()
        GhostTextRenderer.removeGhostText(from: storage)
        storage.endEditing()
    }

    /// Announces ghost text availability for VoiceOver per AC-7.
    private func announceGhostTextForVoiceOver() {
        #if canImport(UIKit)
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString(
                "AI suggestion available. Press Tab to accept.",
                comment: "VoiceOver announcement when ghost text appears per FEAT-056 AC-7"
            )
        )
        #elseif canImport(AppKit)
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: NSLocalizedString(
                    "AI suggestion available. Press Tab to accept.",
                    comment: "VoiceOver announcement when ghost text appears per FEAT-056 AC-7"
                ),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        #endif
    }
}
