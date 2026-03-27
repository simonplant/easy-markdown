import Foundation

/// Result of a fuzzy match attempt, containing score and matched ranges.
public struct FuzzyMatchResult: Sendable {
    /// Overall match score. Higher is better. Zero means no match.
    public let score: Int

    /// Ranges in the target string that matched the query characters.
    public let matchedRanges: [Range<String.Index>]
}

/// Fuzzy string matcher for Quick Open per F-011.
///
/// Matches query characters in order against a target string.
/// Scores reward consecutive matches, word-boundary matches, and prefix matches.
/// Designed for matching filenames and paths.
public enum FuzzyMatcher {

    /// Attempts a fuzzy match of `query` against `target`.
    ///
    /// Characters in the query must appear in order in the target, but need not be adjacent.
    /// Returns nil if the query cannot be matched at all.
    /// - Parameters:
    ///   - query: The user's search string (lowercased internally).
    ///   - target: The string to match against (lowercased internally).
    /// - Returns: A `FuzzyMatchResult` with the score and matched ranges, or nil if no match.
    public static func match(query: String, target: String) -> FuzzyMatchResult? {
        guard !query.isEmpty else { return FuzzyMatchResult(score: 0, matchedRanges: []) }
        guard !target.isEmpty else { return nil }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        let queryChars = Array(queryLower)
        let targetChars = Array(targetLower)

        // Find the best match using a greedy forward scan with scoring
        var score = 0
        var queryIndex = 0
        var matchedIndices: [Int] = []
        var previousMatchIndex = -1

        for (targetIndex, targetChar) in targetChars.enumerated() {
            guard queryIndex < queryChars.count else { break }

            if targetChar == queryChars[queryIndex] {
                matchedIndices.append(targetIndex)

                // Base score per character match
                var charScore = 1

                // Consecutive match bonus
                if targetIndex == previousMatchIndex + 1 {
                    charScore += 5
                }

                // Word boundary bonus (start of string, after separator)
                if targetIndex == 0 || isSeparator(targetChars[targetIndex - 1]) {
                    charScore += 10
                }

                // Camel case boundary bonus
                if targetIndex > 0 && target[target.index(target.startIndex, offsetBy: targetIndex)].isUppercase
                    && target[target.index(target.startIndex, offsetBy: targetIndex - 1)].isLowercase {
                    charScore += 8
                }

                // Prefix bonus — first character of query matches first character of target
                if targetIndex == 0 && queryIndex == 0 {
                    charScore += 15
                }

                score += charScore
                previousMatchIndex = targetIndex
                queryIndex += 1
            }
        }

        // All query characters must match
        guard queryIndex == queryChars.count else { return nil }

        // Penalize longer targets (prefer shorter, more specific matches).
        // Cap the penalty so weak matches remain distinguishable instead of all clamping to 1.
        let lengthPenalty = max(0, targetChars.count - queryChars.count)
        let cappedPenalty = min(lengthPenalty / 3, score / 2)
        score = max(1, score - cappedPenalty)

        // Build matched ranges from indices
        let ranges = buildRanges(matchedIndices: matchedIndices, in: target)

        return FuzzyMatchResult(score: score, matchedRanges: ranges)
    }

    // MARK: - Private

    private static func isSeparator(_ char: Character) -> Bool {
        char == "/" || char == "\\" || char == "." || char == "-" || char == "_" || char == " "
    }

    private static func buildRanges(matchedIndices: [Int], in string: String) -> [Range<String.Index>] {
        guard !matchedIndices.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var rangeStart = matchedIndices[0]
        var rangeEnd = matchedIndices[0]

        for i in 1..<matchedIndices.count {
            if matchedIndices[i] == rangeEnd + 1 {
                rangeEnd = matchedIndices[i]
            } else {
                let start = string.index(string.startIndex, offsetBy: rangeStart)
                let end = string.index(string.startIndex, offsetBy: rangeEnd + 1)
                ranges.append(start..<end)
                rangeStart = matchedIndices[i]
                rangeEnd = matchedIndices[i]
            }
        }

        let start = string.index(string.startIndex, offsetBy: rangeStart)
        let end = string.index(string.startIndex, offsetBy: rangeEnd + 1)
        ranges.append(start..<end)

        return ranges
    }
}
