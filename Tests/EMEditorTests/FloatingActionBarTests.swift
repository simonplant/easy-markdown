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
        actions.onSummarize()
        actions.onTranslate()
        actions.onTone()
        actions.onProUpgrade()
        actions.onAccept()
        actions.onDismiss()
        actions.onBold()
        actions.onItalic()
        actions.onLink()
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

    @Test("new AI actions are dispatched")
    func newAIActions() {
        var summarizeCalled = false
        var translateCalled = false
        var toneCalled = false
        var proUpgradeCalled = false

        let actions = FloatingActionBarActions(
            onSummarize: { summarizeCalled = true },
            onTranslate: { translateCalled = true },
            onTone: { toneCalled = true },
            onProUpgrade: { proUpgradeCalled = true }
        )

        actions.onSummarize()
        #expect(summarizeCalled)

        actions.onTranslate()
        #expect(translateCalled)

        actions.onTone()
        #expect(toneCalled)

        actions.onProUpgrade()
        #expect(proUpgradeCalled)
    }

    @Test("formatting actions are dispatched")
    func formattingActions() {
        var boldCalled = false
        var italicCalled = false
        var linkCalled = false

        let actions = FloatingActionBarActions(
            onBold: { boldCalled = true },
            onItalic: { italicCalled = true },
            onLink: { linkCalled = true }
        )

        actions.onBold()
        #expect(boldCalled)

        actions.onItalic()
        #expect(italicCalled)

        actions.onLink()
        #expect(linkCalled)
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

    @Test("bar stores Pro subscriber status")
    func proSubscriberStatus() {
        let proBar = FloatingActionBar(
            diffPhase: .inactive,
            actions: FloatingActionBarActions(),
            showAIActions: true,
            isProSubscriber: true
        )
        #expect(proBar.isProSubscriber)

        let freeBar = FloatingActionBar(
            diffPhase: .inactive,
            actions: FloatingActionBarActions(),
            showAIActions: true,
            isProSubscriber: false
        )
        #expect(!freeBar.isProSubscriber)
    }

    @Test("bar stores compact mode")
    func compactMode() {
        let compactBar = FloatingActionBar(
            diffPhase: .inactive,
            actions: FloatingActionBarActions(),
            showAIActions: true,
            isCompact: true
        )
        #expect(compactBar.isCompact)
    }

    // MARK: - EditorState Selection Rect per FEAT-054

    @Test("selection rect updates and clears")
    func selectionRect() {
        let state = EditorState()

        #expect(state.selection.selectionRect == nil)

        let rect = CGRect(x: 10, y: 20, width: 200, height: 16)
        state.selection.updateSelectionRect(rect)
        #expect(state.selection.selectionRect == rect)

        state.selection.updateSelectionRect(nil)
        #expect(state.selection.selectionRect == nil)
    }

    // MARK: - EditorState Formatting Actions per FEAT-054

    @Test("formatting actions dispatch through EditorState")
    func formattingActionsViaEditorState() {
        let state = EditorState()
        var boldCalled = false
        var italicCalled = false
        var linkCalled = false

        state.formatting.performBold = { boldCalled = true }
        state.formatting.performItalic = { italicCalled = true }
        state.formatting.performLink = { linkCalled = true }

        state.formatting.performBold?()
        #expect(boldCalled)

        state.formatting.performItalic?()
        #expect(italicCalled)

        state.formatting.performLink?()
        #expect(linkCalled)
    }

    @Test("focusAISection defaults to false")
    func focusAISectionDefault() {
        let state = EditorState()
        #expect(!state.formatting.focusAISection)
    }

    @Test("focusAISection can be toggled")
    func focusAISectionToggle() {
        let state = EditorState()
        state.formatting.focusAISection = true
        #expect(state.formatting.focusAISection)
        state.formatting.focusAISection = false
        #expect(!state.formatting.focusAISection)
    }
}
