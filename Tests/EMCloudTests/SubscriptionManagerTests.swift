import Testing
import EMCore

@testable import EMCloud

@Suite("SubscriptionManager")
struct SubscriptionManagerTests {

    @Test("SubscriptionPlan enum has both cases")
    func subscriptionPlanCases() {
        let monthly: SubscriptionPlan = .monthly
        let annual: SubscriptionPlan = .annual

        switch monthly {
        case .monthly: break
        case .annual: Issue.record("Expected .monthly")
        }
        switch annual {
        case .annual: break
        case .monthly: Issue.record("Expected .annual")
        }
    }

    @Test("Product IDs for subscriptions are correct")
    func subscriptionProductIDs() {
        #expect(ProductID.proAIMonthly == "com.easymarkdown.proai.monthly")
        #expect(ProductID.proAIAnnual == "com.easymarkdown.proai.annual")
    }

    @Test("Subscription error types have user-facing descriptions")
    func subscriptionErrorDescriptions() {
        let subscriptionRequired = EMError.ai(.subscriptionRequired)
        #expect(subscriptionRequired.errorDescription != nil)
        #expect(subscriptionRequired.errorDescription!.contains("Pro AI"))

        let subscriptionExpired = EMError.ai(.subscriptionExpired)
        #expect(subscriptionExpired.errorDescription != nil)
        #expect(subscriptionExpired.errorDescription!.contains("expired"))

        let cloudUnavailable = EMError.ai(.cloudUnavailable)
        #expect(cloudUnavailable.errorDescription != nil)
    }

    @Test("Subscription error severity classification")
    func subscriptionErrorSeverity() {
        #expect(EMError.ai(.subscriptionRequired).severity == .informational)
        #expect(EMError.ai(.subscriptionExpired).severity == .informational)
        #expect(EMError.ai(.cloudUnavailable).severity == .recoverable)
        #expect(EMError.ai(.inferenceTimeout).severity == .recoverable)
    }
}
