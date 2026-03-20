import Testing
import Foundation
@testable import EMAI
@testable import EMCore

/// Mock subscription status for testing.
struct MockSubscriptionStatus: SubscriptionStatusProviding {
    var isProSubscriptionActive: Bool { isActive }
    var subscriptionExpirationDate: Date? { expiration }

    let isActive: Bool
    let expiration: Date?

    init(isActive: Bool = false, expiration: Date? = nil) {
        self.isActive = isActive
        self.expiration = expiration
    }
}

@MainActor
@Suite("AIProviderManager")
struct AIProviderManagerTests {

    private func makeManager(
        isProActive: Bool = false,
        modelDirectory: URL? = nil
    ) -> AIProviderManager {
        let dir = modelDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-test-\(UUID().uuidString)")
        return AIProviderManager(
            subscriptionStatus: MockSubscriptionStatus(isActive: isProActive),
            modelDirectory: dir
        )
    }

    // MARK: - Device Capability Gating (AC-6)

    @Test("shouldShowAIUI reflects device capability")
    func shouldShowAIUIReflectsCapability() {
        let manager = makeManager()
        // On test host (simulator/Mac), detect() returns .fullAI
        let expected = DeviceCapability.detect() == .fullAI
        #expect(manager.shouldShowAIUI == expected)
    }

    @Test("deviceCapability is set from detect()")
    func deviceCapabilityFromDetect() {
        let manager = makeManager()
        #expect(manager.deviceCapability == DeviceCapability.detect())
    }

    // MARK: - Provider Selection (A-030)

    @Test("selectProvider returns nil when no providers available and no model")
    func selectProviderNoModel() async {
        let manager = makeManager()
        let context = manager.makeContext()
        let provider = await manager.selectProvider(for: .improve, context: context)

        // On a capable device with no model downloaded, local provider is unavailable
        // Cloud requires subscription, platform AI is a stub
        if manager.deviceCapability == .fullAI {
            // Only cloud could work if subscribed; with no subscription, nil
            #expect(provider == nil)
        } else {
            #expect(provider == nil)
        }
    }

    @Test("selectProvider returns cloud provider when subscribed")
    func selectProviderWithSubscription() async {
        let manager = makeManager(isProActive: true)
        let context = AIContext(
            deviceCapability: .fullAI,
            isOffline: false,
            subscriptionStatus: MockSubscriptionStatus(isActive: true)
        )
        let provider = await manager.selectProvider(for: .translate(targetLanguage: "es"), context: context)

        // Cloud supports all actions and subscription is active
        if manager.deviceCapability == .fullAI {
            #expect(provider?.name == "Pro AI")
        }
    }

    // MARK: - Context Creation

    @Test("makeContext creates valid context")
    func makeContextValid() {
        let manager = makeManager()
        let context = manager.makeContext()
        #expect(context.deviceCapability == manager.deviceCapability)
    }

    // MARK: - Refresh Availability

    @Test("refreshAvailability updates state")
    func refreshAvailabilityUpdates() async {
        let manager = makeManager()
        await manager.refreshAvailability()

        // Without a downloaded model and no platform AI,
        // availability depends on cloud subscription
        if manager.deviceCapability == .noAI {
            #expect(manager.isAIAvailable == false)
        }
    }
}
