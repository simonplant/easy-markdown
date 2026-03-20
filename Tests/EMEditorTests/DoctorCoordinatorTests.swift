import Testing
import Foundation
@testable import EMEditor
@testable import EMParser
@testable import EMCore

@MainActor
@Suite("DoctorCoordinator")
struct DoctorCoordinatorTests {

    private let parser = MarkdownParser()

    @Test("AC-7: Doctor evaluates in rich view mode (isSourceView=false)")
    func doctorEvaluatesInRichView() async throws {
        let state = EditorState()
        state.isSourceView = false
        let coordinator = DoctorCoordinator(editorState: state)

        let text = "# Title\n### Skipped Level"
        let result = parser.parse(text)

        coordinator.evaluateImmediately(text: text, ast: result.ast)

        // Wait for the background Task.detached to complete and post results
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(!state.diagnostics.isEmpty, "Doctor should find diagnostics in rich view mode")
        #expect(state.diagnostics.contains { $0.ruleID == "heading-hierarchy" })
    }

    @Test("AC-7: Doctor evaluates in source view mode (isSourceView=true)")
    func doctorEvaluatesInSourceView() async throws {
        let state = EditorState()
        state.isSourceView = true
        let coordinator = DoctorCoordinator(editorState: state)

        let text = "# Title\n### Skipped Level"
        let result = parser.parse(text)

        coordinator.evaluateImmediately(text: text, ast: result.ast)

        // Wait for the background Task.detached to complete and post results
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(!state.diagnostics.isEmpty, "Doctor should find diagnostics in source view mode")
        #expect(state.diagnostics.contains { $0.ruleID == "heading-hierarchy" })
    }

    @Test("AC-7: Doctor produces identical results in both view modes")
    func doctorResultsIdenticalAcrossViewModes() async throws {
        let text = "# Title\n### Skipped Level\n\n## Features\n\nSome text\n\n## Features"
        let result = parser.parse(text)

        // Rich view
        let richState = EditorState()
        richState.isSourceView = false
        let richCoordinator = DoctorCoordinator(editorState: richState)
        richCoordinator.evaluateImmediately(text: text, ast: result.ast)

        // Source view
        let sourceState = EditorState()
        sourceState.isSourceView = true
        let sourceCoordinator = DoctorCoordinator(editorState: sourceState)
        sourceCoordinator.evaluateImmediately(text: text, ast: result.ast)

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(richState.diagnostics.count == sourceState.diagnostics.count,
                "Doctor should produce the same number of diagnostics in both view modes")

        // Verify same rule IDs in same order
        let richRuleIDs = richState.diagnostics.map(\.ruleID)
        let sourceRuleIDs = sourceState.diagnostics.map(\.ruleID)
        #expect(richRuleIDs == sourceRuleIDs,
                "Doctor should produce the same rules in both view modes")
    }
}
