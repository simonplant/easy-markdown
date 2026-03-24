/// Update emitted during an AI Translation session per FEAT-024.
/// Lives in EMCore so both EMAI and EMEditor can reference it
/// without violating dependency rules per [A-015].
public enum TranslationUpdate: Sendable {
    /// A new token was received from the AI provider.
    case token(String)
    /// The AI finished generating the translated text.
    case completed(fullText: String)
    /// An error occurred during generation.
    case failed(EMError)
}
