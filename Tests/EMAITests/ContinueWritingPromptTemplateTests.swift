import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("ContinueWritingPromptTemplate")
struct ContinueWritingPromptTemplateTests {

    @Test("builds prompt with ghostTextComplete action")
    func buildPromptAction() {
        let prompt = ContinueWritingPromptTemplate.buildPrompt(
            precedingText: "The quick brown fox"
        )
        guard case .ghostTextComplete = prompt.action else {
            Issue.record("Expected .ghostTextComplete action")
            return
        }
    }

    @Test("builds prompt with preceding text as selectedText")
    func buildPromptText() {
        let prompt = ContinueWritingPromptTemplate.buildPrompt(
            precedingText: "Hello world."
        )
        #expect(prompt.selectedText == "Hello world.")
    }

    @Test("builds prompt with surrounding context")
    func buildPromptContext() {
        let prompt = ContinueWritingPromptTemplate.buildPrompt(
            precedingText: "Hello",
            surroundingContext: "Broader document context here."
        )
        #expect(prompt.surroundingContext == "Broader document context here.")
    }

    @Test("builds prompt with prose content type")
    func buildPromptContentType() {
        let prompt = ContinueWritingPromptTemplate.buildPrompt(
            precedingText: "Test"
        )
        guard case .prose = prompt.contentType else {
            Issue.record("Expected .prose content type")
            return
        }
    }

    @Test("system prompt instructs continuation without repetition")
    func systemPromptContent() {
        let prompt = ContinueWritingPromptTemplate.buildPrompt(
            precedingText: "Test"
        )
        #expect(prompt.systemPrompt.contains("Continue"))
        #expect(prompt.systemPrompt.contains("1-3 sentences"))
        #expect(prompt.systemPrompt.contains("Do NOT repeat"))
    }

    @Test("version is defined")
    func versionIsDefined() {
        #expect(ContinueWritingPromptTemplate.version >= 1)
    }
}
