import Testing
import Foundation
import Markdown
@testable import EMParser

// MARK: - SPIKE-002: swift-markdown Round-Trip Fidelity Test Harness
//
// Validates that swift-markdown can:
// 1. Parse markdown and re-emit it with formatting preserved (identity round-trip)
// 2. Parse, modify specific AST nodes, and re-emit with changes applied correctly
// 3. Preserve surrounding formatting when only specific nodes are modified

@Suite("SPIKE-002: Round-Trip Fidelity")
struct RoundTripFidelityTests {

    let parser = MarkdownParser()

    // MARK: - Test Infrastructure

    /// Result of a single round-trip test case.
    struct RoundTripResult {
        let name: String
        let input: String
        let output: String
        let structuralMatch: Bool
        let textMatch: Bool
    }

    /// Parse → format → compare text and AST structure.
    /// Returns the result for aggregation.
    private func roundTrip(_ source: String, name: String = "") -> RoundTripResult {
        let firstParse = parser.parse(source)
        let formatted = firstParse.ast.format()
        let secondParse = parser.parse(formatted)

        let structuralMatch = nodesEqual(firstParse.ast.root, secondParse.ast.root)
        let textMatch = normalizeWhitespace(source) == normalizeWhitespace(formatted)

        return RoundTripResult(
            name: name,
            input: source,
            output: formatted,
            structuralMatch: structuralMatch,
            textMatch: textMatch
        )
    }

    /// Deep-compare two node trees by type and child count.
    private func nodesEqual(_ a: MarkdownNode, _ b: MarkdownNode) -> Bool {
        guard a.type == b.type, a.children.count == b.children.count else {
            return false
        }
        return zip(a.children, b.children).allSatisfy { nodesEqual($0, $1) }
    }

    /// Normalize trailing whitespace and trailing newlines for comparison.
    private func normalizeWhitespace(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - CommonMark Spec Examples — ATX Headings (§4.2)

    @Test("Spec: ATX heading levels 1-6")
    func specATXHeadings() {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            let r = roundTrip("\(prefix) Heading \(level)")
            #expect(r.structuralMatch, "ATX heading level \(level) structural mismatch")
        }
    }

    @Test("Spec: ATX heading with trailing hashes")
    func specATXTrailingHashes() {
        let r = roundTrip("## Heading ##")
        #expect(r.structuralMatch)
    }

    @Test("Spec: ATX heading with inline content")
    func specATXInlineContent() {
        let r = roundTrip("# Heading with **bold** and *italic*")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Empty ATX heading")
    func specEmptyATXHeading() {
        let r = roundTrip("#")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Setext Headings (§4.3)

    @Test("Spec: Setext heading level 1")
    func specSetextH1() {
        let r = roundTrip("Heading\n=======")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Setext heading level 2")
    func specSetextH2() {
        let r = roundTrip("Heading\n-------")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Thematic Breaks (§4.1)

    @Test("Spec: Thematic break variants", arguments: ["---", "***", "___", "- - -", "* * *"])
    func specThematicBreaks(variant: String) {
        let r = roundTrip(variant)
        #expect(r.structuralMatch, "Thematic break '\(variant)' structural mismatch")
    }

    // MARK: - CommonMark Spec — Indented Code Blocks (§4.4)

    @Test("Spec: Indented code block")
    func specIndentedCodeBlock() {
        let r = roundTrip("    code line 1\n    code line 2")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Fenced Code Blocks (§4.5)

    @Test("Spec: Fenced code block with backticks")
    func specFencedBackticks() {
        let r = roundTrip("```\ncode\n```")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Fenced code block with tildes")
    func specFencedTildes() {
        let r = roundTrip("~~~\ncode\n~~~")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Fenced code block with language info")
    func specFencedWithLang() {
        let r = roundTrip("```swift\nlet x = 42\n```")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Fenced code block preserves content exactly")
    func specFencedContentPreservation() {
        let source = "```\n  indented\n    more indented\n\ttabbed\n```"
        let result = parser.parse(source)
        let formatted = result.ast.format()
        let reparsed = parser.parse(formatted)
        let origCode = result.ast.nodes(ofType: .codeBlock(language: nil)).first?.literalText
        let rtCode = reparsed.ast.nodes(ofType: .codeBlock(language: nil)).first?.literalText
        #expect(origCode == rtCode, "Code block content changed during round-trip")
    }

    @Test("Spec: Fenced code block with empty lines")
    func specFencedEmptyLines() {
        let r = roundTrip("```\nline1\n\nline3\n```")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Paragraphs (§4.8)

    @Test("Spec: Simple paragraph")
    func specSimpleParagraph() {
        let r = roundTrip("Hello, world!")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Multi-line paragraph")
    func specMultiLineParagraph() {
        let r = roundTrip("Line one\nline two\nline three")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Multiple paragraphs")
    func specMultipleParagraphs() {
        let r = roundTrip("Paragraph one.\n\nParagraph two.\n\nParagraph three.")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Block Quotes (§5.1)

    @Test("Spec: Simple block quote")
    func specSimpleBlockQuote() {
        let r = roundTrip("> A wise quote")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Multi-line block quote")
    func specMultiLineBlockQuote() {
        let r = roundTrip("> Line 1\n> Line 2\n> Line 3")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Nested block quotes")
    func specNestedBlockQuotes() {
        let r = roundTrip("> Level 1\n>> Level 2\n>>> Level 3")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Block quote with lazy continuation")
    func specBlockQuoteLazy() {
        let r = roundTrip("> First line\nLazy continuation")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Block quote with paragraph")
    func specBlockQuoteParagraph() {
        let r = roundTrip("> First paragraph.\n>\n> Second paragraph.")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Bullet Lists (§5.3)

    @Test("Spec: Dash list items")
    func specDashList() {
        let r = roundTrip("- Item 1\n- Item 2\n- Item 3")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Asterisk list items")
    func specAsteriskList() {
        let r = roundTrip("* Item 1\n* Item 2\n* Item 3")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Plus list items")
    func specPlusList() {
        let r = roundTrip("+ Item 1\n+ Item 2\n+ Item 3")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Nested unordered lists")
    func specNestedUnorderedLists() {
        let r = roundTrip("- Item 1\n  - Nested 1\n  - Nested 2\n- Item 2")
        #expect(r.structuralMatch)
    }

    @Test("Spec: List item with multiple paragraphs")
    func specListItemMultiParagraph() {
        let r = roundTrip("- First paragraph.\n\n  Second paragraph.")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Ordered Lists (§5.3)

    @Test("Spec: Ordered list starting at 1")
    func specOrderedListFrom1() {
        let r = roundTrip("1. First\n2. Second\n3. Third")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Ordered list starting at 0")
    func specOrderedListFrom0() {
        let r = roundTrip("0. Zero\n1. One\n2. Two")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Ordered list with all same numbers")
    func specOrderedListSameNumbers() {
        let r = roundTrip("1. First\n1. Second\n1. Third")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Nested ordered lists")
    func specNestedOrderedLists() {
        let r = roundTrip("1. Item 1\n   1. Nested 1\n   2. Nested 2\n2. Item 2")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — HTML Blocks (§4.6)

    @Test("Spec: HTML block")
    func specHTMLBlock() {
        let r = roundTrip("<div>\nsome content\n</div>")
        #expect(r.structuralMatch)
    }

    @Test("Spec: HTML comment")
    func specHTMLComment() {
        let r = roundTrip("<!-- comment -->")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Link Reference Definitions (§4.7)

    @Test("Spec: Link reference definition")
    func specLinkRefDef() {
        let r = roundTrip("[foo]: /url \"title\"\n\n[foo]")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Code Spans (§6.1)

    @Test("Spec: Code span")
    func specCodeSpan() {
        let r = roundTrip("`code`")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Code span with backtick inside")
    func specCodeSpanBacktick() {
        let r = roundTrip("`` `code` ``")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Code span strips leading/trailing space")
    func specCodeSpanSpaces() {
        let r = roundTrip("` code `")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Emphasis (§6.2-6.4)

    @Test("Spec: Emphasis with asterisks")
    func specEmphasisAsterisks() {
        let r = roundTrip("*emphasis*")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Emphasis with underscores")
    func specEmphasisUnderscores() {
        let r = roundTrip("_emphasis_")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Strong emphasis with asterisks")
    func specStrongAsterisks() {
        let r = roundTrip("**strong**")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Strong emphasis with underscores")
    func specStrongUnderscores() {
        let r = roundTrip("__strong__")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Nested emphasis")
    func specNestedEmphasis() {
        let r = roundTrip("***bold and italic***")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Emphasis inside strong")
    func specEmphasisInsideStrong() {
        let r = roundTrip("**bold *and italic* here**")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Strong inside emphasis")
    func specStrongInsideEmphasis() {
        let r = roundTrip("*italic **and bold** here*")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Mid-word emphasis")
    func specMidWordEmphasis() {
        let r = roundTrip("foo*bar*baz")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Links (§6.5-6.7)

    @Test("Spec: Inline link")
    func specInlineLink() {
        let r = roundTrip("[text](url)")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Inline link with title")
    func specInlineLinkTitle() {
        let r = roundTrip("[text](url \"title\")")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Link with emphasis in label")
    func specLinkWithEmphasis() {
        let r = roundTrip("[**bold link**](url)")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Autolink")
    func specAutolink() {
        let r = roundTrip("<https://example.com>")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Reference link full")
    func specReferenceLinkFull() {
        let r = roundTrip("[foo][bar]\n\n[bar]: /url")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Images (§6.8)

    @Test("Spec: Image")
    func specImage() {
        let r = roundTrip("![alt text](image.png)")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Image with title")
    func specImageTitle() {
        let r = roundTrip("![alt](image.png \"title\")")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Hard Line Breaks (§6.9)

    @Test("Spec: Hard line break with backslash")
    func specHardBreakBackslash() {
        let r = roundTrip("Line 1\\\nLine 2")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Hard line break with two spaces")
    func specHardBreakSpaces() {
        let r = roundTrip("Line 1  \nLine 2")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Soft Line Breaks (§6.10)

    @Test("Spec: Soft line break")
    func specSoftBreak() {
        let r = roundTrip("Line 1\nLine 2")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Inline: Raw HTML (§6.11)

    @Test("Spec: Inline HTML tag")
    func specInlineHTML() {
        let r = roundTrip("This is <em>inline HTML</em>.")
        #expect(r.structuralMatch)
    }

    // MARK: - CommonMark Spec — Backslash Escapes (§6.12)

    @Test("Spec: Backslash escapes", arguments: ["\\*not emphasis\\*", "\\# not a heading", "\\[not a link\\]"])
    func specBackslashEscapes(input: String) {
        let r = roundTrip(input)
        #expect(r.structuralMatch, "Backslash escape failed: \(input)")
    }

    // MARK: - CommonMark Spec — Entities (§6.13)

    @Test("Spec: HTML entity")
    func specHTMLEntity() {
        let r = roundTrip("&copy; 2024")
        #expect(r.structuralMatch)
    }

    @Test("Spec: Numeric entity")
    func specNumericEntity() {
        let r = roundTrip("&#169; &#x00A9;")
        #expect(r.structuralMatch)
    }

    // MARK: - GFM Extensions — Strikethrough

    @Test("GFM: Strikethrough")
    func gfmStrikethrough() {
        let r = roundTrip("~~deleted text~~")
        #expect(r.structuralMatch)
    }

    @Test("GFM: Strikethrough with inline content")
    func gfmStrikethroughInline() {
        let r = roundTrip("~~deleted **bold** text~~")
        #expect(r.structuralMatch)
    }

    // MARK: - GFM Extensions — Tables

    @Test("GFM: Simple table")
    func gfmSimpleTable() {
        let r = roundTrip("| A | B |\n|---|---|\n| 1 | 2 |")
        #expect(r.structuralMatch)
    }

    @Test("GFM: Table with alignment")
    func gfmTableAlignment() {
        let r = roundTrip("| Left | Center | Right |\n|:-----|:------:|------:|\n| a    | b      | c     |")
        #expect(r.structuralMatch)
    }

    @Test("GFM: Table with inline formatting")
    func gfmTableInlineFormatting() {
        let r = roundTrip("| **Bold** | *Italic* | `Code` |\n|----------|----------|--------|\n| a        | b        | c      |")
        #expect(r.structuralMatch)
    }

    @Test("GFM: Table with many rows")
    func gfmTableManyRows() {
        var table = "| Col1 | Col2 | Col3 |\n|------|------|------|\n"
        for i in 1...10 {
            table += "| r\(i)c1 | r\(i)c2 | r\(i)c3 |\n"
        }
        let r = roundTrip(table.trimmingCharacters(in: .newlines))
        #expect(r.structuralMatch)
    }

    @Test("GFM: Table with single column")
    func gfmTableSingleColumn() {
        let r = roundTrip("| A |\n|---|\n| 1 |")
        #expect(r.structuralMatch)
    }

    // MARK: - GFM Extensions — Task Lists

    @Test("GFM: Task list unchecked")
    func gfmTaskListUnchecked() {
        let r = roundTrip("- [ ] Todo item")
        #expect(r.structuralMatch)
    }

    @Test("GFM: Task list checked")
    func gfmTaskListChecked() {
        let r = roundTrip("- [x] Done item")
        #expect(r.structuralMatch)
    }

    @Test("GFM: Mixed task list")
    func gfmMixedTaskList() {
        let r = roundTrip("- [x] Done\n- [ ] Not done\n- Regular item")
        #expect(r.structuralMatch)
    }

    // MARK: - Complex Document Round-Trips

    @Test("Complex: Mixed block elements")
    func complexMixedBlocks() {
        let r = roundTrip("""
        # Title

        A paragraph with **bold**, *italic*, and `code`.

        ## Section

        > A blockquote with *emphasis*.

        - Item 1
        - Item 2

        1. First
        2. Second

        ```python
        def hello():
            print("world")
        ```

        ---

        Final paragraph.
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Nested lists with formatting")
    func complexNestedLists() {
        let r = roundTrip("""
        - **Bold item**
          - *Nested italic*
            - `Code item`
          - [Link item](url)
        - ~~Strikethrough item~~
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Block quote with list and code")
    func complexBlockQuoteWithListAndCode() {
        let r = roundTrip("""
        > ## Heading in quote
        >
        > - Item 1
        > - Item 2
        >
        > ```
        > code in quote
        > ```
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Multiple code blocks with different languages")
    func complexMultipleCodeBlocks() {
        let r = roundTrip("""
        ```swift
        let x = 42
        ```

        ```javascript
        const y = 42;
        ```

        ```python
        z = 42
        ```

        ```
        plain code
        ```
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Document with tables and lists")
    func complexTablesAndLists() {
        let r = roundTrip("""
        # API Reference

        | Method | Path | Description |
        |--------|------|-------------|
        | GET    | /api | List items  |
        | POST   | /api | Create item |

        ## Parameters

        - `id` — The item ID
        - `name` — The item name

        1. First step
        2. Second step
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: README-like document")
    func complexReadmeLike() {
        let r = roundTrip("""
        # Project Name

        A brief description of the project.

        ## Installation

        ```bash
        npm install project-name
        ```

        ## Usage

        ```javascript
        const proj = require('project-name');
        proj.doSomething();
        ```

        ## Features

        - [x] Feature 1
        - [x] Feature 2
        - [ ] Feature 3 (planned)

        ## Contributing

        1. Fork the repo
        2. Create a branch
        3. Make changes
        4. Submit a PR

        ## License

        [MIT](LICENSE)
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Deeply nested structure")
    func complexDeeplyNested() {
        let r = roundTrip("""
        > > > Deeply nested quote
        >
        > - List in quote
        >   - Nested list
        >     - Even deeper

        - Level 1
          - Level 2
            - Level 3
              - Level 4
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Inline formatting combinations")
    func complexInlineCombinations() {
        let r = roundTrip("""
        This has **bold**, *italic*, ~~strikethrough~~, `code`, [link](url), and ![img](img.png).

        Nested: ***bold italic***, **bold with `code` inside**, *italic with [link](url)*.

        Mixed: A ~~deleted **bold**~~ and *emphasized `code`* in one line.
        """)
        #expect(r.structuralMatch)
    }

    @Test("Complex: Long paragraph with many inline elements")
    func complexLongParagraph() {
        let r = roundTrip("""
        The **quick** *brown* `fox` [jumps](url1) over the ~~lazy~~ **dog**. \
        Then the *fox* runs **fast** through the `forest` and finds a [river](url2). \
        The ~~old~~ *wise* **owl** watches from the `tree` and [flies](url3) away.
        """)
        #expect(r.structuralMatch)
    }

    // MARK: - Edge Cases

    @Test("Edge: Empty document")
    func edgeEmptyDocument() {
        let r = roundTrip("")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Only whitespace")
    func edgeOnlyWhitespace() {
        let r = roundTrip("   \n  \n   ")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Consecutive blank lines")
    func edgeConsecutiveBlankLines() {
        let r = roundTrip("Paragraph 1\n\n\n\nParagraph 2")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Unicode content")
    func edgeUnicode() {
        let r = roundTrip("# 日本語タイトル\n\nこれは**太字**の段落です。\n\n- 項目一\n- 項目二")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Emoji content")
    func edgeEmoji() {
        let r = roundTrip("# 🎉 Party\n\n🚀 **Launch** the *rocket* 🌟")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Very long heading")
    func edgeLongHeading() {
        let longTitle = String(repeating: "word ", count: 50).trimmingCharacters(in: .whitespaces)
        let r = roundTrip("# \(longTitle)")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Code block with markdown-like content")
    func edgeCodeBlockWithMarkdown() {
        let r = roundTrip("```\n# Not a heading\n**Not bold**\n- Not a list\n```")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Adjacent block elements")
    func edgeAdjacentBlocks() {
        let r = roundTrip("# Heading\n> Quote\n- List\n\nParagraph")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Link with special characters in URL")
    func edgeLinkSpecialChars() {
        let r = roundTrip("[text](https://example.com/path?q=1&r=2#frag)")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Image inside link")
    func edgeImageInLink() {
        let r = roundTrip("[![alt](img.png)](url)")
        #expect(r.structuralMatch)
    }

    @Test("Edge: Paragraph ending with inline code")
    func edgeParagraphEndingCode() {
        let r = roundTrip("Run the command `npm install`")
        #expect(r.structuralMatch)
    }

    // MARK: - AST Modification Round-Trips

    @Test("Modify: Change heading level")
    func modifyHeadingLevel() {
        let source = "# Original Heading\n\nSome paragraph text."
        let doc = Markdown.Document(parsing: source)

        // Rewrite: change heading level from 1 to 2
        var rewriter = HeadingLevelRewriter(newLevel: 2)
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        // Verify the modification was applied
        let reparsed = parser.parse(output)
        let headings = reparsed.ast.nodes(ofType: .heading(level: 2))
        #expect(headings.count == 1, "Heading should be level 2 after modification")

        // Verify paragraph is preserved
        let paragraphs = reparsed.ast.nodes(ofType: .paragraph)
        #expect(paragraphs.count == 1, "Paragraph should be preserved")
    }

    @Test("Modify: Update link URL")
    func modifyLinkURL() {
        let source = "Click [here](https://old.com) for more info.\n\nAnother paragraph."
        let doc = Markdown.Document(parsing: source)

        var rewriter = LinkURLRewriter(newURL: "https://new.com")
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        let reparsed = parser.parse(output)
        let links = reparsed.ast.nodes(ofType: .link(destination: "https://new.com"))
        #expect(links.count == 1, "Link URL should be updated")
    }

    @Test("Modify: Add emphasis to text")
    func modifyAddEmphasis() {
        let source = "Plain text here."
        let doc = Markdown.Document(parsing: source)

        var rewriter = TextToEmphasisRewriter(targetText: "Plain")
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        let reparsed = parser.parse(output)
        let emphases = reparsed.ast.nodes(ofType: .emphasis)
        #expect(emphases.count == 1, "Emphasis should be added")
    }

    @Test("Modify: Change code block language")
    func modifyCodeBlockLanguage() {
        let source = "```javascript\nconsole.log('hello');\n```\n\nSome text."
        let doc = Markdown.Document(parsing: source)

        var rewriter = CodeBlockLanguageRewriter(newLanguage: "typescript")
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        let reparsed = parser.parse(output)
        let codeBlocks = reparsed.ast.nodes(ofType: .codeBlock(language: "typescript"))
        #expect(codeBlocks.count == 1, "Code block language should be updated")
        #expect(codeBlocks.first?.literalText?.contains("console.log") == true, "Code content should be preserved")
    }

    @Test("Modify: Toggle task list checkbox")
    func modifyTaskListCheckbox() {
        let source = "- [ ] Unchecked item\n- [x] Checked item"
        let doc = Markdown.Document(parsing: source)

        var rewriter = CheckboxToggleRewriter()
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        let reparsed = parser.parse(output)
        let checked = reparsed.ast.nodes(ofType: .listItem(checkbox: .checked))
        let unchecked = reparsed.ast.nodes(ofType: .listItem(checkbox: .unchecked))
        #expect(checked.count == 1, "Previously unchecked should now be checked")
        #expect(unchecked.count == 1, "Previously checked should now be unchecked")
    }

    @Test("Modify: Rewrite paragraph text preserves surrounding blocks")
    func modifyParagraphPreservesSurroundings() {
        let source = """
        # Heading

        Old paragraph text.

        - List item 1
        - List item 2

        ```swift
        let x = 42
        ```
        """
        let doc = Markdown.Document(parsing: source)

        var rewriter = ParagraphTextRewriter(oldText: "Old paragraph text.", newText: "New paragraph text.")
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        let reparsed = parser.parse(output)

        // Verify modification
        let textNodes = reparsed.ast.nodes(ofType: .text)
        let hasNewText = textNodes.contains { $0.literalText == "New paragraph text." }
        #expect(hasNewText, "Paragraph text should be updated")

        // Verify surrounding structure is preserved
        let headings = reparsed.ast.nodes(ofType: .heading(level: 1))
        #expect(headings.count == 1, "Heading should be preserved")

        let lists = reparsed.ast.nodes(ofType: .unorderedList)
        #expect(lists.count == 1, "List should be preserved")

        let codeBlocks = reparsed.ast.nodes(ofType: .codeBlock(language: "swift"))
        #expect(codeBlocks.count == 1, "Code block should be preserved")
    }

    @Test("Modify: Add list item preserves document")
    func modifyAddListItem() {
        let source = """
        # Title

        - Item 1
        - Item 2
        """
        let doc = Markdown.Document(parsing: source)

        var rewriter = ListItemAppender(newItemText: "Item 3")
        let modified = rewriter.visit(doc) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(modified)
        let output = formatter.result

        let reparsed = parser.parse(output)
        let items = reparsed.ast.nodes(ofType: .listItem(checkbox: nil))
        #expect(items.count == 3, "Should have 3 list items after adding one")
    }

    @Test("Modify: Multiple modifications in one pass")
    func modifyMultipleChanges() {
        let source = """
        # Original Title

        Visit [old site](https://old.com).

        - [ ] Todo item
        """
        let doc = Markdown.Document(parsing: source)

        // Apply heading change
        var headingRewriter = HeadingLevelRewriter(newLevel: 2)
        let step1 = headingRewriter.visit(doc) as! Markdown.Document

        // Apply link change
        var linkRewriter = LinkURLRewriter(newURL: "https://new.com")
        let step2 = linkRewriter.visit(step1) as! Markdown.Document

        // Apply checkbox toggle
        var checkboxRewriter = CheckboxToggleRewriter()
        let step3 = checkboxRewriter.visit(step2) as! Markdown.Document

        var formatter = MarkupFormatter()
        formatter.visit(step3)
        let output = formatter.result

        let reparsed = parser.parse(output)
        #expect(reparsed.ast.nodes(ofType: .heading(level: 2)).count == 1)
        #expect(reparsed.ast.nodes(ofType: .link(destination: "https://new.com")).count == 1)
        #expect(reparsed.ast.nodes(ofType: .listItem(checkbox: .checked)).count == 1)
    }

    // MARK: - Batch Round-Trip Fidelity Assessment

    @Test("Batch: Aggregate round-trip fidelity across all CommonMark + GFM examples")
    func batchRoundTripFidelity() {
        let testCases: [(name: String, source: String)] = [
            // ATX Headings
            ("h1", "# Heading 1"),
            ("h2", "## Heading 2"),
            ("h3", "### Heading 3"),
            ("h4", "#### Heading 4"),
            ("h5", "##### Heading 5"),
            ("h6", "###### Heading 6"),
            ("h_inline", "# **Bold** heading"),
            ("h_trailing", "## Heading ##"),
            // Setext headings
            ("setext_h1", "Heading\n======="),
            ("setext_h2", "Heading\n-------"),
            // Thematic breaks
            ("hr_dash", "---"),
            ("hr_star", "***"),
            ("hr_under", "___"),
            ("hr_spaced", "- - -"),
            // Code blocks
            ("cb_backtick", "```\ncode\n```"),
            ("cb_tilde", "~~~\ncode\n~~~"),
            ("cb_lang", "```swift\nlet x = 1\n```"),
            ("cb_indent", "    indented code"),
            ("cb_empty_lines", "```\nline1\n\nline3\n```"),
            // Paragraphs
            ("para_simple", "Hello world."),
            ("para_multi", "Line 1\nLine 2"),
            ("para_two", "Para 1.\n\nPara 2."),
            // Block quotes
            ("bq_simple", "> Quote"),
            ("bq_multi", "> Line 1\n> Line 2"),
            ("bq_nested", "> L1\n>> L2\n>>> L3"),
            ("bq_para", "> Para 1.\n>\n> Para 2."),
            // Bullet lists
            ("ul_dash", "- A\n- B\n- C"),
            ("ul_star", "* A\n* B\n* C"),
            ("ul_plus", "+ A\n+ B\n+ C"),
            ("ul_nested", "- A\n  - B\n    - C"),
            // Ordered lists
            ("ol_123", "1. A\n2. B\n3. C"),
            ("ol_same", "1. A\n1. B\n1. C"),
            ("ol_nested", "1. A\n   1. B\n   2. C"),
            ("ol_start0", "0. A\n1. B"),
            // HTML
            ("html_block", "<div>\ntext\n</div>"),
            ("html_comment", "<!-- comment -->"),
            ("html_inline", "This is <em>html</em>."),
            // Code spans
            ("cs_simple", "`code`"),
            ("cs_double", "`` `code` ``"),
            // Emphasis
            ("em_star", "*emphasis*"),
            ("em_under", "_emphasis_"),
            ("strong_star", "**strong**"),
            ("strong_under", "__strong__"),
            ("em_nested", "***bold italic***"),
            ("em_in_strong", "**bold *italic* bold**"),
            ("strong_in_em", "*italic **bold** italic*"),
            // Links
            ("link_inline", "[text](url)"),
            ("link_title", "[text](url \"title\")"),
            ("link_emphasis", "[**bold**](url)"),
            ("link_auto", "<https://example.com>"),
            // Images
            ("img_simple", "![alt](img.png)"),
            ("img_title", "![alt](img.png \"title\")"),
            // Line breaks
            ("lb_backslash", "A\\\nB"),
            ("lb_spaces", "A  \nB"),
            ("lb_soft", "A\nB"),
            // Escapes
            ("esc_star", "\\*not emphasis\\*"),
            ("esc_hash", "\\# not heading"),
            ("esc_bracket", "\\[not link\\]"),
            // Entities
            ("ent_named", "&copy; 2024"),
            ("ent_numeric", "&#169;"),
            // GFM: Strikethrough
            ("gfm_strike", "~~deleted~~"),
            ("gfm_strike_inline", "~~**bold** deleted~~"),
            // GFM: Tables
            ("gfm_table_simple", "| A | B |\n|---|---|\n| 1 | 2 |"),
            ("gfm_table_align", "| L | C | R |\n|:--|:-:|--:|\n| a | b | c |"),
            ("gfm_table_format", "| **B** | *I* | `C` |\n|-------|-----|-----|\n| a     | b   | c   |"),
            ("gfm_table_single_col", "| A |\n|---|\n| 1 |"),
            // GFM: Task lists
            ("gfm_task_unchecked", "- [ ] Todo"),
            ("gfm_task_checked", "- [x] Done"),
            ("gfm_task_mixed", "- [x] Done\n- [ ] Todo\n- Regular"),
            // Complex documents
            ("complex_mixed", "# H1\n\nPara.\n\n> Quote\n\n- List\n\n```\ncode\n```\n\n---"),
            ("complex_nested", "- **Bold**\n  - *Italic*\n    - `Code`"),
            ("complex_bq_list", "> - Item 1\n> - Item 2"),
            ("complex_inline_all", "**bold** *italic* ~~strike~~ `code` [link](u) ![img](i)"),
            // Edge cases
            ("edge_empty", ""),
            ("edge_unicode", "# 日本語\n\n**太字**テスト"),
            ("edge_emoji", "# 🎉\n\n🚀 **bold**"),
            ("edge_long_heading", "# " + String(repeating: "w ", count: 40)),
            ("edge_code_markdown", "```\n# Not heading\n**Not bold**\n```"),
            ("edge_link_special", "[t](https://e.com?q=1&r=2#f)"),
            // Additional CommonMark spec coverage
            ("spec_blank_between_blocks", "# Heading\n\nParagraph\n\n> Quote"),
            ("spec_list_tight", "- A\n- B\n- C"),
            ("spec_list_loose", "- A\n\n- B\n\n- C"),
            ("spec_bq_lazy", "> Line 1\nLazy line"),
            ("spec_setext_multi", "Multi\nline\n----"),
            ("spec_indent_after_list", "- Item\n\n      code in list"),
            ("spec_link_ref", "[foo]: /url\n\n[foo]"),
            ("spec_nested_emphasis_2", "**foo *bar* baz**"),
            ("spec_backslash_in_code", "`\\*`"),
            ("spec_entity_in_code", "`&copy;`"),
            ("spec_empty_list_item", "- \n- Item"),
            ("spec_two_blank_lines", "Para 1\n\n\n\nPara 2"),
            ("spec_hr_in_list", "- Item\n\n---\n\n- Item"),
            // Additional spec coverage to exceed 100 cases
            ("spec_strong_then_em", "**bold** then *italic*"),
            ("spec_em_then_strong", "*italic* then **bold**"),
            ("spec_code_in_heading", "## Heading with `code`"),
            ("spec_link_in_heading", "## [Linked](url) heading"),
            ("spec_ol_dot_paren", "1. Dot style"),
            ("spec_nested_bq_list", "> - A\n> - B\n>   - C"),
            ("spec_image_in_para", "See ![icon](i.png) here"),
            ("spec_multi_code_span", "`a` then `b` then `c`"),
            ("spec_adjacent_strong", "**A** **B** **C**"),
            ("gfm_table_empty_cell", "| A | |\n|---|---|\n| 1 | |"),
            ("gfm_task_in_ol", "1. [ ] Todo\n2. [x] Done"),
            ("complex_full_doc", "# Title\n\n## Intro\n\nText with **bold**.\n\n- [x] Done\n- [ ] Todo\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n> Quote\n\n```swift\nlet x = 1\n```\n\n---\n\n[Link](url) and ![img](i)"),
            ("edge_only_hr", "---"),
            ("edge_only_heading", "# H"),
        ]

        var structuralPasses = 0
        var textPasses = 0
        var structuralFailures: [(name: String, input: String, output: String)] = []

        for testCase in testCases {
            let result = roundTrip(testCase.source, name: testCase.name)
            if result.structuralMatch {
                structuralPasses += 1
            } else {
                structuralFailures.append((name: testCase.name, input: testCase.source, output: result.output))
            }
            if result.textMatch {
                textPasses += 1
            }
        }

        let total = testCases.count
        let structuralRate = Double(structuralPasses) / Double(total) * 100
        let textRate = Double(textPasses) / Double(total) * 100

        // Log results for the spike report
        print("═══ SPIKE-002 BATCH RESULTS ═══")
        print("Total test cases: \(total)")
        print("Structural fidelity: \(structuralPasses)/\(total) (\(String(format: "%.1f", structuralRate))%)")
        print("Text fidelity: \(textPasses)/\(total) (\(String(format: "%.1f", textRate))%)")

        if !structuralFailures.isEmpty {
            print("\nStructural failures:")
            for failure in structuralFailures {
                print("  - \(failure.name)")
                print("    Input:  \(failure.input.prefix(80))")
                print("    Output: \(failure.output.prefix(80))")
            }
        }

        // Acceptance criteria: >95% structural fidelity
        #expect(structuralRate > 95.0, "Structural fidelity \(structuralRate)% is below 95% target")
        #expect(total >= 100, "Need at least 100 test cases, have \(total)")
    }
}

// MARK: - MarkupRewriter Implementations for AST Modification Tests

/// Rewriter that changes all heading levels to a specified level.
struct HeadingLevelRewriter: MarkupRewriter {
    let newLevel: Int

    mutating func visitHeading(_ heading: Heading) -> Markup? {
        var newHeading = heading
        newHeading.level = newLevel
        return newHeading
    }
}

/// Rewriter that changes all link URLs.
struct LinkURLRewriter: MarkupRewriter {
    let newURL: String

    mutating func visitLink(_ link: Link) -> Markup? {
        var newLink = link
        newLink.destination = newURL
        return newLink
    }
}

/// Rewriter that wraps a specific text node in emphasis.
struct TextToEmphasisRewriter: MarkupRewriter {
    let targetText: String

    mutating func visitText(_ text: Markdown.Text) -> Markup? {
        guard text.string.contains(targetText) else { return text }

        let parts = text.string.components(separatedBy: targetText)
        guard parts.count == 2 else { return text }

        return Emphasis(Markdown.Text(targetText))
    }
}

/// Rewriter that changes code block language.
struct CodeBlockLanguageRewriter: MarkupRewriter {
    let newLanguage: String

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        var newBlock = codeBlock
        newBlock.language = newLanguage
        return newBlock
    }
}

/// Rewriter that toggles all task list checkboxes.
struct CheckboxToggleRewriter: MarkupRewriter {
    mutating func visitListItem(_ listItem: ListItem) -> Markup? {
        var newItem = listItem
        switch listItem.checkbox {
        case .checked:
            newItem.checkbox = .unchecked
        case .unchecked:
            newItem.checkbox = .checked
        case .none:
            break // Leave non-task items unchanged
        }
        return newItem
    }
}

/// Rewriter that replaces specific paragraph text.
struct ParagraphTextRewriter: MarkupRewriter {
    let oldText: String
    let newText: String

    mutating func visitText(_ text: Markdown.Text) -> Markup? {
        if text.string == oldText {
            return Markdown.Text(newText)
        }
        return text
    }
}

/// Rewriter that appends a new item to unordered lists.
struct ListItemAppender: MarkupRewriter {
    let newItemText: String

    mutating func visitUnorderedList(_ list: UnorderedList) -> Markup? {
        var children = Array(list.children)
        let newItem = ListItem(Paragraph(Markdown.Text(newItemText)))
        children.append(newItem)
        return UnorderedList(children.compactMap { $0 as? ListItem })
    }
}
