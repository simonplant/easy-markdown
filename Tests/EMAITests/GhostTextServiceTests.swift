import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@MainActor
@Suite("GhostTextService")
struct GhostTextServiceTests {

    private func makeManager(
        modelDirectory: URL? = nil
    ) -> AIProviderManager {
        let dir = modelDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-ghost-test-\(UUID().uuidString)")
        return AIProviderManager(
            subscriptionStatus: MockSubscriptionStatus(isActive: false),
            modelDirectory: dir
        )
    }

    // MARK: - Initial State

    @Test("service starts in idle state")
    func initialState() {
        let manager = makeManager()
        let service = GhostTextService(providerManager: manager)
        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
        #expect(service.precedingText.isEmpty)
        #expect(service.continuationText.isEmpty)
    }

    // MARK: - Start Generating

    @Test("startGenerating sets state to generating")
    func startGeneratingSetsState() async {
        let manager = makeManager()
        let service = GhostTextService(providerManager: manager)

        let stream = service.startGenerating(precedingText: "The quick brown fox")

        // State should be generating
        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }
        #expect(service.precedingText == "The quick brown fox")

        // Consume stream to let it complete
        for await _ in stream { break }
    }

    @Test("startGenerating stores preceding text")
    func startGeneratingStoresPrecedingText() {
        let manager = makeManager()
        let service = GhostTextService(providerManager: manager)

        _ = service.startGenerating(precedingText: "Hello world.")

        #expect(service.precedingText == "Hello world.")
    }

    // MARK: - Cancel

    @Test("cancel resets generating state to cancelled")
    func cancelResetsState() {
        let manager = makeManager()
        let service = GhostTextService(providerManager: manager)

        _ = service.startGenerating(precedingText: "Some text")
        service.cancel()

        guard case .cancelled = service.state else {
            Issue.record("Expected .cancelled state")
            return
        }
    }

    @Test("cancel from idle stays idle")
    func cancelFromIdleStaysIdle() {
        let manager = makeManager()
        let service = GhostTextService(providerManager: manager)

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
        let service = GhostTextService(providerManager: manager)

        _ = service.startGenerating(precedingText: "Text")
        service.reset()

        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
        #expect(service.precedingText.isEmpty)
        #expect(service.continuationText.isEmpty)
    }

    // MARK: - Second start cancels first

    @Test("starting a new session cancels the previous one")
    func secondStartCancelsPrevious() {
        let manager = makeManager()
        let service = GhostTextService(providerManager: manager)

        _ = service.startGenerating(precedingText: "First")
        _ = service.startGenerating(precedingText: "Second")

        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }
        #expect(service.precedingText == "Second")
        #expect(service.continuationText.isEmpty)
    }
}
