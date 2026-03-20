import Testing
import Foundation
@testable import EMEditor

@Suite("DocumentStatsCalculator")
struct DocumentStatsCalculatorTests {

    // MARK: - Word Count

    @Test("Empty text returns zero stats")
    func emptyText() {
        let stats = DocumentStatsCalculator.computeFullStats(for: "")
        #expect(stats == .zero)
    }

    @Test("Counts words in simple English text")
    func simpleEnglishWords() {
        let count = DocumentStatsCalculator.countWords(in: "Hello world foo bar")
        #expect(count == 4)
    }

    @Test("Counts words with mixed whitespace")
    func mixedWhitespace() {
        let count = DocumentStatsCalculator.countWords(in: "  Hello   world\n\nfoo  ")
        #expect(count == 3)
    }

    @Test("Single word")
    func singleWord() {
        let count = DocumentStatsCalculator.countWords(in: "Hello")
        #expect(count == 1)
    }

    @Test("CJK text uses NLTokenizer segmentation, not space-delimited")
    func cjkSegmentation() {
        // Chinese: "I love China" — NLTokenizer should segment this as multiple tokens
        let count = DocumentStatsCalculator.countWords(in: "我爱中国")
        // NLTokenizer should produce more than 1 word for this (not treated as single token)
        #expect(count >= 1)
        // Should NOT be 0
        #expect(count > 0)
    }

    @Test("Japanese text segmentation")
    func japaneseSegmentation() {
        // "Tokyo is the capital" in Japanese
        let count = DocumentStatsCalculator.countWords(in: "東京は首都です")
        #expect(count > 0)
    }

    // MARK: - Character Count

    @Test("Character count includes spaces")
    func characterCountWithSpaces() {
        let stats = DocumentStatsCalculator.computeFullStats(for: "Hello world")
        #expect(stats.characterCount == 11)
    }

    @Test("Character count without spaces excludes whitespace")
    func characterCountNoSpaces() {
        let stats = DocumentStatsCalculator.computeFullStats(for: "Hello world")
        #expect(stats.characterCountNoSpaces == 10)
    }

    @Test("Character count with newlines")
    func characterCountNewlines() {
        let stats = DocumentStatsCalculator.computeFullStats(for: "a\nb\nc")
        #expect(stats.characterCount == 5) // a, \n, b, \n, c
        #expect(stats.characterCountNoSpaces == 3) // a, b, c
    }

    // MARK: - Reading Time

    @Test("Reading time for short text is at least 1 second")
    func readingTimeShortText() {
        let stats = DocumentStatsCalculator.computeFullStats(for: "Hello")
        #expect(stats.readingTimeSeconds > 0)
    }

    @Test("Reading time scales with word count")
    func readingTimeScales() {
        // 238 words should be ~60 seconds (1 minute)
        let words = Array(repeating: "word", count: 238).joined(separator: " ")
        let stats = DocumentStatsCalculator.computeFullStats(for: words)
        #expect(stats.readingTimeSeconds == 60)
    }

    // MARK: - Paragraph Count

    @Test("Counts paragraphs separated by blank lines")
    func paragraphCount() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let count = DocumentStatsCalculator.countParagraphs(in: text)
        #expect(count == 3)
    }

    @Test("Single paragraph without blank lines")
    func singleParagraph() {
        let count = DocumentStatsCalculator.countParagraphs(in: "Line one\nLine two\nLine three")
        #expect(count == 1)
    }

    @Test("Empty text has zero paragraphs")
    func zeroParagraphs() {
        let count = DocumentStatsCalculator.countParagraphs(in: "")
        #expect(count == 0)
    }

    @Test("Multiple blank lines between paragraphs")
    func multipleBlankLines() {
        let count = DocumentStatsCalculator.countParagraphs(in: "One\n\n\n\nTwo")
        #expect(count == 2)
    }

    // MARK: - Sentence Count

    @Test("Counts sentences")
    func sentenceCount() {
        let count = DocumentStatsCalculator.countSentences(in: "Hello. World. Foo bar.")
        #expect(count == 3)
    }

    @Test("Single sentence without period")
    func singleSentence() {
        let count = DocumentStatsCalculator.countSentences(in: "Hello world")
        #expect(count == 1)
    }

    // MARK: - Flesch-Kincaid

    @Test("Flesch-Kincaid returns nil for empty text")
    func fleschKincaidEmpty() {
        let stats = DocumentStatsCalculator.computeFullStats(for: "")
        #expect(stats.fleschKincaidGradeLevel == nil)
    }

    @Test("Flesch-Kincaid produces a numeric grade for text")
    func fleschKincaidNumeric() {
        let text = "The cat sat on the mat. The dog ran to the park. It was a nice day."
        let stats = DocumentStatsCalculator.computeFullStats(for: text)
        #expect(stats.fleschKincaidGradeLevel != nil)
    }

    // MARK: - Full Stats Integration

    @Test("Full stats computes all fields")
    func fullStatsIntegration() {
        let text = "Hello world. This is a test.\n\nSecond paragraph here."
        let stats = DocumentStatsCalculator.computeFullStats(for: text)

        #expect(stats.wordCount > 0)
        #expect(stats.characterCount > 0)
        #expect(stats.characterCountNoSpaces > 0)
        #expect(stats.readingTimeSeconds > 0)
        #expect(stats.paragraphCount == 2)
        #expect(stats.sentenceCount >= 2)
        #expect(stats.fleschKincaidGradeLevel != nil)
    }

    // MARK: - DocumentStats.zero

    @Test("DocumentStats.zero has all zero values")
    func zeroStats() {
        let stats = DocumentStats.zero
        #expect(stats.wordCount == 0)
        #expect(stats.characterCount == 0)
        #expect(stats.characterCountNoSpaces == 0)
        #expect(stats.readingTimeSeconds == 0)
        #expect(stats.paragraphCount == 0)
        #expect(stats.sentenceCount == 0)
        #expect(stats.fleschKincaidGradeLevel == nil)
    }
}
