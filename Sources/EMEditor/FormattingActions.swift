/// Focused state object for formatting action closures per FEAT-076.
/// Wired by TextViewBridge so the floating bar can dispatch
/// Bold/Italic/Link without direct access to the text view.
/// Independently observable and testable.

import Foundation

@MainActor
@Observable
public final class FormattingActions {
    /// Formatting action closure for bold per FEAT-054.
    public var performBold: (() -> Void)?

    /// Formatting action closure for italic per FEAT-054.
    public var performItalic: (() -> Void)?

    /// Formatting action closure for link insertion per FEAT-054.
    public var performLink: (() -> Void)?

    /// When set to true, the floating action bar should move focus to its AI section.
    /// Reset to false after the bar consumes the request.
    public var focusAISection: Bool = false

    public init() {}
}
