import Foundation
import StoreKit
import EMCore

/// Product identifiers for App Store purchases per [A-012].
public enum ProductID {
    /// One-time app purchase ($9.99) per [D-BIZ-2].
    public static let appPurchase = "com.easymarkdown.app"
    /// Pro AI monthly subscription ($3.99/mo) per [D-BIZ-7].
    public static let proAIMonthly = "com.easymarkdown.proai.monthly"
    /// Pro AI annual subscription ($29.99/yr) per [D-BIZ-7].
    public static let proAIAnnual = "com.easymarkdown.proai.annual"
}

/// Represents the user's purchase state for the one-time app purchase.
public enum PurchaseState: Sendable {
    /// Purchase state has not been determined yet.
    case unknown
    /// The user has purchased the app.
    case purchased
    /// The user has not purchased the app.
    case notPurchased
}

/// Manages the one-time $9.99 app purchase via StoreKit 2 per [A-012] and [D-BIZ-1].
///
/// Handles:
/// - Purchase flow via the standard App Store sheet
/// - Receipt validation using StoreKit 2's built-in `Transaction.currentEntitlements`
/// - Restore purchases for reinstall or device switch
/// - Family sharing eligibility
///
/// The app must be fully functional after purchase with no additional gates per [D-BIZ-1].
@MainActor
@Observable
public final class PurchaseManager {
    /// Current purchase state for the one-time app purchase.
    public private(set) var purchaseState: PurchaseState = .unknown

    /// The StoreKit product for the app purchase, fetched from the App Store.
    public private(set) var appProduct: Product?

    /// Whether a purchase or restore operation is in progress.
    public private(set) var isPurchasing: Bool = false

    private var transactionListenerTask: Task<Void, Never>?

    public init() {
        transactionListenerTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task {
            await loadProducts()
            await refreshPurchaseState()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Purchase

    /// Initiates the one-time app purchase via the standard App Store flow.
    /// Returns the verified transaction on success, or throws on failure.
    @discardableResult
    public func purchaseApp() async throws -> Transaction {
        guard let product = appProduct else {
            throw EMError.purchase(.productNotFound)
        }
        isPurchasing = true
        defer { isPurchasing = false }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw EMError.purchase(.purchaseFailed(underlying: error))
        }

        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            await transaction.finish()
            purchaseState = .purchased
            return transaction

        case .userCancelled:
            throw EMError.purchase(.userCancelled)

        case .pending:
            throw EMError.purchase(.purchasePending)

        @unknown default:
            throw EMError.purchase(.purchaseFailed(underlying: nil))
        }
    }

    // MARK: - Restore

    /// Restores purchases for users who reinstall or switch devices.
    /// Triggers App Store sync and re-checks entitlements.
    public func restorePurchases() async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
        } catch {
            throw EMError.purchase(.restoreFailed(underlying: error))
        }
        await refreshPurchaseState()
    }

    // MARK: - Entitlement Check

    /// Refreshes purchase state by checking current entitlements.
    /// Called on launch, after purchase, and after restore.
    public func refreshPurchaseState() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue else { continue }
            if transaction.productID == ProductID.appPurchase {
                purchaseState = .purchased
                return
            }
        }
        purchaseState = .notPurchased
    }

    // MARK: - Private

    /// Loads the app purchase product from the App Store.
    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [ProductID.appPurchase])
            appProduct = products.first
        } catch {
            // Product fetch failure is non-fatal; purchaseState remains .unknown
            // and the purchase button will be disabled.
        }
    }

    /// Listens for transaction updates (renewals, revocations, family sharing changes).
    /// Runs for the lifetime of the manager per StoreKit 2 best practices.
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? verifiedTransaction(from: result) else { continue }
            await transaction.finish()
            await refreshPurchaseState()
        }
    }

    /// Extracts a verified transaction, throwing on verification failure.
    private func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw EMError.purchase(.receiptValidationFailed(underlying: error))
        }
    }
}
