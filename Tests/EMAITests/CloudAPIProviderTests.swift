import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("CloudAPIProvider")
struct CloudAPIProviderTests {

    private func makeProvider(
        isProActive: Bool = false,
        receiptJWS: String? = nil
    ) -> CloudAPIProvider {
        CloudAPIProvider(
            relayURL: URL(string: "https://api.easymarkdown.app/v1/generate")!,
            networkMonitor: NetworkMonitor(),
            subscriptionStatus: MockSubscriptionStatus(
                isActive: isProActive,
                receiptJWS: receiptJWS
            )
        )
    }

    @Test("name is Pro AI")
    func name() {
        let provider = makeProvider()
        #expect(provider.name == "Pro AI")
    }

    @Test("requiresNetwork is true")
    func requiresNetwork() {
        let provider = makeProvider()
        #expect(provider.requiresNetwork == true)
    }

    @Test("requiresSubscription is true")
    func requiresSubscription() {
        let provider = makeProvider()
        #expect(provider.requiresSubscription == true)
    }

    @Test("supports all actions")
    func supportsAllActions() {
        let provider = makeProvider()
        #expect(provider.supports(action: .improve) == true)
        #expect(provider.supports(action: .summarize) == true)
        #expect(provider.supports(action: .translate(targetLanguage: "es")) == true)
        #expect(provider.supports(action: .adjustTone(style: .formal)) == true)
        #expect(provider.supports(action: .generateFromPrompt) == true)
        #expect(provider.supports(action: .analyzeDocument) == true)
        #expect(provider.supports(action: .editDiagram) == true)
    }

    @Test("requestTimeoutSeconds is 10")
    func timeout() {
        #expect(CloudAPIProvider.requestTimeoutSeconds == 10)
    }

    @Test("generate throws subscriptionRequired when not subscribed")
    func generateWithoutSubscription() async {
        let provider = makeProvider(isProActive: false)
        let prompt = AIPrompt(
            action: .improve,
            selectedText: "Hello world",
            systemPrompt: "Improve this text."
        )
        let context = AIContext(
            deviceCapability: .fullAI,
            isOffline: false,
            subscriptionStatus: MockSubscriptionStatus(isActive: false)
        )

        var thrownError: Error?
        let stream = provider.generate(prompt: prompt, context: context)
        do {
            for try await _ in stream {
                Issue.record("Expected stream to throw, not yield tokens")
            }
        } catch {
            thrownError = error
        }

        #expect(thrownError is EMError)
        if let emError = thrownError as? EMError, case .ai(.subscriptionRequired) = emError {
            // Expected
        } else {
            Issue.record("Expected EMError.ai(.subscriptionRequired), got \(String(describing: thrownError))")
        }
    }

    @Test("generate throws subscriptionRequired when no receipt JWS available")
    func generateWithoutReceipt() async {
        let provider = makeProvider(isProActive: true, receiptJWS: nil)
        let prompt = AIPrompt(
            action: .improve,
            selectedText: "Hello world",
            systemPrompt: "Improve this text."
        )
        let context = AIContext(
            deviceCapability: .fullAI,
            isOffline: false,
            subscriptionStatus: MockSubscriptionStatus(isActive: true)
        )

        var thrownError: Error?
        let stream = provider.generate(prompt: prompt, context: context)
        do {
            for try await _ in stream {
                Issue.record("Expected stream to throw, not yield tokens")
            }
        } catch {
            thrownError = error
        }

        #expect(thrownError is EMError)
        if let emError = thrownError as? EMError, case .ai(.subscriptionRequired) = emError {
            // Expected — no JWS means can't authenticate
        } else {
            Issue.record("Expected EMError.ai(.subscriptionRequired), got \(String(describing: thrownError))")
        }
    }
}
