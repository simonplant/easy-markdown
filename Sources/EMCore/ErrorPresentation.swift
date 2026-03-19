import Foundation

/// How an error should be presented to the user per [A-035].
/// Determines whether the error appears as a banner or modal alert.
public enum ErrorSeverity: Sendable {
    /// Recoverable errors (save failure, network timeout).
    /// Presented as a non-modal banner with retry action. Auto-dismisses after 8 seconds.
    case recoverable

    /// Data-loss-risk errors (file deleted while editing, storage full).
    /// Presented as a modal alert. Does not auto-dismiss.
    case dataLossRisk

    /// Informational warnings (file >1MB, non-UTF-8).
    /// Presented as a dismissable banner. No action required.
    case informational
}

/// A recovery action the user can take in response to an error.
public struct RecoveryAction: Sendable {
    /// Human-readable label for the action button (e.g., "Try Again", "Save Elsewhere").
    public let label: String

    /// The action to perform. Runs on @MainActor since it typically updates UI state.
    public let perform: @MainActor @Sendable () async -> Void

    public init(label: String, perform: @MainActor @Sendable @escaping () async -> Void) {
        self.label = label
        self.perform = perform
    }
}

/// A presentable error combining a user-facing message, severity, and recovery actions.
/// Created from an `EMError` and passed to the error presentation layer in EMApp.
public struct PresentableError: Identifiable, Sendable {
    public let id: UUID
    public let message: String
    public let severity: ErrorSeverity
    public let recoveryActions: [RecoveryAction]

    public init(
        id: UUID = UUID(),
        message: String,
        severity: ErrorSeverity,
        recoveryActions: [RecoveryAction] = []
    ) {
        self.id = id
        self.message = message
        self.severity = severity
        self.recoveryActions = recoveryActions
    }
}
