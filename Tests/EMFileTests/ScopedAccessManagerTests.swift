import Testing
import Foundation
@testable import EMFile

@Suite("ScopedAccessManager")
struct ScopedAccessManagerTests {

    @Test("Starts with zero active count")
    func initialState() {
        let manager = ScopedAccessManager()
        #expect(manager.activeCount == 0)
    }

    @Test("Stop all clears active state")
    func stopAll() {
        let manager = ScopedAccessManager()
        // stopAll on empty state should not crash
        manager.stopAll()
        #expect(manager.activeCount == 0)
    }

    @Test("Stop accessing unknown URL is a no-op")
    func stopUnknown() {
        let manager = ScopedAccessManager()
        let url = URL(fileURLWithPath: "/tmp/unknown.md")
        // Should not crash
        manager.stopAccessing(url)
        #expect(manager.activeCount == 0)
    }
}
