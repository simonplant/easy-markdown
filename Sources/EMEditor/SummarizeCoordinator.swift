/// Coordinates the AI Summarize flow between EMAI and the popover UI per FEAT-055.
/// Handles: starting summarize, streaming tokens into the popover, insert, copy, dismiss.
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

/// The phase of a summarize session, driving popover UI state.
public enum SummarizePhase: Sendable, Equatable {
    /// No summarize session active.
    case inactive
    /// AI is streaming the summary.
    case streaming
    /// Summary generation complete — user can insert, copy, or dismiss.
    case ready
    /// User inserted the summary.
    case inserted
    /// User dismissed the summary.
    case dismissed
}

/// Coordinates the full AI Summarize lifecycle per FEAT-055.
///
/// Usage flow:
/// 1. User selects text and taps "Summarize"
/// 2. Coordinator streams tokens from EMAI into the summary text
/// 3. Summary appears in a popover, updating progressively
/// 4. User taps Insert → summary inserted at cursor, haptic fires
/// 5. User taps Copy → summary copied to clipboard, haptic fires
/// 6. User taps Dismiss → popover closes
@MainActor
@Observable
public final class SummarizeCoordinator {
    /// Current phase of the summarize session.
    public private(set) var phase: SummarizePhase = .inactive

    /// The accumulated summary text (grows as tokens stream in).
    public private(set) var summaryText: String = ""

    /// Whether the popover should be visible.
    public var isPopoverPresented: Bool = false

    /// The editor state for cursor position access.
    private let editorState: EditorState

    /// The streaming task.
    private var streamingTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "summarize-coordinator")

    /// Creates a summarize coordinator.
    /// - Parameter editorState: The editor state for cursor position access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    /// Starts the summarize flow.
    /// Consumes the update stream from EMAI and populates the summary progressively.
    ///
    /// - Parameter updateStream: An `AsyncStream` of summarize updates from EMAI.
    ///   The caller (EMApp composition root) starts the EMAI service and passes the
    ///   stream here — this keeps EMEditor decoupled from EMAI per [A-015].
    public func startSummarize(
        updateStream: AsyncStream<SummarizeUpdate>
    ) {
        // Cancel any existing session
        cancel()

        summaryText = ""
        phase = .streaming
        isPopoverPresented = true

        streamingTask = Task { [weak self] in
            for await update in updateStream {
                guard let self, !Task.isCancelled else { break }

                switch update {
                case .token(let token):
                    self.summaryText += token

                case .completed:
                    self.phase = .ready

                case .failed(let error):
                    self.logger.error("Summarize failed: \(error.localizedDescription)")
                    self.phase = .inactive
                    self.isPopoverPresented = false
                }
            }
        }
    }

    /// Inserts the summary at the current cursor position per AC-2.
    /// - Parameter insertAction: Closure that performs the text insertion,
    ///   provided by the composition root to avoid direct text view coupling.
    public func insert(using insertAction: (String) -> Void) {
        guard phase == .ready, !summaryText.isEmpty else { return }

        insertAction(summaryText)
        phase = .inserted
        isPopoverPresented = false

        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Summary inserted at cursor: \(self.summaryText.count) chars")

        resetAfterDelay()
    }

    /// Copies the summary to the clipboard per AC-3.
    public func copyToClipboard() {
        guard !summaryText.isEmpty else { return }

        #if canImport(UIKit)
        UIPasteboard.general.string = summaryText
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryText, forType: .string)
        #endif

        isPopoverPresented = false

        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Summary copied to clipboard: \(self.summaryText.count) chars")

        resetAfterDelay()
    }

    /// Dismisses the summary popover.
    public func dismiss() {
        streamingTask?.cancel()
        streamingTask = nil

        phase = .dismissed
        isPopoverPresented = false

        logger.debug("Summary dismissed")

        resetAfterDelay()
    }

    /// Cancels the current summarize session.
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil

        if phase == .streaming {
            phase = .inactive
        }

        isPopoverPresented = false
        summaryText = ""
    }

    // MARK: - Private

    /// Resets state after a brief delay to allow UI to settle.
    private func resetAfterDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.phase = .inactive
            self?.summaryText = ""
        }
    }
}
