import Testing
import Foundation
@testable import EMEditor
@testable import EMParser

@MainActor
@Suite("CursorMapper")
struct CursorMapperTests {

    private let mapper = CursorMapper()
    private let parser = MarkdownParser()

    // MARK: - Empty Document (AC-5)

    @Test("Empty document returns cursor at start")
    func emptyDocument() {
        let text = ""
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 0, length: 0),
            text: text,
            ast: nil
        )
        #expect(result == NSRange(location: 0, length: 0))
    }

    @Test("Empty document rich to source returns cursor at start")
    func emptyDocumentRichToSource() {
        let text = ""
        let result = mapper.mapRichToSource(
            selectedRange: NSRange(location: 0, length: 0),
            text: text,
            ast: nil
        )
        #expect(result == NSRange(location: 0, length: 0))
    }

    // MARK: - Source to Rich Mapping

    @Test("Cursor in plain paragraph stays at same position")
    func plainParagraphSourceToRich() {
        let text = "Hello world"
        let ast = parser.parse(text).ast
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 5, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 5, length: 0))
    }

    @Test("Cursor inside heading marker snaps past prefix")
    func headingMarkerSnap() {
        let text = "## Hello"
        let ast = parser.parse(text).ast
        // Cursor at position 1 (inside "##") should snap to position 3 (after "## ")
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 1, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 3, length: 0))
    }

    @Test("Cursor after heading marker stays in place")
    func headingAfterMarker() {
        let text = "## Hello"
        let ast = parser.parse(text).ast
        // Cursor at position 4 (inside "Hello") should stay
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 4, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 4, length: 0))
    }

    @Test("Cursor inside list marker snaps past prefix")
    func listMarkerSnap() {
        let text = "- Item one"
        let ast = parser.parse(text).ast
        // Cursor at position 0 (at "-") should snap to position 2 (after "- ")
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 0, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 2, length: 0))
    }

    @Test("Cursor inside ordered list marker snaps past prefix")
    func orderedListMarkerSnap() {
        let text = "1. First item"
        let ast = parser.parse(text).ast
        // Cursor at position 1 (at ".") should snap to position 3 (after "1. ")
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 1, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 3, length: 0))
    }

    @Test("Cursor inside blockquote marker snaps past prefix")
    func blockquoteMarkerSnap() {
        let text = "> Hello"
        let ast = parser.parse(text).ast
        // Cursor at position 0 (at ">") should snap to position 2 (after "> ")
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 0, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 2, length: 0))
    }

    // MARK: - Rich to Source Mapping

    @Test("Rich to source preserves cursor position")
    func richToSourcePreservesPosition() {
        let text = "Hello world\n\nSecond paragraph"
        let ast = parser.parse(text).ast
        let result = mapper.mapRichToSource(
            selectedRange: NSRange(location: 15, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 15, length: 0))
    }

    // MARK: - Selection Preservation

    @Test("Selection range preserved in source to rich")
    func selectionPreservedSourceToRich() {
        let text = "Hello world"
        let ast = parser.parse(text).ast
        // Selecting "world" (location: 6, length: 5)
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 6, length: 5),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 6, length: 5))
    }

    // MARK: - Source Position Conversion

    @Test("UTF-16 offset to source position on first line")
    func utf16ToSourcePositionFirstLine() {
        let text = "Hello"
        let pos = mapper.sourcePosition(atUTF16Offset: 3, in: text)
        #expect(pos?.line == 1)
        #expect(pos?.column == 4) // 1-based
    }

    @Test("UTF-16 offset to source position on second line")
    func utf16ToSourcePositionSecondLine() {
        let text = "Hello\nWorld"
        let pos = mapper.sourcePosition(atUTF16Offset: 8, in: text)
        #expect(pos?.line == 2)
        #expect(pos?.column == 3) // "Wo" = 2 chars past start, column 3
    }

    @Test("Source position to UTF-16 offset round-trips")
    func sourcePositionRoundTrip() {
        let text = "Hello\nWorld\nThird"
        let offset = 13 // "Th" on line 3
        let pos = mapper.sourcePosition(atUTF16Offset: offset, in: text)
        #expect(pos != nil)
        if let pos {
            let backToOffset = mapper.utf16Offset(for: pos, in: text)
            #expect(backToOffset == offset)
        }
    }

    // MARK: - Edge Cases

    @Test("Cursor at end of document")
    func cursorAtEnd() {
        let text = "Hello"
        let ast = parser.parse(text).ast
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 5, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 5, length: 0))
    }

    @Test("Cursor beyond document length clamps to start")
    func cursorBeyondLength() {
        let text = "Hello"
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 100, length: 0),
            text: text,
            ast: nil
        )
        #expect(result == NSRange(location: 0, length: 0))
    }

    @Test("Multi-paragraph document preserves cursor in second paragraph")
    func multiParagraph() {
        let text = "# Title\n\nSome text here"
        let ast = parser.parse(text).ast
        // Cursor in "Some text here" (offset 9+5 = 14)
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 14, length: 0),
            text: text,
            ast: ast
        )
        #expect(result == NSRange(location: 14, length: 0))
    }

    @Test("Nil AST returns original range")
    func nilAST() {
        let text = "Hello world"
        let original = NSRange(location: 5, length: 0)
        let result = mapper.mapSourceToRich(
            selectedRange: original,
            text: text,
            ast: nil
        )
        #expect(result == original)
    }
}
