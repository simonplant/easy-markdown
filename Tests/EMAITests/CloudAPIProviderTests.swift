import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("CloudAPIProvider")
struct CloudAPIProviderTests {

    private func makeProvider(isProActive: Bool = false) -> CloudAPIProvider {
        CloudAPIProvider(
            relayURL: URL(string: "https://api.easymarkdown.app/v1/generate")!,
            networkMonitor: NetworkMonitor(),
            subscriptionStatus: MockSubscriptionStatus(isActive: isProActive)
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
}
