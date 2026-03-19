import Testing
import Foundation
@testable import EMCore

@Suite("Error Severity Classification")
struct ErrorSeverityTests {

    @Test("Save failure is recoverable")
    func saveFailedIsRecoverable() {
        let error = EMError.file(.saveFailed(url: URL(fileURLWithPath: "/test.md"), underlying: NSError(domain: "", code: 0)))
        #expect(error.severity == .recoverable)
    }

    @Test("Access denied is recoverable")
    func accessDeniedIsRecoverable() {
        let error = EMError.file(.accessDenied(url: URL(fileURLWithPath: "/test.md")))
        #expect(error.severity == .recoverable)
    }

    @Test("Externally deleted is data-loss-risk")
    func externallyDeletedIsDataLossRisk() {
        let error = EMError.file(.externallyDeleted(url: URL(fileURLWithPath: "/test.md")))
        #expect(error.severity == .dataLossRisk)
    }

    @Test("File not found is data-loss-risk")
    func notFoundIsDataLossRisk() {
        let error = EMError.file(.notFound(url: URL(fileURLWithPath: "/test.md")))
        #expect(error.severity == .dataLossRisk)
    }

    @Test("Non-UTF-8 is informational")
    func notUTF8IsInformational() {
        let error = EMError.file(.notUTF8(url: URL(fileURLWithPath: "/test.md")))
        #expect(error.severity == .informational)
    }

    @Test("Too large is informational")
    func tooLargeIsInformational() {
        let error = EMError.file(.tooLarge(url: URL(fileURLWithPath: "/test.md"), sizeBytes: 100_000_000))
        #expect(error.severity == .informational)
    }

    @Test("Bookmark stale is informational")
    func bookmarkStaleIsInformational() {
        let error = EMError.file(.bookmarkStale(url: URL(fileURLWithPath: "/test.md")))
        #expect(error.severity == .informational)
    }

    @Test("AI inference timeout is recoverable")
    func aiTimeoutIsRecoverable() {
        let error = EMError.ai(.inferenceTimeout)
        #expect(error.severity == .recoverable)
    }

    @Test("AI cloud unavailable is recoverable")
    func aiCloudUnavailableIsRecoverable() {
        let error = EMError.ai(.cloudUnavailable)
        #expect(error.severity == .recoverable)
    }

    @Test("AI model not downloaded is informational")
    func aiModelNotDownloadedIsInformational() {
        let error = EMError.ai(.modelNotDownloaded)
        #expect(error.severity == .informational)
    }

    @Test("AI device not supported is informational")
    func aiDeviceNotSupportedIsInformational() {
        let error = EMError.ai(.deviceNotSupported)
        #expect(error.severity == .informational)
    }

    @Test("AI subscription required is informational")
    func aiSubscriptionRequiredIsInformational() {
        let error = EMError.ai(.subscriptionRequired)
        #expect(error.severity == .informational)
    }

    @Test("Parse timeout is informational")
    func parseTimeoutIsInformational() {
        let error = EMError.parse(.timeout(lineCount: 10_000))
        #expect(error.severity == .informational)
    }

    @Test("Unexpected error is recoverable")
    func unexpectedIsRecoverable() {
        let error = EMError.unexpected(underlying: NSError(domain: "test", code: 42))
        #expect(error.severity == .recoverable)
    }
}

@Suite("PresentableError")
struct PresentableErrorTests {

    @Test("EMError produces presentable error with correct message")
    func presentableFromEMError() {
        let error = EMError.file(.saveFailed(url: URL(fileURLWithPath: "/test.md"), underlying: NSError(domain: "", code: 0)))
        let presentable = error.presentable()
        #expect(presentable.message.contains("Couldn't save"))
        #expect(presentable.severity == .recoverable)
        #expect(presentable.recoveryActions.isEmpty)
    }

    @Test("PresentableError has unique ID")
    func uniqueIDs() {
        let a = PresentableError(message: "Error", severity: .recoverable)
        let b = PresentableError(message: "Error", severity: .recoverable)
        #expect(a.id != b.id)
    }

    @Test("PresentableError preserves recovery actions")
    func recoveryActions() {
        let action = RecoveryAction(label: "Retry") {}
        let error = EMError.ai(.inferenceTimeout)
        let presentable = error.presentable(recoveryActions: [action])
        #expect(presentable.recoveryActions.count == 1)
        #expect(presentable.recoveryActions[0].label == "Retry")
    }
}
