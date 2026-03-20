import Testing
import Foundation
@testable import EMEditor
@testable import EMCore

@Suite("Formatting Shortcuts per FEAT-009")
struct FormattingShortcutTests {

    // MARK: - Bold (Cmd+B)

    @Test("Bold wraps selected text with **")
    func boldWrapSelection() {
        let text = "Hello world"
        let range = NSRange(location: 6, length: 5) // "world"
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "**world**")
    }

    @Test("Bold unwraps already-wrapped text")
    func boldUnwrapSelection() {
        let text = "Hello **world**"
        let range = NSRange(location: 6, length: 9) // "**world**"
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "world")
    }

    @Test("Bold inserts paired markers with no selection")
    func boldNoSelection() {
        let text = "Hello world"
        let range = NSRange(location: 5, length: 0)
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "****")
    }

    // MARK: - Italic (Cmd+I)

    @Test("Italic wraps selected text with *")
    func italicWrapSelection() {
        let text = "Hello world"
        let range = NSRange(location: 6, length: 5) // "world"
        let mutation = inlineMarkerMutation(marker: "*", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "*world*")
    }

    @Test("Italic unwraps already-wrapped text")
    func italicUnwrapSelection() {
        let text = "Hello *world*"
        let range = NSRange(location: 6, length: 7) // "*world*"
        let mutation = inlineMarkerMutation(marker: "*", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "world")
    }

    // MARK: - Code (Cmd+Shift+K)

    @Test("Code wraps selected text with backtick")
    func codeWrapSelection() {
        let text = "Hello world"
        let range = NSRange(location: 6, length: 5)
        let mutation = inlineMarkerMutation(marker: "`", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "`world`")
    }

    @Test("Code unwraps already-wrapped text")
    func codeUnwrapSelection() {
        let text = "Hello `world`"
        let range = NSRange(location: 6, length: 7)
        let mutation = inlineMarkerMutation(marker: "`", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "world")
    }

    @Test("Code inserts paired backticks with no selection")
    func codeNoSelection() {
        let text = "Hello world"
        let range = NSRange(location: 5, length: 0)
        let mutation = inlineMarkerMutation(marker: "`", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "``")
    }

    // MARK: - Link (Cmd+K)

    @Test("Link wraps selected text as [text]()")
    func linkWrapSelection() {
        let text = "Hello world"
        let range = NSRange(location: 6, length: 5)
        let mutation = linkInsertMutation(fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "[world]()")
    }

    @Test("Link inserts []() with no selection")
    func linkNoSelection() {
        let text = "Hello world"
        let range = NSRange(location: 5, length: 0)
        let mutation = linkInsertMutation(fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "[]()")
    }

    // MARK: - Edge cases

    @Test("Works with emoji text")
    func emojiText() {
        let text = "Hello 🌍🌎🌏"
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "**Hello 🌍🌎🌏**")
    }

    @Test("Works with CJK text")
    func cjkText() {
        let text = "你好世界"
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let mutation = inlineMarkerMutation(marker: "*", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "*你好世界*")
    }

    @Test("Empty text with no selection")
    func emptyText() {
        let text = ""
        let range = NSRange(location: 0, length: 0)
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)
        #expect(mutation != nil)
        #expect(mutation?.replacement == "****")
    }

    @Test("Invalid range returns nil")
    func invalidRange() {
        let text = "Hello"
        let range = NSRange(location: 100, length: 5)
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)
        #expect(mutation == nil)
    }

    @Test("Mutation has correct range for text replacement")
    func mutationRangeCorrect() {
        let text = "Hello world"
        let range = NSRange(location: 6, length: 5) // "world"
        let mutation = inlineMarkerMutation(marker: "**", fullText: text, selectedRange: range)!
        // The mutation range should cover "world" in the original text
        let swiftRange = Range(range, in: text)!
        #expect(mutation.range == swiftRange)
    }

    @Test("Link with empty selection has bracket-pair replacement")
    func linkEmptySelectionReplacement() {
        let text = "test"
        let range = NSRange(location: 4, length: 0)
        let mutation = linkInsertMutation(fullText: text, selectedRange: range)!
        #expect(mutation.replacement == "[]()")
        // Verify result text
        let resultText = String(text[..<mutation.range.lowerBound])
            + mutation.replacement
            + String(text[mutation.range.upperBound...])
        #expect(resultText == "test[]()")
    }
}
