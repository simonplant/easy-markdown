/// Versioned, content-aware prompt template for the Tone Adjustment action per FEAT-023 and [A-032].
/// Adapts the system prompt based on the target tone style and content type.

import EMCore

/// Builds system and user prompts for the AI Tone Adjustment action.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct ToneAdjustmentPromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// Builds an AIPrompt for adjusting the tone of the given text.
    /// - Parameters:
    ///   - selectedText: The user-selected text to adjust.
    ///   - toneStyle: The target tone style.
    ///   - surroundingContext: Optional paragraph or section around the selection.
    ///   - contentType: Detected content type for content-aware prompting.
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        selectedText: String,
        toneStyle: ToneStyle,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AIPrompt {
        AIPrompt(
            action: .adjustTone(style: toneStyle),
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt(for: toneStyle, contentType: contentType),
            contentType: contentType
        )
    }

    /// Returns the system prompt tailored to the tone style and content type.
    static func systemPrompt(for toneStyle: ToneStyle, contentType: ContentType) -> String {
        let base = """
            You are a writing assistant for a markdown editor. \
            Rewrite the user's text to match the requested tone. \
            Return ONLY the rewritten text — no explanations, no markdown fences, no preamble. \
            Preserve the original meaning, structure, and any markdown formatting.
            """

        let toneInstruction: String
        switch toneStyle {
        case .formal:
            toneInstruction = "Make the text more formal and professional. Use precise language, avoid contractions, and adopt a polished, authoritative voice."
        case .casual:
            toneInstruction = "Make the text more casual and conversational. Use a relaxed, friendly voice with natural phrasing. Contractions are fine."
        case .academic:
            toneInstruction = "Make the text more technical and academic. Use domain-appropriate terminology, precise definitions, and a scholarly tone."
        case .concise:
            toneInstruction = "Make the text simpler and more concise. Use shorter sentences, plain language, and remove unnecessary complexity. Keep the core message."
        case .friendly:
            toneInstruction = "Make the text warmer and more approachable. Use an encouraging, positive tone while keeping the content accurate."
        case .custom(let instruction):
            toneInstruction = "Apply the following tone instruction: \(instruction)"
        }

        let contentGuidance: String
        switch contentType {
        case .codeBlock:
            contentGuidance = " The selection contains code — adjust only comments and documentation strings, not the code itself."
        case .table:
            contentGuidance = " The selection is a markdown table — adjust cell content while preserving table structure."
        case .mermaid:
            contentGuidance = " The selection is a Mermaid diagram — adjust labels and descriptions only."
        default:
            contentGuidance = ""
        }

        return base + "\n" + toneInstruction + contentGuidance
    }
}
