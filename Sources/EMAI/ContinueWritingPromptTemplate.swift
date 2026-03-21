/// Versioned prompt template for the AI Continue Writing (ghost text) action per [A-032].
/// Generates 1-3 sentences continuing the user's thought, matching their tone and style.

import EMCore

/// Builds system and user prompts for the AI Continue Writing action per FEAT-056.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct ContinueWritingPromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// Builds an AIPrompt for continuing the user's text.
    /// - Parameters:
    ///   - precedingText: The text before the cursor (last ~500 chars for context).
    ///   - surroundingContext: Optional broader document context.
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        precedingText: String,
        surroundingContext: String? = nil
    ) -> AIPrompt {
        AIPrompt(
            action: .ghostTextComplete,
            selectedText: precedingText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt,
            contentType: .prose
        )
    }

    /// System prompt for ghost text continuation.
    static let systemPrompt = """
        You are a writing assistant for a markdown editor. \
        Continue the user's text naturally with 1-3 sentences. \
        Match the user's tone, style, and vocabulary. \
        Do NOT repeat any of the user's existing text. \
        Do NOT add markdown formatting unless the user was already using it. \
        Do NOT add explanations, preamble, or meta-commentary. \
        Return ONLY the continuation text.
        """
}
