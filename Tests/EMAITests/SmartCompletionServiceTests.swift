import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@MainActor
@Suite("SmartCompletionService")
struct SmartCompletionServiceTests {

    private func makeManager(
        modelDirectory: URL? = nil
    ) -> AIProviderManager {
        let dir = modelDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-smart-test-\(UUID().uuidString)")
        return AIProviderManager(
            subscriptionStatus: MockSubscriptionStatus(isActive: false),
            modelDirectory: dir
        )
    }

    // MARK: - Initial State

    @Test("service starts in idle state")
    func initialState() {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)
        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
        #expect(service.completionText.isEmpty)
    }

    // MARK: - Start Completing

    @Test("startCompleting sets state to generating for table header")
    func startCompletingTableHeader() async {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        let stream = service.startCompleting(
            structureType: .tableHeader(columns: ["Name", "Email"]),
            precedingText: "| Name | Email |\n"
        )

        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }

        // Consume stream to let it complete
        for await _ in stream { break }
    }

    @Test("startCompleting sets state to generating for list item")
    func startCompletingListItem() async {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        let stream = service.startCompleting(
            structureType: .listItem(prefix: "- ", items: ["apples", "bananas", "cherries"]),
            precedingText: "- apples\n- bananas\n- cherries\n"
        )

        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }

        for await _ in stream { break }
    }

    @Test("startCompleting sets state to generating for front matter")
    func startCompletingFrontMatter() async {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        let stream = service.startCompleting(
            structureType: .frontMatter(existingKeys: ["title", "date"]),
            precedingText: "---\ntitle: My Post\ndate: 2026-03-23\n"
        )

        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }

        for await _ in stream { break }
    }

    // MARK: - Cancel

    @Test("cancel resets generating state to cancelled")
    func cancelResetsState() {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        _ = service.startCompleting(
            structureType: .tableHeader(columns: ["A", "B"]),
            precedingText: "| A | B |\n"
        )
        service.cancel()

        guard case .cancelled = service.state else {
            Issue.record("Expected .cancelled state")
            return
        }
    }

    @Test("cancel from idle stays idle")
    func cancelFromIdleStaysIdle() {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        service.cancel()

        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
    }

    // MARK: - Reset

    @Test("reset clears all state")
    func resetClearsState() {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        _ = service.startCompleting(
            structureType: .tableHeader(columns: ["X"]),
            precedingText: "| X |\n"
        )
        service.reset()

        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
        #expect(service.completionText.isEmpty)
    }

    // MARK: - Second start cancels first

    @Test("starting a new session cancels the previous one")
    func secondStartCancelsPrevious() {
        let manager = makeManager()
        let service = SmartCompletionService(providerManager: manager)

        _ = service.startCompleting(
            structureType: .tableHeader(columns: ["A"]),
            precedingText: "First"
        )
        _ = service.startCompleting(
            structureType: .listItem(prefix: "- ", items: ["a", "b"]),
            precedingText: "Second"
        )

        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }
        #expect(service.completionText.isEmpty)
    }
}
