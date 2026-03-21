/// Observable state for the find-and-replace bar per FEAT-017.
/// Lives in EMEditor. The find bar UI in EMApp reads this state.

import Foundation

/// Search mode: plain text or regex per FEAT-017.
public enum FindMode: Sendable {
    case plainText
    case regex
}

/// A single search match with its range in the document.
public struct FindMatch: Sendable, Equatable {
    /// Range of the match in the document string.
    public let range: Range<String.Index>

    public init(range: Range<String.Index>) {
        self.range = range
    }
}

/// Per-scene find/replace state per FEAT-017.
/// Owned by EditorState, observed by the find bar UI.
@MainActor
@Observable
public final class FindReplaceState {
    /// Whether the find bar is visible.
    public var isVisible: Bool = false

    /// The search query entered by the user.
    public var searchQuery: String = ""

    /// The replacement text entered by the user.
    public var replaceText: String = ""

    /// Current search mode (plain text or regex).
    public var mode: FindMode = .plainText

    /// Whether search is case-sensitive.
    public var isCaseSensitive: Bool = false

    /// All matches in the document.
    public private(set) var matches: [FindMatch] = []

    /// Index of the currently focused match (for "next"/"previous" navigation).
    /// Nil when there are no matches.
    public private(set) var currentMatchIndex: Int?

    /// Error message for invalid regex. Nil when query is valid.
    public private(set) var errorMessage: String?

    /// Total match count for display.
    public var matchCount: Int { matches.count }

    /// Human-readable label for current position, e.g. "3 of 12".
    public var positionLabel: String {
        guard let index = currentMatchIndex, !matches.isEmpty else {
            return matchCount == 0 && !searchQuery.isEmpty ? "No results" : ""
        }
        return "\(index + 1) of \(matchCount)"
    }

    public init() {}

    /// Update matches from the engine. Resets currentMatchIndex to 0 if matches exist.
    public func updateMatches(_ newMatches: [FindMatch], errorMessage: String? = nil) {
        matches = newMatches
        self.errorMessage = errorMessage
        if newMatches.isEmpty {
            currentMatchIndex = nil
        } else if currentMatchIndex == nil || currentMatchIndex! >= newMatches.count {
            currentMatchIndex = 0
        }
    }

    /// Move to the next match, wrapping around.
    public func nextMatch() {
        guard !matches.isEmpty else { return }
        if let idx = currentMatchIndex {
            currentMatchIndex = (idx + 1) % matches.count
        } else {
            currentMatchIndex = 0
        }
    }

    /// Move to the previous match, wrapping around.
    public func previousMatch() {
        guard !matches.isEmpty else { return }
        if let idx = currentMatchIndex {
            currentMatchIndex = (idx - 1 + matches.count) % matches.count
        } else {
            currentMatchIndex = matches.count - 1
        }
    }

    /// Clear all state when the find bar is dismissed.
    public func reset() {
        searchQuery = ""
        replaceText = ""
        matches = []
        currentMatchIndex = nil
        errorMessage = nil
    }
}
