/// Versioned, content-aware prompt template for the Summarize action per [A-032].
/// Adapts prompt based on ContentType — prose gets concise summary,
/// code gets description, tables get data summary.

import EMCore

/// Builds system and user prompts for the AI Summarize action per FEAT-055.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct SummarizePromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// Builds an AIPrompt for summarizing the given text.
    /// - Parameters:
    ///   - selectedText: The user-selected text to summarize.
    ///   - surroundingContext: Optional paragraph or section around the selection.
    ///   - contentType: Detected content type for content-aware prompting.
    ///   - isFullDocument: Whether the entire document is selected (produces longer summary).
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        selectedText: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose,
        isFullDocument: Bool = false
    ) -> AIPrompt {
        AIPrompt(
            action: .summarize,
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt(for: contentType, isFullDocument: isFullDocument),
            contentType: contentType
        )
    }

    /// Returns the system prompt tailored to the content type and scope.
    static func systemPrompt(for contentType: ContentType, isFullDocument: Bool) -> String {
        let lengthGuidance = isFullDocument
            ? "Produce a single paragraph summary (3-5 sentences)."
            : "Produce a concise summary of 1-3 sentences."

        switch contentType {
        case .prose:
            return """
                You are a writing assistant for a markdown editor. \
                Summarize the user's text clearly and concisely. \
                \(lengthGuidance) \
                Capture the key points and main argument. \
                Return ONLY the summary — no explanations, no markdown fences, no preamble.
                """

        case .codeBlock(let language):
            let lang = language ?? "unknown"
            return """
                You are a code assistant for a markdown editor. \
                The user selected a \(lang) code block. \
                \(lengthGuidance) \
                Describe what the code does at a high level. \
                Return ONLY the summary — no markdown fences, no explanations.
                """

        case .table:
            return """
                You are a writing assistant for a markdown editor. \
                The user selected a markdown table. \
                \(lengthGuidance) \
                Summarize the data and key takeaways from the table. \
                Return ONLY the summary — no markdown fences, no explanations.
                """

        case .mermaid:
            return """
                You are a diagram assistant for a markdown editor. \
                The user selected a Mermaid diagram block. \
                \(lengthGuidance) \
                Describe what the diagram represents and its key elements. \
                Return ONLY the summary — no fences, no explanations.
                """

        case .mixed:
            return """
                You are a writing assistant for a markdown editor. \
                Summarize the user's content clearly and concisely. \
                \(lengthGuidance) \
                The content contains mixed types — capture the overall meaning. \
                Return ONLY the summary — no explanations, no markdown fences, no preamble.
                """
        }
    }
}
