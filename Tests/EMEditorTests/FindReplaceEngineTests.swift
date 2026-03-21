import Testing
import Foundation
@testable import EMEditor

@Suite("FindReplaceEngine")
struct FindReplaceEngineTests {

    let engine = FindReplaceEngine()

    // MARK: - Plain Text Search

    @Test("Empty query returns no matches")
    func emptyQuery() {
        let result = engine.findMatches(query: "", in: "hello world", mode: .plainText, caseSensitive: false)
        #expect(result.matches.isEmpty)
        #expect(result.errorMessage == nil)
    }

    @Test("Plain text finds all occurrences")
    func plainTextMultipleMatches() {
        let text = "the cat sat on the mat"
        let result = engine.findMatches(query: "the", in: text, mode: .plainText, caseSensitive: false)
        #expect(result.matches.count == 2)
        #expect(String(text[result.matches[0].range]) == "the")
        #expect(String(text[result.matches[1].range]) == "the")
    }

    @Test("Plain text case-insensitive search")
    func plainTextCaseInsensitive() {
        let text = "Hello HELLO hello"
        let result = engine.findMatches(query: "hello", in: text, mode: .plainText, caseSensitive: false)
        #expect(result.matches.count == 3)
    }

    @Test("Plain text case-sensitive search")
    func plainTextCaseSensitive() {
        let text = "Hello HELLO hello"
        let result = engine.findMatches(query: "hello", in: text, mode: .plainText, caseSensitive: true)
        #expect(result.matches.count == 1)
        #expect(String(text[result.matches[0].range]) == "hello")
    }

    @Test("No matches returns empty array")
    func noMatches() {
        let result = engine.findMatches(query: "xyz", in: "hello world", mode: .plainText, caseSensitive: false)
        #expect(result.matches.isEmpty)
        #expect(result.errorMessage == nil)
    }

    // MARK: - Regex Search

    @Test("Regex finds pattern matches")
    func regexMatches() {
        let text = "cat123 dog456 bird789"
        let result = engine.findMatches(query: "\\d+", in: text, mode: .regex, caseSensitive: false)
        #expect(result.matches.count == 3)
        #expect(String(text[result.matches[0].range]) == "123")
        #expect(String(text[result.matches[1].range]) == "456")
        #expect(String(text[result.matches[2].range]) == "789")
    }

    @Test("Invalid regex returns error message, does not crash")
    func invalidRegex() {
        let result = engine.findMatches(query: "[invalid", in: "test", mode: .regex, caseSensitive: false)
        #expect(result.matches.isEmpty)
        #expect(result.errorMessage != nil)
    }

    @Test("Regex case-sensitive flag works")
    func regexCaseSensitive() {
        let text = "Apple apple APPLE"
        let resultInsensitive = engine.findMatches(query: "apple", in: text, mode: .regex, caseSensitive: false)
        #expect(resultInsensitive.matches.count == 3)

        let resultSensitive = engine.findMatches(query: "apple", in: text, mode: .regex, caseSensitive: true)
        #expect(resultSensitive.matches.count == 1)
    }

    @Test("Regex with groups")
    func regexGroups() {
        let text = "2024-01-15 and 2024-02-20"
        let result = engine.findMatches(query: "\\d{4}-\\d{2}-\\d{2}", in: text, mode: .regex, caseSensitive: false)
        #expect(result.matches.count == 2)
    }

    // MARK: - Replace One

    @Test("Replace one substitutes the current match")
    func replaceOne() {
        let text = "hello world hello"
        let result = engine.findMatches(query: "hello", in: text, mode: .plainText, caseSensitive: false)
        let newText = engine.replaceOne(
            at: 0, matches: result.matches, replacement: "hi",
            in: text, mode: .plainText, query: "hello", caseSensitive: false
        )
        #expect(newText == "hi world hello")
    }

    @Test("Replace one at second match")
    func replaceOneSecond() {
        let text = "cat dog cat"
        let result = engine.findMatches(query: "cat", in: text, mode: .plainText, caseSensitive: false)
        let newText = engine.replaceOne(
            at: 1, matches: result.matches, replacement: "bird",
            in: text, mode: .plainText, query: "cat", caseSensitive: false
        )
        #expect(newText == "cat dog bird")
    }

    @Test("Replace one with invalid index returns nil")
    func replaceOneInvalidIndex() {
        let text = "hello"
        let result = engine.findMatches(query: "hello", in: text, mode: .plainText, caseSensitive: false)
        let newText = engine.replaceOne(
            at: 5, matches: result.matches, replacement: "hi",
            in: text, mode: .plainText, query: "hello", caseSensitive: false
        )
        #expect(newText == nil)
    }

    // MARK: - Replace All

    @Test("Replace all substitutes every occurrence")
    func replaceAll() {
        let text = "the cat sat on the mat"
        let result = engine.findMatches(query: "the", in: text, mode: .plainText, caseSensitive: false)
        let newText = engine.replaceAll(
            matches: result.matches, replacement: "a",
            in: text, mode: .plainText, query: "the", caseSensitive: false
        )
        #expect(newText == "a cat sat on a mat")
    }

    @Test("Replace all with empty replacement deletes matches")
    func replaceAllWithEmpty() {
        let text = "a1b2c3"
        let result = engine.findMatches(query: "\\d", in: text, mode: .regex, caseSensitive: false)
        let newText = engine.replaceAll(
            matches: result.matches, replacement: "",
            in: text, mode: .regex, query: "\\d", caseSensitive: false
        )
        #expect(newText == "abc")
    }

    @Test("Replace all with no matches returns original text")
    func replaceAllNoMatches() {
        let text = "hello world"
        let newText = engine.replaceAll(
            matches: [], replacement: "x",
            in: text, mode: .plainText, query: "xyz", caseSensitive: false
        )
        #expect(newText == text)
    }

    @Test("Replace all with regex backreferences")
    func replaceAllRegexBackref() {
        let text = "John Smith, Jane Doe"
        let result = engine.findMatches(query: "(\\w+) (\\w+)", in: text, mode: .regex, caseSensitive: false)
        let newText = engine.replaceAll(
            matches: result.matches, replacement: "$2 $1",
            in: text, mode: .regex, query: "(\\w+) (\\w+)", caseSensitive: false
        )
        #expect(newText == "Smith John, Doe Jane")
    }

    // MARK: - Performance (AC: 5000-line document within 200ms)

    @Test("Search in large document completes quickly")
    func largeDocumentPerformance() {
        // Generate a 5000-line document
        let line = "The quick brown fox jumps over the lazy dog. This is line number "
        let text = (1...5000).map { "\(line)\($0)" }.joined(separator: "\n")

        let start = ContinuousClock.now
        let result = engine.findMatches(query: "fox", in: text, mode: .plainText, caseSensitive: false)
        let elapsed = ContinuousClock.now - start

        #expect(result.matches.count == 5000)
        // Must complete within 200ms per AC-4
        #expect(elapsed < .milliseconds(200), "Search took \(elapsed), exceeds 200ms target")
    }

    @Test("Regex search in large document completes quickly")
    func largeDocumentRegexPerformance() {
        let line = "The quick brown fox jumps over the lazy dog. This is line number "
        let text = (1...5000).map { "\(line)\($0)" }.joined(separator: "\n")

        let start = ContinuousClock.now
        let result = engine.findMatches(query: "\\bfox\\b", in: text, mode: .regex, caseSensitive: false)
        let elapsed = ContinuousClock.now - start

        #expect(result.matches.count == 5000)
        #expect(elapsed < .milliseconds(200), "Regex search took \(elapsed), exceeds 200ms target")
    }

    // MARK: - Edge Cases

    @Test("Search with special regex characters in plain text mode")
    func specialCharsPlainText() {
        let text = "price is $10.00 (USD)"
        let result = engine.findMatches(query: "$10.00", in: text, mode: .plainText, caseSensitive: false)
        #expect(result.matches.count == 1)
        #expect(String(text[result.matches[0].range]) == "$10.00")
    }

    @Test("Search in empty text")
    func emptyText() {
        let result = engine.findMatches(query: "hello", in: "", mode: .plainText, caseSensitive: false)
        #expect(result.matches.isEmpty)
    }

    @Test("Unicode text search")
    func unicodeSearch() {
        let text = "café résumé café"
        let result = engine.findMatches(query: "café", in: text, mode: .plainText, caseSensitive: false)
        #expect(result.matches.count == 2)
    }

    @Test("CJK text search")
    func cjkSearch() {
        let text = "日本語のテキスト。日本語を検索する。"
        let result = engine.findMatches(query: "日本語", in: text, mode: .plainText, caseSensitive: false)
        #expect(result.matches.count == 2)
    }

    @Test("Emoji search")
    func emojiSearch() {
        let text = "Hello 👋 World 👋 Test"
        let result = engine.findMatches(query: "👋", in: text, mode: .plainText, caseSensitive: false)
        #expect(result.matches.count == 2)
    }
}

@MainActor
@Suite("FindReplaceState")
struct FindReplaceStateTests {

    @Test("Initial state is clean")
    func initialState() {
        let state = FindReplaceState()
        #expect(state.isVisible == false)
        #expect(state.searchQuery == "")
        #expect(state.replaceText == "")
        #expect(state.mode == .plainText)
        #expect(state.isCaseSensitive == false)
        #expect(state.matches.isEmpty)
        #expect(state.currentMatchIndex == nil)
        #expect(state.errorMessage == nil)
    }

    @Test("Next match cycles through matches")
    func nextMatchCycles() {
        let state = FindReplaceState()
        let text = "aaa"
        let matches = [
            FindMatch(range: text.startIndex..<text.index(text.startIndex, offsetBy: 1)),
            FindMatch(range: text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 2)),
            FindMatch(range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex),
        ]
        state.updateMatches(matches)

        #expect(state.currentMatchIndex == 0)
        state.nextMatch()
        #expect(state.currentMatchIndex == 1)
        state.nextMatch()
        #expect(state.currentMatchIndex == 2)
        state.nextMatch()
        #expect(state.currentMatchIndex == 0) // wraps
    }

    @Test("Previous match wraps backward")
    func previousMatchWraps() {
        let state = FindReplaceState()
        let text = "ab"
        let matches = [
            FindMatch(range: text.startIndex..<text.index(text.startIndex, offsetBy: 1)),
            FindMatch(range: text.index(text.startIndex, offsetBy: 1)..<text.endIndex),
        ]
        state.updateMatches(matches)

        #expect(state.currentMatchIndex == 0)
        state.previousMatch()
        #expect(state.currentMatchIndex == 1) // wraps backward
    }

    @Test("Position label formatting")
    func positionLabel() {
        let state = FindReplaceState()
        #expect(state.positionLabel == "")

        state.searchQuery = "test"
        let text = "ab"
        let matches = [
            FindMatch(range: text.startIndex..<text.index(text.startIndex, offsetBy: 1)),
        ]
        state.updateMatches(matches)
        #expect(state.positionLabel == "1 of 1")
    }

    @Test("Reset clears all state")
    func reset() {
        let state = FindReplaceState()
        state.searchQuery = "test"
        state.replaceText = "replacement"
        let text = "a"
        state.updateMatches([FindMatch(range: text.startIndex..<text.endIndex)])

        state.reset()

        #expect(state.searchQuery == "")
        #expect(state.replaceText == "")
        #expect(state.matches.isEmpty)
        #expect(state.currentMatchIndex == nil)
    }

    @Test("No results label when query set but no matches")
    func noResultsLabel() {
        let state = FindReplaceState()
        state.searchQuery = "xyz"
        state.updateMatches([])
        #expect(state.positionLabel == "No results")
    }
}
