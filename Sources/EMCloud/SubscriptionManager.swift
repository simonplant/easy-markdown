import Foundation
import StoreKit
import os
import EMCore

/// Manages Pro AI subscriptions via StoreKit 2 per [A-012] and [D-BIZ-7].
/// Conforms to `SubscriptionStatusProviding` (defined in EMCore) so EMAI can
/// check subscription status without depending on EMCloud per [A-057].
@MainActor
@Observable
public final class SubscriptionManager: SubscriptionStatusProviding {
    /// Whether the user has an active Pro AI subscription.
    public private(set) var isProActive: Bool = false

    /// When the current subscription period expires, if applicable.
    public private(set) var expirationDate: Date? {
        didSet {
            let newValue = expirationDate
            _cache.withLock { $0.expirationDate = newValue }
        }
    }

    /// The available subscription products fetched from the App Store.
    public private(set) var monthlyProduct: Product?
    public private(set) var annualProduct: Product?

    /// Whether a purchase operation is in progress.
    public private(set) var isPurchasing: Bool = false

    /// Thread-safe cache for synchronous protocol requirements.
    /// Stores (expirationDate, receiptJWS) behind a lock for atomic nonisolated reads.
    private let _cache = OSAllocatedUnfairLock<(expirationDate: Date?, receiptJWS: String?)>(
        initialState: (nil, nil)
    )

    private let transactionListenerHandle = TaskHandle()
    private let logger = Logger(subsystem: "com.easymarkdown.emcloud", category: "subscription")

    public init() {
        transactionListenerHandle.task = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task {
            await loadProducts()
            await refreshSubscriptionState()
        }
    }

    deinit {
        transactionListenerHandle.cancel()
    }

    // MARK: - SubscriptionStatusProviding

    public nonisolated var isProSubscriptionActive: Bool {
        get async {
            await isProActive
        }
    }

    public nonisolated var subscriptionExpirationDate: Date? {
        _cache.withLock { $0.expirationDate }
    }

    /// Returns the cached JWS receipt for server-side validation.
    /// Note: This returns locally cached data, not a live fetch from StoreKit.
    public nonisolated var subscriptionReceiptJWS: String? {
        get async {
            _cache.withLock { $0.receiptJWS }
        }
    }

    // MARK: - Purchase

    /// Purchases a Pro AI subscription.
    /// - Parameter plan: The subscription plan to purchase.
    /// - Returns: The verified transaction on success.
    @discardableResult
    public func purchaseSubscription(plan: SubscriptionPlan) async throws -> Transaction {
        let product: Product?
        switch plan {
        case .monthly: product = monthlyProduct
        case .annual: product = annualProduct
        }

        guard let product else {
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
            await refreshSubscriptionState()
            return transaction

        case .userCancelled:
            throw EMError.purchase(.userCancelled)

        case .pending:
            throw EMError.purchase(.purchasePending)

        @unknown default:
            throw EMError.purchase(.purchaseFailed(underlying: nil))
        }
    }

    /// Restores subscription purchases for reinstall or device switch.
    public func restoreSubscriptions() async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
        } catch {
            throw EMError.purchase(.restoreFailed(underlying: error))
        }
        await refreshSubscriptionState()
    }

    // MARK: - State

    /// Refreshes subscription state by checking current entitlements.
    public func refreshSubscriptionState() async {
        let subscriptionIDs: Set<String> = [
            ProductID.proAIMonthly,
            ProductID.proAIAnnual,
        ]

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if subscriptionIDs.contains(transaction.productID) {
                isProActive = true
                expirationDate = transaction.expirationDate
                _cache.withLock { $0.receiptJWS = result.jwsRepresentation }
                return
            }
        }
        isProActive = false
        expirationDate = nil
        _cache.withLock { $0.receiptJWS = nil }
    }

    // MARK: - Private

    /// Loads subscription products from the App Store.
    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [
                ProductID.proAIMonthly,
                ProductID.proAIAnnual,
            ])
            for product in products {
                switch product.id {
                case ProductID.proAIMonthly:
                    monthlyProduct = product
                case ProductID.proAIAnnual:
                    annualProduct = product
                default:
                    break
                }
            }
        } catch {
            logger.error("Failed to load subscription products: \(error.localizedDescription)")
        }
    }

    /// Listens for subscription transaction updates.
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let _ = try? result.payloadValue else { continue }
            await refreshSubscriptionState()
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

/// Pro AI subscription plans per [D-BIZ-7].
public enum SubscriptionPlan: Sendable {
    /// $3.99/month
    case monthly
    /// $29.99/year
    case annual
}
