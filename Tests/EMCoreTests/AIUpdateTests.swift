import Testing
import Foundation
@testable import EMCore

@Suite("AIUpdate")
struct AIUpdateTests {

    // MARK: - Token case

    @Test("token case carries text via ImproveWritingUpdate alias")
    func tokenCaseImproveWriting() {
        let update = ImproveWritingUpdate.token("Hello")
        if case .token(let text) = update {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected .token case")
        }
    }

    @Test("token case carries text via SummarizeUpdate alias")
    func tokenCaseSummarize() {
        let update = SummarizeUpdate.token("Summary")
        if case .token(let text) = update {
            #expect(text == "Summary")
        } else {
            Issue.record("Expected .token case")
        }
    }

    @Test("token case carries text via ToneAdjustmentUpdate alias")
    func tokenCaseToneAdjustment() {
        let update = ToneAdjustmentUpdate.token("Adjusted")
        if case .token(let text) = update {
            #expect(text == "Adjusted")
        } else {
            Issue.record("Expected .token case")
        }
    }

    @Test("token case carries text via GhostTextUpdate alias")
    func tokenCaseGhostText() {
        let update = GhostTextUpdate.token("Ghost")
        if case .token(let text) = update {
            #expect(text == "Ghost")
        } else {
            Issue.record("Expected .token case")
        }
    }

    // MARK: - Completed case

    @Test("completed case carries full text")
    func completedCase() {
        let update = ImproveWritingUpdate.completed(fullText: "Hello world")
        if case .completed(let text) = update {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected .completed case")
        }
    }

    // MARK: - Failed case

    @Test("failed case carries error")
    func failedCase() {
        let error = EMError.ai(.inferenceTimeout)
        let update = ImproveWritingUpdate.failed(error)
        if case .failed(let e) = update {
            if case .ai(.inferenceTimeout) = e {
                // Expected
            } else {
                Issue.record("Expected .ai(.inferenceTimeout) error")
            }
        } else {
            Issue.record("Expected .failed case")
        }
    }

    // MARK: - Type safety (phantom types prevent cross-assignment)

    @Test("type aliases resolve to AIUpdate with distinct phantom types")
    func typeAliasesAreDistinct() {
        // These compile — each alias is AIUpdate<DistinctPhantom>
        let _: AIUpdate<ImproveWritingAction> = ImproveWritingUpdate.token("a")
        let _: AIUpdate<SummarizeAction> = SummarizeUpdate.token("b")
        let _: AIUpdate<ToneAdjustmentAction> = ToneAdjustmentUpdate.token("c")
        let _: AIUpdate<GhostTextAction> = GhostTextUpdate.token("d")

        // If this compiles, the aliases are correctly wired
        #expect(true)
    }
}
