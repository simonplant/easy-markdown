import Foundation
import StoreKit
import EMCore

/// Manages Pro AI subscriptions via StoreKit 2 per [A-012] and [D-BIZ-7].
/// Conforms to `SubscriptionStatusProviding` (defined in EMCore) so EMAI can
/// check subscription status without depending on EMCloud per [A-057].
///
/// Full subscription management (purchase, cancel, upgrade) ships with FEAT-046.
/// This implementation covers status checking and caching needed by the purchase system.
@MainActor
@Observable
public final class SubscriptionManager: SubscriptionStatusProviding {
    /// Whether the user has an active Pro AI subscription.
    public private(set) var isProActive: Bool = false

    /// When the current subscription period expires, if applicable.
    public private(set) var expirationDate: Date? {
        didSet { _cachedExpirationDate = expirationDate }
    }

    /// Cached copy for the synchronous protocol requirement.
    /// Updated whenever expirationDate changes on the main actor.
    private nonisolated(unsafe) var _cachedExpirationDate: Date?

    private var transactionListenerTask: Task<Void, Never>?

    public init() {
        transactionListenerTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task {
            await refreshSubscriptionState()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - SubscriptionStatusProviding

    public nonisolated var isProSubscriptionActive: Bool {
        get async {
            await isProActive
        }
    }

    public nonisolated var subscriptionExpirationDate: Date? {
        _cachedExpirationDate
    }

    // MARK: - State

    /// Refreshes subscription state by checking current entitlements.
    public func refreshSubscriptionState() async {
        let subscriptionIDs: Set<String> = [
            ProductID.proAIMonthly,
            ProductID.proAIAnnual,
        ]

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue else { continue }
            if subscriptionIDs.contains(transaction.productID) {
                isProActive = true
                expirationDate = transaction.expirationDate
                return
            }
        }
        isProActive = false
        expirationDate = nil
    }

    // MARK: - Private

    /// Listens for subscription transaction updates.
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let _ = try? result.payloadValue else { continue }
            await refreshSubscriptionState()
        }
    }
}
