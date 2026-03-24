/// Versioned, content-aware prompt template for the Translation action per FEAT-024 and [A-032].
/// Adapts the system prompt based on the target language and content type.

import EMCore

/// Builds system and user prompts for the AI Translation action.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct TranslationPromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// Builds an AIPrompt for translating the given text.
    /// - Parameters:
    ///   - selectedText: The user-selected text to translate.
    ///   - targetLanguage: The target language code (e.g. "es", "fr").
    ///   - surroundingContext: Optional paragraph or section around the selection.
    ///   - contentType: Detected content type for content-aware prompting.
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        selectedText: String,
        targetLanguage: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AIPrompt {
        AIPrompt(
            action: .translate(targetLanguage: targetLanguage),
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt(for: targetLanguage, contentType: contentType),
            contentType: contentType
        )
    }

    /// Returns the system prompt tailored to the target language and content type.
    static func systemPrompt(for targetLanguage: String, contentType: ContentType) -> String {
        let languageName = TranslationLanguage.displayName(for: targetLanguage)

        let base = """
            You are a professional translator for a markdown editor. \
            Translate the user's text into \(languageName). \
            Return ONLY the translated text — no explanations, no markdown fences, no preamble. \
            Preserve the original markdown formatting, structure, and any code or technical terms \
            that should remain untranslated (e.g. variable names, function names, URLs).
            """

        let contentGuidance: String
        switch contentType {
        case .codeBlock:
            contentGuidance = " The selection contains code — translate only comments and string literals, not the code itself."
        case .table:
            contentGuidance = " The selection is a markdown table — translate cell content while preserving table structure."
        case .mermaid:
            contentGuidance = " The selection is a Mermaid diagram — translate labels and descriptions only, preserving diagram syntax."
        default:
            contentGuidance = ""
        }

        return base + "\n" + contentGuidance
    }
}

/// Supported translation languages per FEAT-024.
/// 20 languages: EN, ES, FR, DE, ZH, JA, KO, PT, IT, RU, AR, HI, NL, SV, PL, DA, NO, FI, TR, TH.
public struct TranslationLanguage: Sendable, Identifiable {
    public let code: String
    public let name: String

    public var id: String { code }

    /// All supported translation languages.
    public static let all: [TranslationLanguage] = [
        TranslationLanguage(code: "en", name: "English"),
        TranslationLanguage(code: "es", name: "Spanish"),
        TranslationLanguage(code: "fr", name: "French"),
        TranslationLanguage(code: "de", name: "German"),
        TranslationLanguage(code: "zh", name: "Chinese"),
        TranslationLanguage(code: "ja", name: "Japanese"),
        TranslationLanguage(code: "ko", name: "Korean"),
        TranslationLanguage(code: "pt", name: "Portuguese"),
        TranslationLanguage(code: "it", name: "Italian"),
        TranslationLanguage(code: "ru", name: "Russian"),
        TranslationLanguage(code: "ar", name: "Arabic"),
        TranslationLanguage(code: "hi", name: "Hindi"),
        TranslationLanguage(code: "nl", name: "Dutch"),
        TranslationLanguage(code: "sv", name: "Swedish"),
        TranslationLanguage(code: "pl", name: "Polish"),
        TranslationLanguage(code: "da", name: "Danish"),
        TranslationLanguage(code: "no", name: "Norwegian"),
        TranslationLanguage(code: "fi", name: "Finnish"),
        TranslationLanguage(code: "tr", name: "Turkish"),
        TranslationLanguage(code: "th", name: "Thai"),
    ]

    /// Returns the display name for a language code.
    public static func displayName(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }
}
