import Foundation

/// Bridge protocol between EMCloud and EMAI per [A-057].
/// Defined in EMCore. Implemented by EMCloud. Consumed by EMAI.
/// EMApp injects the EMCloud implementation into EMAI at app launch.
public protocol SubscriptionStatusProviding: Sendable {
    /// Whether the user has an active Pro AI subscription.
    var isProSubscriptionActive: Bool { get async }

    /// When the current subscription expires, if applicable.
    var subscriptionExpirationDate: Date? { get }
}
