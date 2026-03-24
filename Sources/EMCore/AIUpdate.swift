/// Generic update emitted during any AI streaming session.
/// Replaces the four identical per-feature enums (FEAT-077).
/// Lives in EMCore so both EMAI and EMEditor can reference it
/// without violating dependency rules per [A-015].
///
/// Phantom action types (`ImproveWritingAction`, `SummarizeAction`,
/// `ToneAdjustmentAction`, `GhostTextAction`) provide compile-time
/// type safety — you cannot accidentally pass a summarize stream
/// to an improve-writing coordinator.
public enum AIUpdate<Action: Sendable>: Sendable {
    /// A new token was received from the AI provider.
    case token(String)
    /// The AI finished generating text.
    case completed(fullText: String)
    /// An error occurred during generation.
    case failed(EMError)
}

// MARK: - Phantom Action Types

/// Phantom type for AI Improve Writing sessions (FEAT-011).
public enum ImproveWritingAction: Sendable {}

/// Phantom type for AI Summarize sessions (FEAT-055).
public enum SummarizeAction: Sendable {}

/// Phantom type for AI Tone Adjustment sessions (FEAT-023).
public enum ToneAdjustmentAction: Sendable {}

/// Phantom type for AI Continue Writing / ghost text sessions (FEAT-056).
public enum GhostTextAction: Sendable {}

// MARK: - Type Aliases (source-compatible with previous per-feature enums)

/// Update emitted during an AI Improve Writing session per FEAT-011.
public typealias ImproveWritingUpdate = AIUpdate<ImproveWritingAction>

/// Update emitted during an AI Summarize session per FEAT-055.
public typealias SummarizeUpdate = AIUpdate<SummarizeAction>

/// Update emitted during an AI Tone Adjustment session per FEAT-023.
public typealias ToneAdjustmentUpdate = AIUpdate<ToneAdjustmentAction>

/// Update emitted during an AI Continue Writing (ghost text) session per FEAT-056.
public typealias GhostTextUpdate = AIUpdate<GhostTextAction>
