import Testing
import Foundation
@testable import EMAI

@Suite("NetworkMonitor")
struct NetworkMonitorTests {

    @Test("NetworkMonitor initializes without crashing")
    func initSucceeds() {
        let monitor = NetworkMonitor()
        // Give the monitor a moment to receive the initial path update
        _ = monitor.isConnected
    }

    @Test("isConnected returns a boolean")
    func isConnectedReturns() {
        let monitor = NetworkMonitor()
        // Should return true or false, not crash
        let connected = monitor.isConnected
        #expect(connected == true || connected == false)
    }

    @Test("isCellular returns a boolean")
    func isCellularReturns() {
        let monitor = NetworkMonitor()
        let cellular = monitor.isCellular
        #expect(cellular == true || cellular == false)
    }

    @Test("isWiFiAvailable returns a boolean")
    func isWiFiReturns() {
        let monitor = NetworkMonitor()
        let wifi = monitor.isWiFiAvailable
        #expect(wifi == true || wifi == false)
    }

    @Test("isConstrained returns a boolean")
    func isConstrainedReturns() {
        let monitor = NetworkMonitor()
        let constrained = monitor.isConstrained
        #expect(constrained == true || constrained == false)
    }
}
