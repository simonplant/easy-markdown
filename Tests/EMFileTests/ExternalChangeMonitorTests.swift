import Testing
import Foundation
@testable import EMFile

@Suite("ExternalChangeMonitor")
struct ExternalChangeMonitorTests {

    @MainActor
    @Test("Monitor starts and stops without error")
    func startStop() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let monitor = ExternalChangeMonitor(url: url)

        monitor.startMonitoring()
        monitor.stopMonitoring()
    }

    @MainActor
    @Test("Double start is idempotent")
    func doubleStart() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let monitor = ExternalChangeMonitor(url: url)

        monitor.startMonitoring()
        monitor.startMonitoring() // Should not register twice
        monitor.stopMonitoring()
    }

    @MainActor
    @Test("Double stop is safe")
    func doubleStop() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let monitor = ExternalChangeMonitor(url: url)

        monitor.startMonitoring()
        monitor.stopMonitoring()
        monitor.stopMonitoring() // Should not crash
    }

    @MainActor
    @Test("Pause and resume")
    func pauseResume() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let monitor = ExternalChangeMonitor(url: url)

        #expect(monitor.isPaused == false)
        monitor.pause()
        #expect(monitor.isPaused == true)
        monitor.resume()
        #expect(monitor.isPaused == false)
    }

    @MainActor
    @Test("Presents correct URL")
    func presentedURL() {
        let url = URL(fileURLWithPath: "/tmp/monitor-test.md")
        let monitor = ExternalChangeMonitor(url: url)

        #expect(monitor.presentedItemURL == url)
    }
}
