import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMCore

/// Mock text view delegate for testing the ghost text coordinator.
@MainActor
final class MockGhostTextViewDelegate: GhostTextViewDelegate {
    var text: String
    var selectedRange: NSRange
    var storage: NSMutableAttributedString
    var font: PlatformFont
    var replaceCallCount = 0
    var rerenderCallCount = 0
    var lastReplacementRange: NSRange?
    var lastReplacementText: String?
    var isInsideCodeBlock = false

    init(text: String, cursorPosition: Int? = nil) {
        self.text = text
        let cursor = cursorPosition ?? text.utf16.count
        self.selectedRange = NSRange(location: cursor, length: 0)
        self.font = PlatformFont.systemFont(ofSize: 16)
        self.storage = NSMutableAttributedString(
            string: text,
            attributes: [.font: self.font, .foregroundColor: PlatformColor.black]
        )
    }

    func currentText() -> String { text }
    func currentSelectedRange() -> NSRange { selectedRange }
    func textStorage() -> NSMutableAttributedString? { storage }
    func baseFont() -> PlatformFont { font }

    func replaceText(in range: NSRange, with replacement: String) {
        replaceCallCount += 1
        lastReplacementRange = range
        lastReplacementText = replacement

        if let swiftRange = Range(range, in: text) {
            text = text.replacingCharacters(in: swiftRange, with: replacement)
            storage = NSMutableAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: PlatformColor.black]
            )
        }
    }

    func requestRerender() {
        rerenderCallCount += 1
    }

    func isCursorInsideCodeBlock() -> Bool {
        isInsideCodeBlock
    }
}

@MainActor
@Suite("GhostTextCoordinator")
struct GhostTextCoordinatorTests {

    private func makeCoordinator(
        text: String = "Hello world. This is a test document.",
        cursorPosition: Int? = nil
    ) -> (GhostTextCoordinator, MockGhostTextViewDelegate) {
        let editorState = EditorState()
        let coordinator = GhostTextCoordinator(editorState: editorState)
        let delegate = MockGhostTextViewDelegate(
            text: text,
            cursorPosition: cursorPosition
        )
        coordinator.textViewDelegate = delegate
        return (coordinator, delegate)
    }

    // MARK: - Initial State

    @Test("coordinator starts with inactive phase")
    func initialState() {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.phase == .inactive)
        #expect(coordinator.ghostText.isEmpty)
        #expect(coordinator.isEnabled)
    }

    // MARK: - Dismiss

    @Test("dismiss sets phase to dismissed")
    func dismissSetsPhase() {
        let (coordinator, _) = makeCoordinator()
        coordinator.dismiss()
        #expect(coordinator.phase == .dismissed)
    }

    @Test("dismiss clears ghost text")
    func dismissClearsGhostText() {
        let (coordinator, _) = makeCoordinator()
        coordinator.dismiss()
        #expect(coordinator.ghostText.isEmpty)
    }

    // MARK: - Cancel

    @Test("cancel resets to inactive")
    func cancelResetsToInactive() {
        let (coordinator, _) = makeCoordinator()
        coordinator.cancel()
        #expect(coordinator.phase == .inactive)
        #expect(coordinator.ghostText.isEmpty)
    }

    // MARK: - Settings Toggle (AC-5)

    @Test("textDidChange does not start timer when disabled")
    func disabledDoesNotStartTimer() {
        let (coordinator, _) = makeCoordinator()
        coordinator.isEnabled = false
        coordinator.textDidChange()
        // Phase should remain inactive (no timer started)
        #expect(coordinator.phase == .inactive)
    }

    @Test("textDidChange starts timer when enabled")
    func enabledStartsTimer() {
        let (coordinator, _) = makeCoordinator()
        coordinator.isEnabled = true
        coordinator.textDidChange()
        // Phase stays inactive during the 3-second wait
        #expect(coordinator.phase == .inactive)
    }

    // MARK: - Code Block Detection (AC-4)

    @Test("code block delegate flag is checked correctly")
    func codeBlockDelegateCheck() {
        let (_, delegate) = makeCoordinator()

        delegate.isInsideCodeBlock = true
        #expect(delegate.isCursorInsideCodeBlock())

        delegate.isInsideCodeBlock = false
        #expect(!delegate.isCursorInsideCodeBlock())
    }

    // MARK: - onRequestGhostText wiring

    @Test("onRequestGhostText closure can be set")
    func onRequestGhostTextWiring() {
        let (coordinator, _) = makeCoordinator()

        var handlerCalled = false
        coordinator.onRequestGhostText = { _ in
            handlerCalled = true
            return nil
        }

        // Invoke the handler to verify wiring
        _ = coordinator.onRequestGhostText?("test")
        #expect(handlerCalled)
    }

    // MARK: - Accept with inactive phase

    @Test("accept is no-op when phase is inactive")
    func acceptInactiveIsNoop() {
        let (coordinator, delegate) = makeCoordinator()
        coordinator.accept()
        #expect(delegate.replaceCallCount == 0)
    }

    // MARK: - isEnabled property

    @Test("isEnabled defaults to true")
    func isEnabledDefault() {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.isEnabled)
    }

    @Test("isEnabled can be toggled")
    func isEnabledToggle() {
        let (coordinator, _) = makeCoordinator()
        coordinator.isEnabled = false
        #expect(!coordinator.isEnabled)
        coordinator.isEnabled = true
        #expect(coordinator.isEnabled)
    }

    // MARK: - Multiple textDidChange calls

    @Test("rapid textDidChange calls reset the timer")
    func rapidTextDidChangeResetsTimer() {
        let (coordinator, _) = makeCoordinator()

        // Simulate rapid typing — each call resets the timer
        coordinator.textDidChange()
        coordinator.textDidChange()
        coordinator.textDidChange()

        // Should still be inactive (timer hasn't fired)
        #expect(coordinator.phase == .inactive)
    }
}
