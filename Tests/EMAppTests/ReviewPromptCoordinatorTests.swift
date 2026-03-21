import Testing
import Foundation
@testable import EMApp
@testable import EMSettings

@MainActor
@Suite("ReviewPromptCoordinator")
struct ReviewPromptCoordinatorTests {

    private func makeSettings() -> SettingsManager {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SettingsManager(defaults: defaults)
    }

    /// Creates a SettingsManager with counters exactly at the eligibility thresholds.
    /// Sets values directly in UserDefaults since `recordDayActive()` is idempotent per day.
    private func makeEligibleSettings() -> SettingsManager {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(7, forKey: "em_counter_daysActive")
        defaults.set(10, forKey: "em_counter_aiImprove")
        return SettingsManager(defaults: defaults)
    }

    // MARK: - Eligibility

    @Test("Not eligible with zero counters")
    func notEligibleByDefault() {
        let settings = makeSettings()
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(!coordinator.isEligible)
    }

    @Test("Not eligible with only days active met")
    func notEligibleDaysOnly() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(7, forKey: "em_counter_daysActive")
        let settings = SettingsManager(defaults: defaults)
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(!coordinator.isEligible)
    }

    @Test("Not eligible with only AI uses met")
    func notEligibleAIOnly() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(10, forKey: "em_counter_aiImprove")
        let settings = SettingsManager(defaults: defaults)
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(!coordinator.isEligible)
    }

    @Test("Not eligible at 6 days and 9 AI uses")
    func notEligibleJustBelow() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(6, forKey: "em_counter_daysActive")
        defaults.set(9, forKey: "em_counter_aiImprove")
        let settings = SettingsManager(defaults: defaults)
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(!coordinator.isEligible)
    }

    @Test("Eligible at exactly 7 days and 10 AI uses")
    func eligibleAtThreshold() {
        let settings = makeEligibleSettings()
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(coordinator.isEligible)
    }

    @Test("Eligible with mixed AI action types")
    func eligibleMixedActions() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(7, forKey: "em_counter_daysActive")
        defaults.set(3, forKey: "em_counter_aiImprove")
        defaults.set(3, forKey: "em_counter_aiSummarize")
        defaults.set(2, forKey: "em_counter_aiContinueAccept")
        defaults.set(2, forKey: "em_counter_doctorFixAccept")
        let settings = SettingsManager(defaults: defaults)
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(settings.totalAIUsageCount == 10)
        #expect(coordinator.isEligible)
    }

    // MARK: - One-shot behavior

    @Test("Not eligible after already prompted")
    func notEligibleAfterPrompted() {
        let settings = makeEligibleSettings()
        settings.hasPromptedForReview = true
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(!coordinator.isEligible)
    }

    @Test("requestReviewIfEligible sets flag when eligible")
    func setsFlag() {
        let settings = makeEligibleSettings()
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(coordinator.isEligible)

        coordinator.requestReviewIfEligible()
        #expect(settings.hasPromptedForReview)
        #expect(!coordinator.isEligible)
    }

    @Test("requestReviewIfEligible does not set flag when not eligible")
    func doesNotSetFlagWhenIneligible() {
        let settings = makeSettings()
        let coordinator = ReviewPromptCoordinator(settings: settings)

        coordinator.requestReviewIfEligible()
        #expect(!settings.hasPromptedForReview)
    }

    @Test("Second call to requestReviewIfEligible is a no-op")
    func secondCallNoOp() {
        let settings = makeEligibleSettings()
        let coordinator = ReviewPromptCoordinator(settings: settings)

        coordinator.requestReviewIfEligible()
        #expect(settings.hasPromptedForReview)

        // Second call should be safe and change nothing
        coordinator.requestReviewIfEligible()
        #expect(settings.hasPromptedForReview)
    }

    // MARK: - No prompt without AI

    @Test("If user has not used AI features, prompt never appears regardless of time")
    func noPromptWithoutAIRegardlessOfTime() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(100, forKey: "em_counter_daysActive")
        let settings = SettingsManager(defaults: defaults)
        let coordinator = ReviewPromptCoordinator(settings: settings)
        #expect(!coordinator.isEligible)
    }

    // MARK: - totalAIUsageCount

    @Test("totalAIUsageCount sums all AI counters")
    func totalAIUsageCount() {
        let settings = makeSettings()
        settings.recordAIImprove()
        settings.recordAISummarize()
        settings.recordAIContinueAccept()
        settings.recordDoctorFixAccept()
        #expect(settings.totalAIUsageCount == 4)
    }

    // MARK: - Persistence

    @Test("hasPromptedForReview persists across restarts")
    func flagPersistsAcrossRestarts() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // First session: mark as prompted
        let first = SettingsManager(defaults: defaults)
        first.hasPromptedForReview = true

        // Second session: flag is still set
        let second = SettingsManager(defaults: defaults)
        #expect(second.hasPromptedForReview)
    }
}
