import Testing
import Foundation
@testable import EMParser

@Suite("Round-Trip Formatting")
struct RoundTripTests {

    let parser = MarkdownParser()

    /// Helper: parse markdown, format back, parse again, verify same structure.
    private func verifyRoundTrip(_ source: String) {
        let firstParse = parser.parse(source)
        let formatted = firstParse.ast.format()
        let secondParse = parser.parse(formatted)

        // Compare AST structure (node types and child counts)
        assertNodesEqual(firstParse.ast.root, secondParse.ast.root)
    }

    private func assertNodesEqual(_ a: MarkdownNode, _ b: MarkdownNode) {
        #expect(a.type == b.type, "Node types differ: \(a.type) vs \(b.type)")
        #expect(
            a.children.count == b.children.count,
            "Child count differs for \(a.type): \(a.children.count) vs \(b.children.count)"
        )
        for (childA, childB) in zip(a.children, b.children) {
            assertNodesEqual(childA, childB)
        }
    }

    // MARK: - Round-Trip Cases

    @Test("Heading round-trips")
    func heading() {
        verifyRoundTrip("# Hello World")
    }

    @Test("Paragraph with inline formatting round-trips")
    func inlineFormatting() {
        verifyRoundTrip("This is **bold** and *italic* and ~~strikethrough~~ text.")
    }

    @Test("Code block round-trips")
    func codeBlock() {
        verifyRoundTrip("""
        ```swift
        let x = 42
        ```
        """)
    }

    @Test("Blockquote round-trips")
    func blockquote() {
        verifyRoundTrip("> A wise quote")
    }

    @Test("Unordered list round-trips")
    func unorderedList() {
        verifyRoundTrip("""
        - Item 1
        - Item 2
        - Item 3
        """)
    }

    @Test("Ordered list round-trips")
    func orderedList() {
        verifyRoundTrip("""
        1. First
        2. Second
        3. Third
        """)
    }

    @Test("Link round-trips")
    func link() {
        verifyRoundTrip("[Example](https://example.com)")
    }

    @Test("Image round-trips")
    func image() {
        verifyRoundTrip("![Alt text](image.png)")
    }

    @Test("Table round-trips")
    func table() {
        verifyRoundTrip("""
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """)
    }

    @Test("Thematic break round-trips")
    func thematicBreak() {
        verifyRoundTrip("---")
    }

    @Test("Complex document round-trips")
    func complexDocument() {
        verifyRoundTrip("""
        # Title

        A paragraph with **bold**, *italic*, and `code`.

        ## Lists

        - Item with [link](https://example.com)
        - Item with **bold**

        1. First
        2. Second

        > Blockquote with *emphasis*

        ```python
        def hello():
            print("world")
        ```

        ---

        | Column 1 | Column 2 |
        | --- | --- |
        | A | B |
        """)
    }

    // MARK: - Format produces valid markdown

    @Test("Formatted output parses without errors")
    func formatProducesValidMarkdown() {
        let source = """
        # Test

        **bold** and *italic*

        - list item
        """
        let result = parser.parse(source)
        let formatted = result.ast.format()
        let reparsed = parser.parse(formatted)
        #expect(reparsed.ast.root.type == .document)
        #expect(reparsed.ast.blocks.count == result.ast.blocks.count)
    }
}
