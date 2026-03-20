import Testing
import Foundation
@testable import EMEditor
@testable import EMCore

@MainActor
@Suite("FloatingActionBar")
struct FloatingActionBarTests {

    // MARK: - FloatingActionBarActions

    @Test("default actions are no-ops")
    func defaultActions() {
        let actions = FloatingActionBarActions()
        // Should not crash
        actions.onImprove()
        actions.onAccept()
        actions.onDismiss()
    }

    @Test("custom actions are called")
    func customActions() {
        var improveCalled = false
        var acceptCalled = false
        var dismissCalled = false

        let actions = FloatingActionBarActions(
            onImprove: { improveCalled = true },
            onAccept: { acceptCalled = true },
            onDismiss: { dismissCalled = true }
        )

        actions.onImprove()
        #expect(improveCalled)

        actions.onAccept()
        #expect(acceptCalled)

        actions.onDismiss()
        #expect(dismissCalled)
    }

    // MARK: - View Construction

    @Test("bar can be created with inactive diff phase")
    func createWithInactivePhase() {
        let bar = FloatingActionBar(
            diffPhase: .inactive,
            actions: FloatingActionBarActions(),
            showAIActions: true
        )
        // View should construct without issues
        #expect(bar.diffPhase == .inactive)
        #expect(bar.showAIActions)
    }

    @Test("bar can be created with streaming diff phase")
    func createWithStreamingPhase() {
        let bar = FloatingActionBar(
            diffPhase: .streaming,
            actions: FloatingActionBarActions(),
            showAIActions: true
        )
        #expect(bar.diffPhase == .streaming)
    }

    @Test("bar can be created with ready diff phase")
    func createWithReadyPhase() {
        let bar = FloatingActionBar(
            diffPhase: .ready,
            actions: FloatingActionBarActions(),
            showAIActions: true
        )
        #expect(bar.diffPhase == .ready)
    }

    @Test("bar respects showAIActions false for unsupported devices")
    func noAIOnUnsupportedDevices() {
        let bar = FloatingActionBar(
            diffPhase: .inactive,
            actions: FloatingActionBarActions(),
            showAIActions: false
        )
        #expect(!bar.showAIActions)
    }
}
