import Testing
import Foundation
@testable import EMCore

@Suite("ImproveWritingUpdate")
struct ImproveWritingUpdateTests {

    @Test("token case carries text")
    func tokenCase() {
        let update = ImproveWritingUpdate.token("Hello")
        if case .token(let text) = update {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected .token case")
        }
    }

    @Test("completed case carries full text")
    func completedCase() {
        let update = ImproveWritingUpdate.completed(fullText: "Hello world")
        if case .completed(let text) = update {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected .completed case")
        }
    }

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
}
