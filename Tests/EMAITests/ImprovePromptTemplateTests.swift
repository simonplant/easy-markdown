import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("ImprovePromptTemplate")
struct ImprovePromptTemplateTests {

    // MARK: - Prompt Construction

    @Test("buildPrompt creates prompt with improve action")
    func buildPromptAction() {
        let prompt = ImprovePromptTemplate.buildPrompt(
            selectedText: "This is some text."
        )
        guard case .improve = prompt.action else {
            Issue.record("Expected .improve action")
            return
        }
    }

    @Test("buildPrompt includes selected text")
    func buildPromptSelectedText() {
        let text = "The quick brown fox jumps."
        let prompt = ImprovePromptTemplate.buildPrompt(selectedText: text)
        #expect(prompt.selectedText == text)
    }

    @Test("buildPrompt includes surrounding context when provided")
    func buildPromptContext() {
        let prompt = ImprovePromptTemplate.buildPrompt(
            selectedText: "Some text.",
            surroundingContext: "This is the paragraph context."
        )
        #expect(prompt.surroundingContext == "This is the paragraph context.")
    }

    @Test("buildPrompt defaults to prose content type")
    func buildPromptDefaultContentType() {
        let prompt = ImprovePromptTemplate.buildPrompt(selectedText: "Hello.")
        guard case .prose = prompt.contentType else {
            Issue.record("Expected .prose content type")
            return
        }
    }

    @Test("buildPrompt respects explicit content type")
    func buildPromptExplicitContentType() {
        let prompt = ImprovePromptTemplate.buildPrompt(
            selectedText: "graph TD; A-->B",
            contentType: .mermaid
        )
        guard case .mermaid = prompt.contentType else {
            Issue.record("Expected .mermaid content type")
            return
        }
    }

    // MARK: - Content-Aware System Prompts

    @Test("prose system prompt mentions grammar and clarity")
    func prosePrompt() {
        let prompt = ImprovePromptTemplate.systemPrompt(for: .prose)
        #expect(prompt.contains("grammar"))
        #expect(prompt.contains("clarity"))
    }

    @Test("code block system prompt mentions the language")
    func codeBlockPrompt() {
        let prompt = ImprovePromptTemplate.systemPrompt(for: .codeBlock(language: "swift"))
        #expect(prompt.contains("swift"))
        #expect(prompt.contains("code"))
    }

    @Test("code block system prompt handles nil language")
    func codeBlockNilLanguage() {
        let prompt = ImprovePromptTemplate.systemPrompt(for: .codeBlock(language: nil))
        #expect(prompt.contains("unknown"))
    }

    @Test("table system prompt mentions table structure")
    func tablePrompt() {
        let prompt = ImprovePromptTemplate.systemPrompt(for: .table)
        #expect(prompt.contains("table"))
        #expect(prompt.contains("Preserve"))
    }

    @Test("mermaid system prompt mentions diagram")
    func mermaidPrompt() {
        let prompt = ImprovePromptTemplate.systemPrompt(for: .mermaid)
        #expect(prompt.contains("Mermaid"))
        #expect(prompt.contains("diagram"))
    }

    @Test("mixed content system prompt mentions mixed")
    func mixedPrompt() {
        let prompt = ImprovePromptTemplate.systemPrompt(for: .mixed)
        #expect(prompt.contains("mixed"))
    }

    @Test("all prompts instruct no explanations")
    func noExplanations() {
        let types: [ContentType] = [.prose, .codeBlock(language: "js"), .table, .mermaid, .mixed]
        for contentType in types {
            let prompt = ImprovePromptTemplate.systemPrompt(for: contentType)
            #expect(prompt.contains("no explanation") || prompt.contains("no preamble") || prompt.contains("no fences"))
        }
    }

    // MARK: - Version

    @Test("template has a version number")
    func versionExists() {
        #expect(ImprovePromptTemplate.version >= 1)
    }
}
