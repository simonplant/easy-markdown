import Foundation
import Observation
import os

/// Drives Quick Open search and result ranking per F-011.
///
/// Searches recent files from RecentsManager using fuzzy matching.
/// Results are ranked by a combined score of match quality and recency.
/// Filters out stale entries (deleted/inaccessible files) per AC-3.
@MainActor
@Observable
public final class QuickOpenViewModel {
    private let recentsManager: RecentsManager
    private let logger = Logger(subsystem: "com.easymarkdown.emapp", category: "quickOpen")

    /// The current search query text.
    public var query: String = "" {
        didSet { updateResults() }
    }

    /// Filtered and ranked results.
    public private(set) var results: [QuickOpenResult] = []

    /// Index of the currently selected result for keyboard navigation.
    public var selectedIndex: Int? = nil

    /// Whether there are no recent files at all (empty state).
    public var hasNoRecentFiles: Bool {
        recentsManager.recentItems.isEmpty
    }

    public init(recentsManager: RecentsManager) {
        self.recentsManager = recentsManager
    }

    /// Resets the query and results for a fresh invocation.
    /// Prunes stale entries once per invocation per AC-3.
    public func reset() {
        query = ""
        results = []
        selectedIndex = nil
        recentsManager.pruneStaleEntries()
    }

    // MARK: - Keyboard Navigation

    /// Moves selection up by one row, wrapping to the bottom.
    public func moveSelectionUp() {
        guard !results.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = current > 0 ? current - 1 : results.count - 1
        } else {
            selectedIndex = results.count - 1
        }
    }

    /// Moves selection down by one row, wrapping to the top.
    public func moveSelectionDown() {
        guard !results.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = current < results.count - 1 ? current + 1 : 0
        } else {
            selectedIndex = 0
        }
    }

    /// Returns the currently selected result, if any.
    public var selectedResult: QuickOpenResult? {
        guard let index = selectedIndex, results.indices.contains(index) else { return nil }
        return results[index]
    }

    // MARK: - Private

    private func updateResults() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            results = []
            selectedIndex = nil
            return
        }

        let items = recentsManager.recentItems
        var scored: [(item: RecentItem, matchResult: FuzzyMatchResult, combinedScore: Double)] = []

        let now = Date()

        for item in items {
            // Match against filename first, then full path
            let filenameMatch = FuzzyMatcher.match(query: trimmed, target: item.filename)
            let pathMatch = FuzzyMatcher.match(query: trimmed, target: item.urlPath)

            // Use the better match, preferring filename matches
            guard let bestMatch = bestOf(filenameMatch, pathMatch, filenameBonus: 20) else {
                continue
            }

            // Recency score: more recent = higher score. Decays over days.
            let daysSinceOpen = max(0, now.timeIntervalSince(item.lastOpenedDate) / 86400)
            let recencyScore = max(0, 100 - daysSinceOpen * 5)

            // Combined score: match quality (weighted higher) + recency
            let combinedScore = Double(bestMatch.score) * 2.0 + recencyScore

            scored.append((item: item, matchResult: bestMatch, combinedScore: combinedScore))
        }

        // Sort by combined score descending
        scored.sort { $0.combinedScore > $1.combinedScore }

        results = scored.map { entry in
            QuickOpenResult(
                recentItem: entry.item,
                matchScore: entry.combinedScore,
                matchedRanges: entry.matchResult.matchedRanges
            )
        }

        // Reset selection to first result when results change
        selectedIndex = scored.isEmpty ? nil : 0

        logger.debug("Quick Open: query='\(trimmed, privacy: .public)' results=\(self.results.count)")
    }

    /// Returns the better of two match results, applying a bonus to the filename match.
    private func bestOf(
        _ filenameMatch: FuzzyMatchResult?,
        _ pathMatch: FuzzyMatchResult?,
        filenameBonus: Int
    ) -> FuzzyMatchResult? {
        switch (filenameMatch, pathMatch) {
        case let (.some(fn), .some(path)):
            let adjustedFilenameScore = fn.score + filenameBonus
            return adjustedFilenameScore >= path.score ? fn : path
        case let (.some(fn), .none):
            return fn
        case let (.none, .some(path)):
            return path
        case (.none, .none):
            return nil
        }
    }
}

/// A single Quick Open search result.
public struct QuickOpenResult: Identifiable, Sendable {
    /// The underlying recent file entry.
    public let recentItem: RecentItem

    /// Combined match + recency score.
    public let matchScore: Double

    /// Character ranges in the filename/path that matched the query.
    public let matchedRanges: [Range<String.Index>]

    public var id: UUID { recentItem.id }
}
