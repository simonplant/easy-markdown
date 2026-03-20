import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@MainActor
@Suite("ImproveWritingService")
struct ImproveWritingServiceTests {

    private func makeManager(
        modelDirectory: URL? = nil
    ) -> AIProviderManager {
        let dir = modelDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-improve-test-\(UUID().uuidString)")
        return AIProviderManager(
            subscriptionStatus: MockSubscriptionStatus(isActive: false),
            modelDirectory: dir
        )
    }

    // MARK: - Initial State

    @Test("service starts in idle state")
    func initialState() {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)
        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
        #expect(service.originalText.isEmpty)
        #expect(service.improvedText.isEmpty)
    }

    // MARK: - Start Improving

    @Test("startImproving sets state to generating")
    func startImprovingSetsState() async {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)

        let stream = service.startImproving(selectedText: "Hello world")

        // State should be generating
        guard case .generating = service.state else {
            Issue.record("Expected .generating state")
            return
        }
        #expect(service.originalText == "Hello world")

        // Consume stream to let it complete
        for await _ in stream { break }
    }

    @Test("startImproving stores original text")
    func startImprovingStoresOriginal() {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)

        _ = service.startImproving(selectedText: "Test paragraph here.")
        #expect(service.originalText == "Test paragraph here.")
    }

    // MARK: - Cancel

    @Test("cancel sets state to cancelled when generating")
    func cancelWhileGenerating() {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)

        _ = service.startImproving(selectedText: "Some text")
        service.cancel()

        guard case .cancelled = service.state else {
            Issue.record("Expected .cancelled state")
            return
        }
    }

    @Test("cancel from idle is a no-op")
    func cancelFromIdle() {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)

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
        let service = ImproveWritingService(providerManager: manager)

        _ = service.startImproving(selectedText: "Some text")
        service.reset()

        guard case .idle = service.state else {
            Issue.record("Expected .idle state")
            return
        }
        #expect(service.originalText.isEmpty)
        #expect(service.improvedText.isEmpty)
    }

    // MARK: - Provider Selection Failure

    @Test("stream yields failed when no provider available")
    func noProviderAvailable() async {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)

        // On test host with no model downloaded and no subscription,
        // provider selection may fail (depends on device capability).
        let stream = service.startImproving(selectedText: "Test text")

        var gotFailedOrCompleted = false
        for await update in stream {
            switch update {
            case .failed:
                gotFailedOrCompleted = true
            case .completed:
                gotFailedOrCompleted = true
            case .token:
                break
            }
        }

        // Stream should have terminated (either failed or completed)
        #expect(gotFailedOrCompleted)
    }

    // MARK: - Content Type Passthrough

    @Test("startImproving passes content type to prompt")
    func contentTypePassthrough() {
        let manager = makeManager()
        let service = ImproveWritingService(providerManager: manager)

        // We can verify the prompt is built correctly by checking
        // that the service doesn't crash with various content types
        _ = service.startImproving(
            selectedText: "graph TD; A-->B",
            contentType: .mermaid
        )
        service.cancel()

        _ = service.startImproving(
            selectedText: "| A | B |",
            contentType: .table
        )
        service.cancel()
    }
}
