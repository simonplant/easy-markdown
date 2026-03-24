import SwiftUI

/// Navigation destinations for the app per [A-058].
public enum AppRoute: Hashable {
    case home
    case editor
}

/// Sheet presentations.
public enum SheetRoute: Identifiable, Hashable {
    case settings
    case subscriptionOffer
    case gitHubRepoBrowser

    public var id: Self { self }
}
