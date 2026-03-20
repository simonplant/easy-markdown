import Testing
import Foundation
@testable import EMEditor
@testable import EMParser

@Suite("SpellCheckExclusionCalculator")
struct SpellCheckExclusionCalculatorTests {

    private let parser = MarkdownParser()

    /// Helper: parse markdown text and return exclusion ranges.
    private func exclusions(for text: String) -> [NSRange] {
        let result = parser.parse(text)
        return SpellCheckExclusionCalculator.exclusionRanges(
            from: result.ast,
            sourceText: text
        )
    }

    /// Helper: check that a given substring in text is covered by at least one exclusion range.
    private func isExcluded(_ substring: String, in text: String, ranges: [NSRange]) -> Bool {
        guard let substringRange = text.range(of: substring) else { return false }
        let nsRange = NSRange(substringRange, in: text)

        return ranges.contains { exclusion in
            let intersection = NSIntersectionRange(exclusion, nsRange)
            return intersection.length == nsRange.length
        }
    }

    // MARK: - Code Blocks

    @Test("Fenced code block is excluded")
    func fencedCodeBlock() {
        let text = "Hello world\n\n```swift\nlet x = 1\n```\n\nGoodbye"
        let ranges = exclusions(for: text)

        #expect(!ranges.isEmpty)
        #expect(isExcluded("let x = 1", in: text, ranges: ranges))
    }

    @Test("Code block with no language is excluded")
    func codeBlockNoLanguage() {
        let text = "Text before\n\n```\nsome code\n```\n\nText after"
        let ranges = exclusions(for: text)

        #expect(!ranges.isEmpty)
        #expect(isExcluded("some code", in: text, ranges: ranges))
    }

    @Test("Plain text is not excluded")
    func plainTextNotExcluded() {
        let text = "Hello world this is normal text"
        let ranges = exclusions(for: text)

        #expect(ranges.isEmpty)
    }

    // MARK: - Inline Code

    @Test("Inline code span is excluded")
    func inlineCode() {
        let text = "Use the `println` function here"
        let ranges = exclusions(for: text)

        #expect(!ranges.isEmpty)
        #expect(isExcluded("println", in: text, ranges: ranges))
    }

    @Test("Multiple inline code spans are excluded")
    func multipleInlineCode() {
        let text = "Use `foo` and `bar` together"
        let ranges = exclusions(for: text)

        #expect(ranges.count >= 2)
        #expect(isExcluded("foo", in: text, ranges: ranges))
        #expect(isExcluded("bar", in: text, ranges: ranges))
    }

    // MARK: - Links

    @Test("Link URL is excluded but link text is not")
    func linkURL() {
        let text = "Click [here](https://example.com) for info"
        let ranges = exclusions(for: text)

        #expect(!ranges.isEmpty)
        // The URL part should be excluded
        #expect(isExcluded("https://example.com", in: text, ranges: ranges))
    }

    // MARK: - Images

    @Test("Image node is excluded")
    func imageExcluded() {
        let text = "Look at this ![photo](./images/cat.png) nice"
        let ranges = exclusions(for: text)

        #expect(!ranges.isEmpty)
        #expect(isExcluded("./images/cat.png", in: text, ranges: ranges))
    }

    // MARK: - Mixed Content

    @Test("Mixed content excludes only code and URLs")
    func mixedContent() {
        let text = """
        # Hello World

        This is a paragraph with `inline code` and a [link](https://example.com).

        ```python
        print("hello")
        ```

        Normal text here.
        """
        let ranges = exclusions(for: text)

        // Should have exclusions for: inline code, link URL syntax, code block
        #expect(ranges.count >= 3)
        #expect(isExcluded("inline code", in: text, ranges: ranges))
        #expect(isExcluded("print(\"hello\")", in: text, ranges: ranges))
    }

    // MARK: - Empty / Edge Cases

    @Test("Empty text returns no exclusions")
    func emptyText() {
        let ranges = exclusions(for: "")
        #expect(ranges.isEmpty)
    }

    @Test("Text with no excludable elements returns empty")
    func noExcludableElements() {
        let text = "Just a simple **bold** and *italic* paragraph."
        let ranges = exclusions(for: text)
        #expect(ranges.isEmpty)
    }

    @Test("Heading text is not excluded")
    func headingNotExcluded() {
        let text = "# My Heading\n\nSome text"
        let ranges = exclusions(for: text)
        #expect(ranges.isEmpty)
    }
}
