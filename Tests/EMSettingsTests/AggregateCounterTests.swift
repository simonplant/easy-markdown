import Testing
import Foundation
@testable import EMSettings

@MainActor
@Suite("On-Device Aggregate Counters")
struct AggregateCounterTests {

    private func makeManager() -> (SettingsManager, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = SettingsManager(defaults: defaults)
        return (manager, defaults)
    }

    // MARK: - Defaults

    @Test("All counters default to zero")
    func defaultValues() {
        let (m, _) = makeManager()
        #expect(m.aiImproveCount == 0)
        #expect(m.aiSummarizeCount == 0)
        #expect(m.aiContinueAcceptCount == 0)
        #expect(m.doctorFixAcceptCount == 0)
        #expect(m.documentsOpenedCount == 0)
        #expect(m.daysActiveCount == 0)
    }

    // MARK: - Increment and Persist

    @Test("AI improve counter increments and persists")
    func aiImproveIncrement() {
        let (m, d) = makeManager()
        m.recordAIImprove()
        m.recordAIImprove()
        #expect(m.aiImproveCount == 2)
        #expect(d.integer(forKey: "em_counter_aiImprove") == 2)
    }

    @Test("AI summarize counter increments and persists")
    func aiSummarizeIncrement() {
        let (m, d) = makeManager()
        m.recordAISummarize()
        #expect(m.aiSummarizeCount == 1)
        #expect(d.integer(forKey: "em_counter_aiSummarize") == 1)
    }

    @Test("AI continue accept counter increments and persists")
    func aiContinueAcceptIncrement() {
        let (m, d) = makeManager()
        m.recordAIContinueAccept()
        m.recordAIContinueAccept()
        m.recordAIContinueAccept()
        #expect(m.aiContinueAcceptCount == 3)
        #expect(d.integer(forKey: "em_counter_aiContinueAccept") == 3)
    }

    @Test("Doctor fix accept counter increments and persists")
    func doctorFixAcceptIncrement() {
        let (m, d) = makeManager()
        m.recordDoctorFixAccept()
        #expect(m.doctorFixAcceptCount == 1)
        #expect(d.integer(forKey: "em_counter_doctorFixAccept") == 1)
    }

    @Test("Documents opened counter increments and persists")
    func documentsOpenedIncrement() {
        let (m, d) = makeManager()
        m.recordDocumentOpened()
        m.recordDocumentOpened()
        #expect(m.documentsOpenedCount == 2)
        #expect(d.integer(forKey: "em_counter_documentsOpened") == 2)
    }

    @Test("Days active increments once per calendar day")
    func daysActiveIncrementsOncePerDay() {
        let (m, _) = makeManager()
        m.recordDayActive()
        let countAfterFirst = m.daysActiveCount
        m.recordDayActive()
        #expect(m.daysActiveCount == countAfterFirst)
        #expect(countAfterFirst == 1)
    }

    @Test("Days active counter persists to UserDefaults")
    func daysActivePersists() {
        let (m, d) = makeManager()
        m.recordDayActive()
        #expect(d.integer(forKey: "em_counter_daysActive") == 1)
        #expect(d.string(forKey: "em_counter_lastActiveDate") != nil)
    }

    // MARK: - Restoration

    @Test("Counters restore from UserDefaults on init")
    func restoresFromDefaults() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.set(5, forKey: "em_counter_aiImprove")
        defaults.set(3, forKey: "em_counter_aiSummarize")
        defaults.set(12, forKey: "em_counter_aiContinueAccept")
        defaults.set(7, forKey: "em_counter_doctorFixAccept")
        defaults.set(42, forKey: "em_counter_documentsOpened")
        defaults.set(10, forKey: "em_counter_daysActive")

        let m = SettingsManager(defaults: defaults)

        #expect(m.aiImproveCount == 5)
        #expect(m.aiSummarizeCount == 3)
        #expect(m.aiContinueAcceptCount == 12)
        #expect(m.doctorFixAcceptCount == 7)
        #expect(m.documentsOpenedCount == 42)
        #expect(m.daysActiveCount == 10)
    }

    // MARK: - No External Storage

    @Test("Counters use only UserDefaults — reinstall resets them")
    func reinstallResetsCounters() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate usage
        let m1 = SettingsManager(defaults: defaults)
        m1.recordAIImprove()
        m1.recordDocumentOpened()
        m1.recordDayActive()
        #expect(m1.aiImproveCount == 1)

        // Simulate reinstall: fresh UserDefaults (no data carried over)
        let freshSuiteName = "test.\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuiteName)!
        let m2 = SettingsManager(defaults: freshDefaults)
        #expect(m2.aiImproveCount == 0)
        #expect(m2.documentsOpenedCount == 0)
        #expect(m2.daysActiveCount == 0)
    }
}
