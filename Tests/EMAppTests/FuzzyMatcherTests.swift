import Testing
import Foundation
@testable import EMApp

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    @Test("Empty query matches everything with score 0")
    func emptyQuery() {
        let result = FuzzyMatcher.match(query: "", target: "hello.md")
        #expect(result != nil)
        #expect(result!.score == 0)
    }

    @Test("Empty target returns nil")
    func emptyTarget() {
        let result = FuzzyMatcher.match(query: "abc", target: "")
        #expect(result == nil)
    }

    @Test("Exact match scores highly")
    func exactMatch() {
        let result = FuzzyMatcher.match(query: "hello", target: "hello")
        #expect(result != nil)
        #expect(result!.score > 0)
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        let result = FuzzyMatcher.match(query: "README", target: "readme.md")
        #expect(result != nil)
        #expect(result!.score > 0)
    }

    @Test("Non-matching query returns nil")
    func noMatch() {
        let result = FuzzyMatcher.match(query: "xyz", target: "hello.md")
        #expect(result == nil)
    }

    @Test("Partial match with characters in order")
    func partialMatch() {
        let result = FuzzyMatcher.match(query: "hmd", target: "hello.md")
        #expect(result != nil)
        #expect(result!.score > 0)
    }

    @Test("Characters must appear in order")
    func orderMatters() {
        let result = FuzzyMatcher.match(query: "ba", target: "abc")
        #expect(result == nil)
    }

    @Test("Prefix match scores higher than mid-string match")
    func prefixBonus() {
        let prefixResult = FuzzyMatcher.match(query: "re", target: "readme.md")
        let midResult = FuzzyMatcher.match(query: "re", target: "before.md")
        #expect(prefixResult != nil)
        #expect(midResult != nil)
        #expect(prefixResult!.score > midResult!.score)
    }

    @Test("Consecutive matches score higher than scattered matches")
    func consecutiveBonus() {
        let consecutive = FuzzyMatcher.match(query: "read", target: "readme.md")
        let scattered = FuzzyMatcher.match(query: "read", target: "r_e_a_d.md")
        #expect(consecutive != nil)
        #expect(scattered != nil)
        #expect(consecutive!.score > scattered!.score)
    }

    @Test("Word boundary matches score higher")
    func wordBoundaryBonus() {
        let boundary = FuzzyMatcher.match(query: "qo", target: "quick-open.swift")
        #expect(boundary != nil)
        // q at start (boundary), o after - (boundary) — both get bonus
        #expect(boundary!.score > 0)
    }

    @Test("Matched ranges are returned correctly for consecutive characters")
    func matchedRangesConsecutive() {
        let result = FuzzyMatcher.match(query: "hel", target: "hello.md")
        #expect(result != nil)
        #expect(result!.matchedRanges.count == 1) // All consecutive → single range
    }

    @Test("Matched ranges are returned correctly for scattered characters")
    func matchedRangesScattered() {
        let result = FuzzyMatcher.match(query: "hm", target: "hello.md")
        #expect(result != nil)
        // h and m are not consecutive → two ranges
        #expect(result!.matchedRanges.count == 2)
    }

    @Test("Shorter target scores higher for same query")
    func shorterTargetPreferred() {
        let short = FuzzyMatcher.match(query: "rm", target: "readme.md")
        let long = FuzzyMatcher.match(query: "rm", target: "really-long-readme-file.md")
        #expect(short != nil)
        #expect(long != nil)
        #expect(short!.score > long!.score)
    }

    @Test("Fuzzy match works with path separators")
    func pathMatch() {
        let result = FuzzyMatcher.match(query: "src", target: "/Users/dev/src/main.swift")
        #expect(result != nil)
        #expect(result!.score > 0)
    }
}
