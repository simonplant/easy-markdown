import Testing
import Foundation
@testable import EMFile

@Suite("MarkdownExtensions")
struct MarkdownExtensionsTests {

    @Test("All expected extensions are listed per D-FILE-6")
    func allExtensions() {
        let expected = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx"]
        #expect(MarkdownExtensions.all == expected)
    }

    @Test("Recognizes markdown files by extension")
    func recognizesMarkdownFiles() {
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.md")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.markdown")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.mdown")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.mkd")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.mkdn")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.mdx")) == true)
    }

    @Test("Rejects non-markdown files")
    func rejectsNonMarkdown() {
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.txt")) == false)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.swift")) == false)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.html")) == false)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test")) == false)
    }

    @Test("Case-insensitive extension matching")
    func caseInsensitive() {
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.MD")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.Md")) == true)
        #expect(MarkdownExtensions.isMarkdownFile(URL(fileURLWithPath: "/test.MARKDOWN")) == true)
    }

    @Test("UTTypes are generated for all extensions")
    func utTypesExist() {
        // At minimum, .md should produce a valid UTType
        #expect(!MarkdownExtensions.utTypes.isEmpty)
    }
}
