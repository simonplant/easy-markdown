import Testing
import Foundation
@testable import EMAI

@Suite("ApplePlatformAIProvider")
struct ApplePlatformAIProviderTests {

    @Test("name is Apple AI")
    func name() {
        let provider = ApplePlatformAIProvider()
        #expect(provider.name == "Apple AI")
    }

    @Test("isAvailable is always false (stub)")
    func unavailable() async {
        let provider = ApplePlatformAIProvider()
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("supports returns false for all actions (stub)")
    func supportsNothing() {
        let provider = ApplePlatformAIProvider()
        #expect(provider.supports(action: .improve) == false)
        #expect(provider.supports(action: .summarize) == false)
        #expect(provider.supports(action: .continueWriting) == false)
    }

    @Test("requiresNetwork is false")
    func noNetwork() {
        let provider = ApplePlatformAIProvider()
        #expect(provider.requiresNetwork == false)
    }

    @Test("requiresSubscription is false")
    func noSubscription() {
        let provider = ApplePlatformAIProvider()
        #expect(provider.requiresSubscription == false)
    }
}
