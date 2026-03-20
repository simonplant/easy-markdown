/// Word count and document statistics computation per [A-055] and FEAT-012.
///
/// Uses `NLTokenizer` for language-aware word segmentation (handles CJK text
/// correctly without relying on space-delimited splitting). Provides both
/// full-document stats and selection-scoped stats.
///
/// Performance contract: incremental per-keystroke updates must complete in <1ms.

import Foundation
import NaturalLanguage

/// Aggregated document statistics.
public struct DocumentStats: Sendable, Equatable {
    /// Total word count (NLTokenizer-based, CJK-aware).
    public let wordCount: Int

    /// Total character count including spaces.
    public let characterCount: Int

    /// Character count excluding whitespace.
    public let characterCountNoSpaces: Int

    /// Estimated reading time in seconds (wordCount / 238 WPM).
    public let readingTimeSeconds: Int

    /// Number of paragraphs (non-empty lines separated by blank lines).
    public let paragraphCount: Int

    /// Number of sentences (NLTokenizer-based).
    public let sentenceCount: Int

    /// Flesch-Kincaid readability grade level. Nil for empty documents.
    public let fleschKincaidGradeLevel: Double?

    public init(
        wordCount: Int,
        characterCount: Int,
        characterCountNoSpaces: Int,
        readingTimeSeconds: Int,
        paragraphCount: Int,
        sentenceCount: Int,
        fleschKincaidGradeLevel: Double?
    ) {
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.characterCountNoSpaces = characterCountNoSpaces
        self.readingTimeSeconds = readingTimeSeconds
        self.paragraphCount = paragraphCount
        self.sentenceCount = sentenceCount
        self.fleschKincaidGradeLevel = fleschKincaidGradeLevel
    }

    /// Empty stats for initial state.
    public static let zero = DocumentStats(
        wordCount: 0,
        characterCount: 0,
        characterCountNoSpaces: 0,
        readingTimeSeconds: 0,
        paragraphCount: 0,
        sentenceCount: 0,
        fleschKincaidGradeLevel: nil
    )
}

/// Computes document statistics using NLTokenizer for language-aware segmentation.
public enum DocumentStatsCalculator {

    /// Average adult reading speed in words per minute.
    private static let wordsPerMinute = 238

    // MARK: - Full Document Stats

    /// Computes full document statistics. Suitable for background/debounced computation.
    public static func computeFullStats(for text: String) -> DocumentStats {
        guard !text.isEmpty else { return .zero }

        let wordCount = countWords(in: text)
        let characterCount = text.count
        let characterCountNoSpaces = text.filter { !$0.isWhitespace }.count
        let readingTimeSeconds = max(1, (wordCount * 60) / max(1, wordsPerMinute))
        let paragraphCount = countParagraphs(in: text)
        let sentenceCount = countSentences(in: text)
        let fleschKincaid = computeFleschKincaid(
            wordCount: wordCount,
            sentenceCount: sentenceCount,
            text: text
        )

        return DocumentStats(
            wordCount: wordCount,
            characterCount: characterCount,
            characterCountNoSpaces: characterCountNoSpaces,
            readingTimeSeconds: wordCount > 0 ? readingTimeSeconds : 0,
            paragraphCount: paragraphCount,
            sentenceCount: sentenceCount,
            fleschKincaidGradeLevel: fleschKincaid
        )
    }

    // MARK: - Selection Stats (lightweight)

    /// Computes word count for a text selection. Lightweight for per-keystroke use.
    public static func countWords(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    // MARK: - Sentence Count

    /// Counts sentences using NLTokenizer.
    public static func countSentences(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    // MARK: - Paragraph Count

    /// Counts paragraphs (groups of non-empty lines separated by blank lines).
    public static func countParagraphs(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var inParagraph = false

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                inParagraph = false
            } else if !inParagraph {
                count += 1
                inParagraph = true
            }
        }
        return count
    }

    // MARK: - Flesch-Kincaid

    /// Computes the Flesch-Kincaid Grade Level.
    /// Formula: 0.39 * (words/sentences) + 11.8 * (syllables/words) - 15.59
    private static func computeFleschKincaid(
        wordCount: Int,
        sentenceCount: Int,
        text: String
    ) -> Double? {
        guard wordCount > 0, sentenceCount > 0 else { return nil }

        let syllableCount = estimateSyllables(in: text)
        let grade = 0.39 * (Double(wordCount) / Double(sentenceCount))
            + 11.8 * (Double(syllableCount) / Double(wordCount))
            - 15.59
        return (grade * 10).rounded() / 10 // Round to 1 decimal
    }

    /// Estimates total syllable count using a simple English heuristic.
    /// Counts vowel groups, adjusting for silent-e and common patterns.
    private static func estimateSyllables(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var total = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            total += syllablesInWord(word)
            return true
        }
        return max(total, 1)
    }

    /// Estimates syllables in a single word.
    private static func syllablesInWord(_ word: String) -> Int {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var previousWasVowel = false

        for char in word {
            let isVowel = vowels.contains(char)
            if isVowel && !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }

        // Silent-e: if word ends in 'e' and has more than 1 syllable, subtract 1
        if word.hasSuffix("e") && count > 1 {
            count -= 1
        }

        return max(count, 1)
    }
}
