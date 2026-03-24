/// Versioned, content-aware prompt template for voice intent interpretation per FEAT-068.
/// Takes a spoken transcript and generates a system prompt that instructs the AI
/// to interpret the user's editing intent and apply it to the given text.

import EMCore

/// Builds system and user prompts for the AI Voice Intent action.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct VoiceIntentPromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// Builds an AIPrompt for interpreting a voice command and applying it to text.
    /// - Parameters:
    ///   - transcript: The transcribed speech from the user.
    ///   - selectedText: The text to operate on (selection or current paragraph).
    ///   - surroundingContext: Optional surrounding text for context.
    ///   - contentType: Detected content type for content-aware prompting.
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        transcript: String,
        selectedText: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AIPrompt {
        AIPrompt(
            action: .intentFromVoice(transcript: transcript),
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt(for: contentType, transcript: transcript),
            contentType: contentType
        )
    }

    /// Returns the system prompt tailored to the content type and voice transcript.
    static func systemPrompt(for contentType: ContentType, transcript: String) -> String {
        let base = """
            You are a writing assistant for a markdown editor that interprets voice commands. \
            The user spoke: "\(transcript)". \
            Interpret their intent and apply it to the provided text. \
            Return ONLY the modified text — no explanations, no markdown fences, no preamble. \
            If the intent is unclear, return the original text unchanged.
            """

        switch contentType {
        case .prose:
            return base + """
                \nThe text is prose markdown. Common intents include: \
                make shorter, make longer, improve grammar, change tone, \
                add a section, restructure, simplify, make more formal, \
                make more casual, fix spelling, summarize, expand.
                """

        case .codeBlock(let language):
            let lang = language ?? "unknown"
            return base + """
                \nThe text is a \(lang) code block. Common intents include: \
                add comments, simplify, refactor, fix bugs, optimize, \
                rename variables, add error handling.
                """

        case .table:
            return base + """
                \nThe text is a markdown table. Common intents include: \
                add a column, add a row, sort, reorganize, \
                fix alignment, rename headers.
                """

        case .mermaid:
            return base + """
                \nThe text is a Mermaid diagram. Common intents include: \
                add a node, change layout, rename elements, \
                add connections, simplify the diagram.
                """

        case .mixed:
            return base + "\nThe text contains mixed content types. Apply the intent to each part appropriately."
        }
    }
}
