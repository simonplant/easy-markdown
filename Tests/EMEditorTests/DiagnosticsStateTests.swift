import Testing
import Foundation
@testable import EMEditor
@testable import EMCore

@MainActor
@Suite("DiagnosticsState")
struct DiagnosticsStateTests {

    @Test("Initial state is empty")
    func initialState() {
        let state = DiagnosticsState()
        #expect(state.diagnostics.isEmpty)
        #expect(state.dismissedKeys.isEmpty)
    }

    @Test("Update diagnostics replaces current list")
    func updateDiagnostics() {
        let state = DiagnosticsState()
        let diag1 = Diagnostic(
            ruleID: "test-rule",
            message: "Test message",
            severity: .warning,
            line: 1
        )
        let diag2 = Diagnostic(
            ruleID: "test-rule-2",
            message: "Another message",
            severity: .warning,
            line: 5
        )

        state.updateDiagnostics([diag1, diag2])
        #expect(state.diagnostics.count == 2)

        state.updateDiagnostics([diag1])
        #expect(state.diagnostics.count == 1)
    }

    @Test("Dismiss diagnostic removes it and tracks key")
    func dismissDiagnostic() {
        let state = DiagnosticsState()
        let diag = Diagnostic(
            ruleID: "heading-hierarchy",
            message: "Skipped heading level",
            severity: .warning,
            line: 3
        )

        state.updateDiagnostics([diag])
        #expect(state.diagnostics.count == 1)

        state.dismissDiagnostic(diag)
        #expect(state.diagnostics.isEmpty)
        #expect(state.dismissedKeys.contains("heading-hierarchy:3"))
    }

    @Test("Clear diagnostics resets everything")
    func clearDiagnostics() {
        let state = DiagnosticsState()
        let diag = Diagnostic(
            ruleID: "test-rule",
            message: "Test",
            severity: .warning,
            line: 1
        )

        state.updateDiagnostics([diag])
        state.dismissDiagnostic(diag)
        #expect(!state.dismissedKeys.isEmpty)

        state.clearDiagnostics()
        #expect(state.diagnostics.isEmpty)
        #expect(state.dismissedKeys.isEmpty)
    }
}
