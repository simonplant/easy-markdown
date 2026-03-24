/// Focused state object for Document Doctor diagnostics per FEAT-076.
/// Independently observable and testable.

import Foundation
import EMCore

@MainActor
@Observable
public final class DiagnosticsState {
    /// Active diagnostics from the Document Doctor per FEAT-005.
    /// Updated after each doctor evaluation cycle.
    public private(set) var diagnostics: [Diagnostic] = []

    /// Keys of diagnostics dismissed by the user this session per FEAT-005.
    /// Format: "ruleID:line". Cleared on file close.
    public private(set) var dismissedKeys: Set<String> = []

    public init() {}

    /// Replace the current diagnostics with new results from the doctor engine.
    public func updateDiagnostics(_ newDiagnostics: [Diagnostic]) {
        diagnostics = newDiagnostics
    }

    /// Dismiss a diagnostic for this session. It will not reappear until
    /// the file is closed and reopened per FEAT-005 AC-3.
    public func dismissDiagnostic(_ diagnostic: Diagnostic) {
        let key = "\(diagnostic.ruleID):\(diagnostic.line)"
        dismissedKeys.insert(key)
        diagnostics.removeAll { $0.id == diagnostic.id }
    }

    /// Clear all diagnostics and dismissals (called on file close).
    public func clearDiagnostics() {
        diagnostics = []
        dismissedKeys = []
    }
}
