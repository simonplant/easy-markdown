/// Update emitted during an AI Tone Adjustment session per FEAT-023.
/// Lives in EMCore so both EMAI and EMEditor can reference it
/// without violating dependency rules per [A-015].
public enum ToneAdjustmentUpdate: Sendable {
    /// A new token was received from the AI provider.
    case token(String)
    /// The AI finished generating the tone-adjusted text.
    case completed(fullText: String)
    /// An error occurred during generation.
    case failed(EMError)
}
