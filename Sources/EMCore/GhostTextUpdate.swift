/// Update emitted during an AI Continue Writing (ghost text) session per FEAT-056.
/// Lives in EMCore so both EMAI and EMEditor can reference it
/// without violating dependency rules per [A-015].
public enum GhostTextUpdate: Sendable {
    /// A new token was received from the AI provider.
    case token(String)
    /// The AI finished generating the continuation.
    case completed(fullText: String)
    /// An error occurred during generation.
    case failed(EMError)
}
