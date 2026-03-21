import Foundation

/// Bridge protocol between EMCloud and EMAI per [A-057].
/// Defined in EMCore. Implemented by EMCloud. Consumed by EMAI.
/// EMApp injects the EMCloud implementation into EMAI at app launch.
public protocol SubscriptionStatusProviding: Sendable {
    /// Whether the user has an active Pro AI subscription.
    var isProSubscriptionActive: Bool { get async }

    /// When the current subscription expires, if applicable.
    var subscriptionExpirationDate: Date? { get }

    /// The signed transaction JWS for server-side subscription validation.
    /// Used by CloudAPIProvider to authenticate requests to the relay server.
    /// Returns `nil` if no active subscription transaction is available.
    var subscriptionReceiptJWS: String? { get async }
}
