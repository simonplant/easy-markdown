import Foundation
import Observation
import EMSettings
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// Coordinates the App Store review prompt per FEAT-069.
///
/// Evaluates eligibility based on on-device aggregate counters (FEAT-060):
/// - At least 7 days of active use
/// - At least 10 AI feature uses (improve, summarize, continue, doctor fix)
/// - Prompt has not been shown before (once per user, ever)
///
/// The prompt is triggered on return to the home screen or after completing
/// an AI action — never during active editing.
@MainActor
@Observable
final class ReviewPromptCoordinator {
    private let settings: SettingsManager

    /// Minimum days of active use before the review prompt can appear.
    static let requiredDaysActive = 7

    /// Minimum total AI feature uses before the review prompt can appear.
    static let requiredAIUses = 10

    /// Initializes with the given settings manager.
    ///
    /// - Parameter settings: The settings manager providing aggregate counters and review state.
    init(settings: SettingsManager) {
        self.settings = settings
    }

    /// Whether the user meets all criteria for a review prompt.
    ///
    /// Returns `true` when:
    /// - The user has never been prompted before
    /// - Days active ≥ 7
    /// - Total AI usage ≥ 10
    var isEligible: Bool {
        !settings.hasPromptedForReview
            && settings.daysActiveCount >= Self.requiredDaysActive
            && settings.totalAIUsageCount >= Self.requiredAIUses
    }

    /// Attempts to show the App Store review prompt if eligible.
    ///
    /// Call this on return to the home screen or after completing an AI action.
    /// If the user is eligible, requests a review via `SKStoreReviewController`
    /// and marks the prompt as shown so it never appears again.
    func requestReviewIfEligible() {
        guard isEligible else { return }

        // SKStoreReviewController requires a window scene on iOS.
        // Set the flag only after successfully requesting review so that
        // a missing scene doesn't consume the one-shot opportunity.
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        settings.hasPromptedForReview = true
        SKStoreReviewController.requestReview(in: scene)
        #elseif os(macOS)
        settings.hasPromptedForReview = true
        SKStoreReviewController.requestReview()
        #endif
    }
}
