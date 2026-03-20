/// Update emitted during an AI Improve Writing session per FEAT-011.
/// Lives in EMCore so both EMAI and EMEditor can reference it
/// without violating dependency rules per [A-015].
public enum ImproveWritingUpdate: Sendable {
    /// A new token was received from the AI provider.
    case token(String)
    /// The AI finished generating the improved text.
    case completed(fullText: String)
    /// An error occurred during generation.
    case failed(EMError)
}
