import Testing
import Foundation
@testable import EMParser

@Suite("MarkdownParser")
struct MarkdownParserTests {

    let parser = MarkdownParser()

    // MARK: - Basic Parsing

    @Test("Parses empty document without crashing")
    func emptyDocument() {
        let result = parser.parse("")
        #expect(result.ast.root.type == .document)
        #expect(result.ast.blocks.isEmpty)
    }

    @Test("Parses single paragraph")
    func singleParagraph() {
        let result = parser.parse("Hello, world!")
        #expect(result.ast.blocks.count == 1)
        #expect(result.ast.blocks[0].type == .paragraph)
    }

    @Test("Reports correct line count")
    func lineCount() {
        let text = "Line 1\nLine 2\nLine 3"
        let result = parser.parse(text)
        #expect(result.lineCount == 3)
    }

    @Test("Tracks parse duration")
    func parseDuration() {
        let result = parser.parse("# Hello")
        #expect(result.parseDuration >= 0)
    }

    @Test("Retains source text")
    func retainsSource() {
        let source = "Some **bold** text"
        let result = parser.parse(source)
        #expect(result.sourceText == source)
    }

    // MARK: - Headings

    @Test("Parses ATX headings levels 1-6", arguments: 1...6)
    func atxHeadings(level: Int) {
        let prefix = String(repeating: "#", count: level)
        let result = parser.parse("\(prefix) Heading \(level)")
        let headings = result.ast.nodes(ofType: .heading(level: level))
        #expect(headings.count == 1)
    }

    // MARK: - Inline Elements

    @Test("Parses bold text")
    func boldText() {
        let result = parser.parse("**bold**")
        let nodes = result.ast.nodes(ofType: .strong)
        #expect(nodes.count == 1)
    }

    @Test("Parses italic text")
    func italicText() {
        let result = parser.parse("*italic*")
        let nodes = result.ast.nodes(ofType: .emphasis)
        #expect(nodes.count == 1)
    }

    @Test("Parses strikethrough")
    func strikethrough() {
        let result = parser.parse("~~deleted~~")
        let nodes = result.ast.nodes(ofType: .strikethrough)
        #expect(nodes.count == 1)
    }

    @Test("Parses inline code")
    func inlineCode() {
        let result = parser.parse("`code`")
        let nodes = result.ast.nodes(ofType: .inlineCode)
        #expect(nodes.count == 1)
        #expect(nodes[0].literalText == "code")
    }

    @Test("Parses link")
    func link() {
        let result = parser.parse("[text](https://example.com)")
        let nodes = result.ast.nodes(ofType: .link(destination: "https://example.com"))
        #expect(nodes.count == 1)
    }

    @Test("Parses image")
    func image() {
        let result = parser.parse("![alt](image.png)")
        let nodes = result.ast.nodes(ofType: .image(source: "image.png"))
        #expect(nodes.count == 1)
    }

    // MARK: - Block Elements

    @Test("Parses fenced code block with language")
    func fencedCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let result = parser.parse(md)
        let nodes = result.ast.nodes(ofType: .codeBlock(language: "swift"))
        #expect(nodes.count == 1)
        #expect(nodes[0].literalText == "let x = 1\n")
    }

    @Test("Parses fenced code block without language")
    func fencedCodeBlockNoLang() {
        let md = "```\nsome code\n```"
        let result = parser.parse(md)
        let nodes = result.ast.nodes(ofType: .codeBlock(language: nil))
        #expect(nodes.count == 1)
    }

    @Test("Parses blockquote")
    func blockquote() {
        let result = parser.parse("> A quote")
        let nodes = result.ast.nodes(ofType: .blockQuote)
        #expect(nodes.count == 1)
    }

    @Test("Parses unordered list")
    func unorderedList() {
        let md = "- Item 1\n- Item 2\n- Item 3"
        let result = parser.parse(md)
        let lists = result.ast.nodes(ofType: .unorderedList)
        #expect(lists.count == 1)
        let items = result.ast.nodes(ofType: .listItem(checkbox: nil))
        #expect(items.count == 3)
    }

    @Test("Parses ordered list")
    func orderedList() {
        let md = "1. First\n2. Second\n3. Third"
        let result = parser.parse(md)
        let lists = result.ast.nodes(ofType: .orderedList)
        #expect(lists.count == 1)
    }

    @Test("Parses thematic break")
    func thematicBreak() {
        let result = parser.parse("---")
        let nodes = result.ast.nodes(ofType: .thematicBreak)
        #expect(nodes.count == 1)
    }

    @Test("Parses table")
    func table() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let result = parser.parse(md)
        let tables = result.ast.nodes(ofType: .table)
        #expect(tables.count == 1)
    }

    // MARK: - Task Lists

    @Test("Parses task list with checked and unchecked items")
    func taskList() {
        let md = "- [ ] Unchecked\n- [x] Checked\n- Regular item"
        let result = parser.parse(md)
        let unchecked = result.ast.nodes(ofType: .listItem(checkbox: .unchecked))
        let checked = result.ast.nodes(ofType: .listItem(checkbox: .checked))
        let regular = result.ast.nodes(ofType: .listItem(checkbox: nil))
        #expect(unchecked.count == 1)
        #expect(checked.count == 1)
        #expect(regular.count == 1)
    }

    // MARK: - Malformed Markdown

    @Test("Handles unclosed emphasis gracefully")
    func unclosedEmphasis() {
        let result = parser.parse("**unclosed bold")
        // Should parse without crashing; produces a partial AST
        #expect(result.ast.root.type == .document)
        #expect(result.ast.blocks.count >= 1)
    }

    @Test("Handles deeply nested lists")
    func deeplyNestedList() {
        var md = ""
        for i in 0..<20 {
            md += String(repeating: "  ", count: i) + "- Item \(i)\n"
        }
        let result = parser.parse(md)
        #expect(result.ast.root.type == .document)
    }

    @Test("Handles binary-like content without crashing")
    func binaryContent() {
        let junk = String(repeating: "\u{FFFD}", count: 100)
        let result = parser.parse(junk)
        #expect(result.ast.root.type == .document)
    }
}
