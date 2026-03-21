/// Search and replace engine for the find bar per FEAT-017.
/// Handles plain text and regex search, case sensitivity,
/// single replacement, and replace-all operations.
/// All operations are pure functions on String — no UIKit/AppKit dependency.

import Foundation
import os

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "findreplace")

/// Engine that performs find and replace operations on document text per FEAT-017.
public struct FindReplaceEngine: Sendable {

    public init() {}

    /// Finds all matches for the given query in the text.
    ///
    /// - Parameters:
    ///   - query: The search string.
    ///   - text: The document text to search.
    ///   - mode: Plain text or regex search mode.
    ///   - caseSensitive: Whether the search is case-sensitive.
    /// - Returns: A result containing matches or an error message for invalid regex.
    public func findMatches(
        query: String,
        in text: String,
        mode: FindMode,
        caseSensitive: Bool
    ) -> FindResult {
        guard !query.isEmpty else {
            return FindResult(matches: [], errorMessage: nil)
        }

        switch mode {
        case .plainText:
            return findPlainText(query: query, in: text, caseSensitive: caseSensitive)
        case .regex:
            return findRegex(pattern: query, in: text, caseSensitive: caseSensitive)
        }
    }

    /// Replaces the match at the given index and returns the new text.
    ///
    /// - Parameters:
    ///   - index: Index of the match to replace in the matches array.
    ///   - matches: Current list of matches.
    ///   - replacement: The replacement text.
    ///   - text: The document text.
    ///   - mode: Search mode (affects regex backreference expansion).
    ///   - query: Original search query (needed for regex replacement).
    ///   - caseSensitive: Case sensitivity setting.
    /// - Returns: The modified text after replacement, or nil if index is invalid.
    public func replaceOne(
        at index: Int,
        matches: [FindMatch],
        replacement: String,
        in text: String,
        mode: FindMode,
        query: String,
        caseSensitive: Bool
    ) -> String? {
        guard index >= 0, index < matches.count else { return nil }
        let match = matches[index]
        guard match.range.lowerBound >= text.startIndex,
              match.range.upperBound <= text.endIndex else { return nil }

        var result = text
        let expandedReplacement: String
        if mode == .regex {
            expandedReplacement = expandRegexReplacement(
                replacement: replacement,
                matchedText: String(text[match.range]),
                pattern: query,
                caseSensitive: caseSensitive
            )
        } else {
            expandedReplacement = replacement
        }
        result.replaceSubrange(match.range, with: expandedReplacement)
        return result
    }

    /// Replaces all matches and returns the new text.
    /// Builds the result in a single forward pass over the original text
    /// to avoid invalidating String.Index values.
    ///
    /// - Parameters:
    ///   - matches: All current matches (must be in document order).
    ///   - replacement: The replacement text.
    ///   - text: The document text.
    ///   - mode: Search mode.
    ///   - query: Original search query.
    ///   - caseSensitive: Case sensitivity setting.
    /// - Returns: The modified text after all replacements.
    public func replaceAll(
        matches: [FindMatch],
        replacement: String,
        in text: String,
        mode: FindMode,
        query: String,
        caseSensitive: Bool
    ) -> String {
        guard !matches.isEmpty else { return text }

        var parts: [String] = []
        var lastEnd = text.startIndex

        for match in matches {
            guard match.range.lowerBound >= lastEnd,
                  match.range.upperBound <= text.endIndex else { continue }

            // Append text before this match
            parts.append(String(text[lastEnd..<match.range.lowerBound]))

            // Append expanded replacement
            let expandedReplacement: String
            if mode == .regex {
                expandedReplacement = expandRegexReplacement(
                    replacement: replacement,
                    matchedText: String(text[match.range]),
                    pattern: query,
                    caseSensitive: caseSensitive
                )
            } else {
                expandedReplacement = replacement
            }
            parts.append(expandedReplacement)
            lastEnd = match.range.upperBound
        }

        // Append remaining text after last match
        parts.append(String(text[lastEnd..<text.endIndex]))
        return parts.joined()
    }

    // MARK: - Private

    private func findPlainText(
        query: String,
        in text: String,
        caseSensitive: Bool
    ) -> FindResult {
        var matches: [FindMatch] = []
        let options: String.CompareOptions = caseSensitive ? .literal : [.literal, .caseInsensitive]
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            guard let range = text.range(of: query, options: options, range: searchStart..<text.endIndex) else {
                break
            }
            matches.append(FindMatch(range: range))
            // Advance past this match to find non-overlapping matches
            searchStart = range.upperBound
            if searchStart == range.lowerBound {
                // Zero-length match safety (shouldn't happen with plain text)
                guard searchStart < text.endIndex else { break }
                searchStart = text.index(after: searchStart)
            }
        }
        return FindResult(matches: matches, errorMessage: nil)
    }

    private func findRegex(
        pattern: String,
        in text: String,
        caseSensitive: Bool
    ) -> FindResult {
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            let message = Self.userFriendlyRegexError(error)
            logger.info("Invalid regex pattern: \(pattern, privacy: .public) — \(message)")
            return FindResult(matches: [], errorMessage: message)
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsResults = regex.matches(in: text, range: nsRange)

        var matches: [FindMatch] = []
        for nsResult in nsResults {
            guard let range = Range(nsResult.range, in: text) else { continue }
            // Skip zero-length matches to avoid infinite loops
            if range.isEmpty { continue }
            matches.append(FindMatch(range: range))
        }

        return FindResult(matches: matches, errorMessage: nil)
    }

    /// Expands regex backreferences ($0, $1, etc.) in the replacement string.
    private func expandRegexReplacement(
        replacement: String,
        matchedText: String,
        pattern: String,
        caseSensitive: Bool
    ) -> String {
        var options: NSRegularExpression.Options = []
        if !caseSensitive { options.insert(.caseInsensitive) }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return replacement
        }

        let nsRange = NSRange(matchedText.startIndex..<matchedText.endIndex, in: matchedText)
        // Use NSRegularExpression's built-in template replacement
        guard let match = regex.firstMatch(in: matchedText, range: nsRange) else {
            return replacement
        }
        return regex.replacementString(
            for: match,
            in: matchedText,
            offset: 0,
            template: replacement
        )
    }

    /// Converts an NSRegularExpression error into a user-friendly message.
    static func userFriendlyRegexError(_ error: Error) -> String {
        let description = error.localizedDescription
        // NSRegularExpression errors are reasonably descriptive already
        if description.contains("pattern") {
            return description
        }
        return "Invalid regular expression"
    }
}

/// Result of a find operation.
public struct FindResult: Sendable {
    /// Matches found in the document.
    public let matches: [FindMatch]
    /// Error message if the query was invalid (e.g. bad regex). Nil on success.
    public let errorMessage: String?
}
