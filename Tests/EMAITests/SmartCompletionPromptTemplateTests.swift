import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("SmartCompletionPromptTemplate")
struct SmartCompletionPromptTemplateTests {

    // MARK: - Table Header Prompt

    @Test("table header prompt includes column names")
    func tableHeaderPromptColumns() {
        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: .tableHeader(columns: ["Name", "Email", "Role"]),
            precedingText: "| Name | Email | Role |\n"
        )

        #expect(prompt.action == .smartComplete)
        #expect(prompt.contentType == .table)
        #expect(prompt.systemPrompt.contains("Name, Email, Role"))
        #expect(prompt.systemPrompt.contains("3"))
    }

    @Test("table header prompt mentions separator row")
    func tableHeaderPromptSeparator() {
        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: .tableHeader(columns: ["A", "B"]),
            precedingText: "| A | B |\n"
        )

        #expect(prompt.systemPrompt.contains("separator"))
    }

    // MARK: - List Item Prompt

    @Test("list item prompt includes recent items")
    func listItemPromptRecentItems() {
        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: .listItem(prefix: "- ", items: ["apples", "bananas"]),
            precedingText: "- apples\n- bananas\n"
        )

        #expect(prompt.action == .smartComplete)
        #expect(prompt.contentType == .prose)
        #expect(prompt.systemPrompt.contains("apples"))
        #expect(prompt.systemPrompt.contains("bananas"))
    }

    @Test("list item prompt uses the correct prefix")
    func listItemPromptPrefix() {
        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: .listItem(prefix: "* ", items: ["x", "y"]),
            precedingText: "* x\n* y\n"
        )

        #expect(prompt.systemPrompt.contains("* "))
    }

    // MARK: - Front Matter Prompt

    @Test("front matter prompt includes existing keys")
    func frontMatterPromptKeys() {
        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: .frontMatter(existingKeys: ["title", "date", "tags"]),
            precedingText: "---\ntitle: Post\ndate: 2026-01-01\ntags: [swift]\n"
        )

        #expect(prompt.action == .smartComplete)
        #expect(prompt.systemPrompt.contains("title, date, tags"))
    }

    // MARK: - Version

    @Test("template version is 1")
    func templateVersion() {
        #expect(SmartCompletionPromptTemplate.version == 1)
    }

    // MARK: - Selected Text

    @Test("preceding text is set as selectedText")
    func precedingTextIsSelectedText() {
        let precedingText = "| Col1 | Col2 |\n"
        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: .tableHeader(columns: ["Col1", "Col2"]),
            precedingText: precedingText
        )

        #expect(prompt.selectedText == precedingText)
    }
}
