/// Versioned, content-aware prompt template for the Improve action per [A-032].
/// Inspects `ContentType` and adapts the prompt accordingly.

import EMCore

/// Builds system and user prompts for the AI Improve Writing action.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct ImprovePromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// Builds an AIPrompt for improving the given text.
    /// - Parameters:
    ///   - selectedText: The user-selected text to improve.
    ///   - surroundingContext: Optional paragraph or section around the selection.
    ///   - contentType: Detected content type for content-aware prompting.
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        selectedText: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AIPrompt {
        AIPrompt(
            action: .improve,
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt(for: contentType),
            contentType: contentType
        )
    }

    /// Returns the system prompt tailored to the content type.
    static func systemPrompt(for contentType: ContentType) -> String {
        let base = """
            You are a writing assistant for a markdown editor. \
            Improve the user's text for grammar, clarity, and conciseness. \
            Return ONLY the improved text — no explanations, no markdown fences, no preamble.
            """

        switch contentType {
        case .prose:
            return base + "\nPreserve the author's voice and intent. Fix grammar and improve readability."

        case .codeBlock(let language):
            let lang = language ?? "unknown"
            return """
                You are a code assistant for a markdown editor. \
                The user selected a \(lang) code block. \
                Improve the code for clarity, correctness, and idiomatic style. \
                Return ONLY the improved code — no markdown fences, no explanations.
                """

        case .table:
            return base + """
                \nThe selection is a markdown table. \
                Improve content within cells for clarity. \
                Preserve the table structure (pipes and alignment).
                """

        case .mermaid:
            return """
                You are a diagram assistant for a markdown editor. \
                The user selected a Mermaid diagram block. \
                Improve the diagram for clarity, correct syntax, and better naming. \
                Return ONLY the improved Mermaid code — no fences, no explanations.
                """

        case .mixed:
            return base + "\nThe selection contains mixed content types. Improve each part appropriately."
        }
    }
}
