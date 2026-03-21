import Testing
import EMCore

@testable import EMCloud

@Suite("PurchaseManager")
struct PurchaseManagerTests {

    @Test("Product IDs have expected values")
    func productIDs() {
        #expect(ProductID.appPurchase == "com.easymarkdown.app")
        #expect(ProductID.proAIMonthly == "com.easymarkdown.proai.monthly")
        #expect(ProductID.proAIAnnual == "com.easymarkdown.proai.annual")
    }

    @Test("PurchaseState defaults to unknown")
    func purchaseStateDefault() {
        let state: PurchaseState = .unknown
        switch state {
        case .unknown: break // expected
        case .purchased, .notPurchased:
            Issue.record("Expected .unknown")
        }
    }

    @Test("PurchaseError has user-facing descriptions")
    func purchaseErrorDescriptions() {
        let productNotFound = EMError.purchase(.productNotFound)
        #expect(productNotFound.errorDescription != nil)

        let purchaseFailed = EMError.purchase(.purchaseFailed(underlying: nil))
        #expect(purchaseFailed.errorDescription != nil)

        let userCancelled = EMError.purchase(.userCancelled)
        #expect(userCancelled.errorDescription == nil) // Silent cancel

        let pending = EMError.purchase(.purchasePending)
        #expect(pending.errorDescription != nil)

        let receiptFailed = EMError.purchase(.receiptValidationFailed(
            underlying: NSError(domain: "test", code: 0)
        ))
        #expect(receiptFailed.errorDescription != nil)

        let restoreFailed = EMError.purchase(.restoreFailed(
            underlying: NSError(domain: "test", code: 0)
        ))
        #expect(restoreFailed.errorDescription != nil)
    }

    @Test("PurchaseError severity classification")
    func purchaseErrorSeverity() {
        #expect(EMError.purchase(.userCancelled).severity == .informational)
        #expect(EMError.purchase(.purchasePending).severity == .informational)
        #expect(EMError.purchase(.purchaseFailed(underlying: nil)).severity == .recoverable)
        #expect(EMError.purchase(.restoreFailed(
            underlying: NSError(domain: "test", code: 0)
        )).severity == .recoverable)
        #expect(EMError.purchase(.productNotFound).severity == .recoverable)
        #expect(EMError.purchase(.receiptValidationFailed(
            underlying: NSError(domain: "test", code: 0)
        )).severity == .recoverable)
    }
}
