import Testing
import Foundation
@testable import EMCore

@Suite("GraphemeClusterHelper")
struct GraphemeClusterHelperTests {

    // MARK: - Snap to Boundary

    @Test("Empty string snaps to 0")
    func emptyString() {
        let result = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: 0, in: "")
        #expect(result == 0)
    }

    @Test("ASCII text — every offset is a boundary")
    func asciiText() {
        let text = "Hello"
        for i in 0...text.utf16.count {
            let snapped = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: i, in: text)
            #expect(snapped == i)
        }
    }

    @Test("Flag emoji treated as single grapheme cluster per FEAT-051 AC-4")
    func flagEmoji() {
        // 🇯🇵 is two regional indicators: U+1F1EF U+1F1F5, each is 2 UTF-16 code units = 4 total
        let text = "A🇯🇵B"
        // A = offset 0, 🇯🇵 starts at 1, B starts at 5
        let width = GraphemeClusterHelper.graphemeClusterUTF16Width(at: 1, in: text)
        #expect(width == 4) // Flag emoji is 4 UTF-16 code units

        // Offset 2 is mid-emoji — should snap back to 1
        let snapped = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: 2, in: text)
        #expect(snapped == 1)
    }

    @Test("Skin tone emoji treated as single grapheme cluster per FEAT-051 AC-4")
    func skinToneEmoji() {
        // 👍🏽 = U+1F44D U+1F3FD (thumbs up + medium skin tone)
        let text = "👍🏽"
        #expect(text.count == 1) // Swift sees 1 grapheme cluster
        let width = GraphemeClusterHelper.graphemeClusterUTF16Width(at: 0, in: text)
        #expect(width == text.utf16.count)
    }

    @Test("ZWJ sequence treated as single grapheme cluster per FEAT-051 AC-4")
    func zwjSequenceEmoji() {
        // 👨‍👩‍👧 = family emoji (ZWJ sequence)
        let text = "👨‍👩‍👧"
        #expect(text.count == 1) // One grapheme cluster
        let width = GraphemeClusterHelper.graphemeClusterUTF16Width(at: 0, in: text)
        #expect(width == text.utf16.count)
        #expect(width > 2) // Must be multi-codepoint
    }

    // MARK: - CJK Characters (AC-1)

    @Test("CJK characters are each a grapheme cluster boundary")
    func cjkCharacterBoundaries() {
        // 你好世界 — 4 CJK characters, each 1 UTF-16 code unit
        let text = "你好世界"
        #expect(text.utf16.count == 4)
        for i in 0...text.utf16.count {
            #expect(GraphemeClusterHelper.isGraphemeClusterBoundary(utf16Offset: i, in: text))
        }
    }

    @Test("Japanese hiragana characters are individual boundaries")
    func hiraganaCharacterBoundaries() {
        let text = "こんにちは"
        #expect(text.utf16.count == 5)
        for i in 0...text.utf16.count {
            #expect(GraphemeClusterHelper.isGraphemeClusterBoundary(utf16Offset: i, in: text))
        }
    }

    @Test("Korean Hangul syllables are individual boundaries")
    func hangulBoundaries() {
        let text = "안녕하세요"
        #expect(text.utf16.count == 5)
        for i in 0...text.utf16.count {
            #expect(GraphemeClusterHelper.isGraphemeClusterBoundary(utf16Offset: i, in: text))
        }
    }

    // MARK: - RTL Text (AC-2)

    @Test("Arabic text has correct grapheme cluster boundaries")
    func arabicText() {
        // مرحبا = "hello" in Arabic, 5 characters
        let text = "مرحبا"
        for i in 0...text.utf16.count {
            let snapped = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: i, in: text)
            #expect(snapped == i)
        }
    }

    @Test("Hebrew text has correct grapheme cluster boundaries")
    func hebrewText() {
        // שלום = "hello" in Hebrew
        let text = "שלום"
        for i in 0...text.utf16.count {
            let snapped = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: i, in: text)
            #expect(snapped == i)
        }
    }

    // MARK: - Mixed Script Text (AC-3)

    @Test("Mixed LTR and RTL text preserves boundaries")
    func mixedLTRRTL() {
        // "Hello مرحبا World"
        let text = "Hello مرحبا World"
        // Every character should be on a boundary (no multi-codepoint sequences)
        var offset = 0
        for _ in text {
            #expect(GraphemeClusterHelper.isGraphemeClusterBoundary(utf16Offset: offset, in: text))
            offset += 1
        }
    }

    // MARK: - Accented Characters

    @Test("Precomposed accented characters are single clusters")
    func precomposedAccent() {
        // é (precomposed U+00E9) — single UTF-16 code unit
        let text = "café"
        #expect(text.count == 4) // 4 grapheme clusters
        #expect(text.utf16.count == 4)
    }

    @Test("Combining accented characters are single clusters")
    func combiningAccent() {
        // e + combining acute accent (U+0065 U+0301)
        let text = "e\u{0301}" // "é" decomposed
        #expect(text.count == 1) // Swift sees 1 grapheme cluster
        let width = GraphemeClusterHelper.graphemeClusterUTF16Width(at: 0, in: text)
        #expect(width == 2) // 2 UTF-16 code units
        // Offset 1 is mid-cluster
        #expect(!GraphemeClusterHelper.isGraphemeClusterBoundary(utf16Offset: 1, in: text))
    }

    @Test("Devanagari conjuncts treated as single clusters")
    func devanagariConjunct() {
        // क्ष = ka + virama + ssa (3 Unicode scalars, 1 grapheme cluster)
        let text = "क्ष"
        #expect(text.count == 1)
        let width = GraphemeClusterHelper.graphemeClusterUTF16Width(at: 0, in: text)
        #expect(width == text.utf16.count)
    }

    // MARK: - Enumerate Grapheme Clusters

    @Test("Enumerating clusters over emoji produces correct offsets")
    func enumerateEmojiClusters() {
        let text = "A😀B"
        var clusters: [(String, Int, Int)] = []
        GraphemeClusterHelper.enumerateGraphemeClusters(in: text) { cluster, offset, width in
            clusters.append((cluster, offset, width))
            return true
        }
        #expect(clusters.count == 3)
        #expect(clusters[0].0 == "A")
        #expect(clusters[0].1 == 0)
        #expect(clusters[0].2 == 1)
        #expect(clusters[1].0 == "😀")
        #expect(clusters[1].1 == 1)
        #expect(clusters[1].2 == 2) // 😀 is U+1F600, 2 UTF-16 code units
        #expect(clusters[2].0 == "B")
        #expect(clusters[2].1 == 3)
        #expect(clusters[2].2 == 1)
    }

    // MARK: - Edge Cases

    @Test("Negative offset clamps to 0")
    func negativeOffset() {
        let text = "Hello"
        let snapped = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: -5, in: text)
        #expect(snapped == 0)
    }

    @Test("Offset beyond string length clamps to end")
    func beyondLength() {
        let text = "Hello"
        let snapped = GraphemeClusterHelper.snapToGraphemeClusterBoundary(utf16Offset: 100, in: text)
        #expect(snapped == 5)
    }

    @Test("Width at end of string returns 0")
    func widthAtEnd() {
        let text = "Hi"
        let width = GraphemeClusterHelper.graphemeClusterUTF16Width(at: 2, in: text)
        #expect(width == 0)
    }
}
