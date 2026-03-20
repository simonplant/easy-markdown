import Testing
@testable import EMParser

@Suite("SourcePosition")
struct SourcePositionTests {

    @Test("Positions are ordered by line then column")
    func ordering() {
        let a = SourcePosition(line: 1, column: 1)
        let b = SourcePosition(line: 1, column: 5)
        let c = SourcePosition(line: 2, column: 1)

        #expect(a < b)
        #expect(b < c)
        #expect(a < c)
    }

    @Test("Equal positions compare correctly")
    func equality() {
        let a = SourcePosition(line: 3, column: 7)
        let b = SourcePosition(line: 3, column: 7)
        #expect(a == b)
    }

    @Test("Description formats as line:column")
    func description() {
        let pos = SourcePosition(line: 10, column: 5)
        #expect(pos.description == "10:5")
    }

    @Test("Range description formats as start-end")
    func rangeDescription() {
        let range = SourceRange(
            start: SourcePosition(line: 1, column: 1),
            end: SourcePosition(line: 3, column: 10)
        )
        #expect(range.description == "1:1-3:10")
    }

    // MARK: - Source Positions on AST Nodes

    @Test("Heading node has source range")
    func headingSourceRange() {
        let parser = MarkdownParser()
        let result = parser.parse("# Hello")
        let headings = result.ast.nodes(ofType: .heading(level: 1))
        #expect(headings.count == 1)
        let range = headings[0].range
        #expect(range != nil)
        #expect(range?.start.line == 1)
        #expect(range?.start.column == 1)
    }

    @Test("Multi-line document nodes have correct line ranges")
    func multiLineRanges() {
        let md = """
        # Title

        Paragraph text.

        ## Subtitle
        """
        let parser = MarkdownParser()
        let result = parser.parse(md)

        let h1 = result.ast.nodes(ofType: .heading(level: 1))
        #expect(h1.count == 1)
        #expect(h1[0].range?.start.line == 1)

        let h2 = result.ast.nodes(ofType: .heading(level: 2))
        #expect(h2.count == 1)
        #expect(h2[0].range?.start.line == 5)
    }

    @Test("Node lookup by position finds the correct node")
    func nodeAtPosition() {
        let md = """
        # Title

        Some **bold** text.
        """
        let parser = MarkdownParser()
        let result = parser.parse(md)

        // Position within the heading
        let headingNode = result.ast.node(at: SourcePosition(line: 1, column: 3))
        #expect(headingNode != nil)

        // Position within the bold text (line 3)
        let boldNode = result.ast.node(at: SourcePosition(line: 3, column: 7))
        #expect(boldNode != nil)
    }
}
