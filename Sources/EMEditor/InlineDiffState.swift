/// Observable state model for an inline diff preview session per FEAT-011.
/// Tracks the original text, streaming suggestion, and user actions.
/// Lives in EMEditor (supporting package per [A-050]).

import Foundation
import Observation
import EMCore

/// The phase of the inline diff preview.
public enum InlineDiffPhase: Sendable, Equatable {
    /// No diff preview active.
    case inactive
    /// AI is streaming tokens; the diff updates progressively per AC-8.
    case streaming
    /// Generation complete; waiting for user to accept or dismiss.
    case ready
    /// User accepted the suggestion per AC-6.
    case accepted
    /// User dismissed the suggestion per AC-7.
    case dismissed
}

/// Manages the state of an inline diff preview for AI Improve Writing.
/// One instance per editor scene, owned by the ImproveWritingCoordinator.
@MainActor
@Observable
public final class InlineDiffState {
    /// Current phase of the diff preview.
    public private(set) var phase: InlineDiffPhase = .inactive

    /// The original text being improved (the user's selection).
    public private(set) var originalText: String = ""

    /// The improved text accumulated so far (grows as tokens stream in).
    public private(set) var improvedText: String = ""

    /// The range of the original text in the document (NSRange for UITextView).
    public private(set) var originalRange: NSRange = NSRange(location: 0, length: 0)

    /// Whether the diff preview is currently showing.
    public var isActive: Bool {
        switch phase {
        case .streaming, .ready:
            return true
        case .inactive, .accepted, .dismissed:
            return false
        }
    }

    /// Starts a new diff session.
    /// - Parameters:
    ///   - originalText: The selected text being improved.
    ///   - range: The NSRange of the selection in the document.
    public func begin(originalText: String, range: NSRange) {
        self.originalText = originalText
        self.improvedText = ""
        self.originalRange = range
        self.phase = .streaming
    }

    /// Appends a token to the improved text (progressive streaming per AC-8).
    public func appendToken(_ token: String) {
        guard phase == .streaming else { return }
        improvedText += token
    }

    /// Marks generation as complete — user can now accept or dismiss.
    public func markReady() {
        guard phase == .streaming else { return }
        phase = .ready
    }

    /// Marks the suggestion as accepted.
    public func markAccepted() {
        phase = .accepted
    }

    /// Marks the suggestion as dismissed.
    public func markDismissed() {
        phase = .dismissed
    }

    /// Resets to inactive state.
    public func reset() {
        phase = .inactive
        originalText = ""
        improvedText = ""
        originalRange = NSRange(location: 0, length: 0)
    }
}
