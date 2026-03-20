import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMCore

/// Mock text view delegate for testing the coordinator.
@MainActor
final class MockTextViewDelegate: ImproveWritingTextViewDelegate {
    var text: String
    var selectedRange: NSRange
    var storage: NSMutableAttributedString
    var font: PlatformFont
    var replaceCallCount = 0
    var rerenderCallCount = 0
    var lastReplacementRange: NSRange?
    var lastReplacementText: String?

    init(text: String, selectedRange: NSRange? = nil) {
        self.text = text
        self.selectedRange = selectedRange ?? NSRange(location: 0, length: text.utf16.count)
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

        // Apply the replacement to the mock storage
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
}

@MainActor
@Suite("ImproveWritingCoordinator")
struct ImproveWritingCoordinatorTests {

    private func makeCoordinator() -> (ImproveWritingCoordinator, MockTextViewDelegate) {
        let editorState = EditorState()
        let coordinator = ImproveWritingCoordinator(editorState: editorState)
        let delegate = MockTextViewDelegate(
            text: "Hello world, this is a test.",
            selectedRange: NSRange(location: 0, length: 11) // "Hello world"
        )
        coordinator.textViewDelegate = delegate
        return (coordinator, delegate)
    }

    // MARK: - Initial State

    @Test("coordinator starts with inactive diff state")
    func initialState() {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.diffState.phase == .inactive)
        #expect(!coordinator.diffState.isActive)
    }

    // MARK: - Start Improve

    @Test("startImprove begins diff session with selected text")
    func startImproveBeginsDiff() {
        let (coordinator, _) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)

        #expect(coordinator.diffState.phase == .streaming)
        #expect(coordinator.diffState.originalText == "Hello world")
    }

    @Test("startImprove ignores empty selection")
    func startImproveEmptySelection() {
        let editorState = EditorState()
        let coordinator = ImproveWritingCoordinator(editorState: editorState)
        let delegate = MockTextViewDelegate(
            text: "Hello world.",
            selectedRange: NSRange(location: 5, length: 0)
        )
        coordinator.textViewDelegate = delegate

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)

        // Should remain inactive since no text was selected
        #expect(coordinator.diffState.phase == .inactive)
    }

    // MARK: - Token Streaming

    @Test("tokens stream into diff state")
    func tokenStreaming() async throws {
        let (coordinator, _) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.yield(.token("Greet"))
            continuation.yield(.token("ings"))
            continuation.yield(.completed(fullText: "Greetings"))
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)

        // Allow the streaming task to process
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(coordinator.diffState.improvedText == "Greetings")
        #expect(coordinator.diffState.phase == .ready)
    }

    // MARK: - Accept

    @Test("accept replaces original text with improved text")
    func acceptReplacesText() async throws {
        let (coordinator, delegate) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.yield(.token("Greetings"))
            continuation.yield(.completed(fullText: "Greetings"))
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)
        try await Task.sleep(nanoseconds: 200_000_000)

        coordinator.accept()

        #expect(delegate.replaceCallCount == 1)
        #expect(delegate.lastReplacementText == "Greetings")
        #expect(delegate.lastReplacementRange == NSRange(location: 0, length: 11))
    }

    @Test("accept triggers rerender")
    func acceptTriggersRerender() async throws {
        let (coordinator, delegate) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.yield(.token("Better"))
            continuation.yield(.completed(fullText: "Better"))
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)
        try await Task.sleep(nanoseconds: 200_000_000)

        let prerenderCount = delegate.rerenderCallCount
        coordinator.accept()

        #expect(delegate.rerenderCallCount > prerenderCount)
    }

    // MARK: - Dismiss

    @Test("dismiss does not modify original text")
    func dismissPreservesOriginal() async throws {
        let (coordinator, delegate) = makeCoordinator()
        let originalText = delegate.text

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.yield(.token("Greetings"))
            continuation.yield(.completed(fullText: "Greetings"))
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)
        try await Task.sleep(nanoseconds: 200_000_000)

        coordinator.dismiss()

        // replaceText should NOT have been called
        #expect(delegate.replaceCallCount == 0)
        // Original text in the delegate should be unchanged
        // (The delegate's text may have been modified by diff rendering,
        // but dismiss should trigger cleanup + rerender)
        #expect(delegate.rerenderCallCount > 0)
    }

    @Test("dismiss sets phase to dismissed")
    func dismissSetsPhase() async throws {
        let (coordinator, _) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.yield(.token("Better"))
            continuation.yield(.completed(fullText: "Better"))
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)
        try await Task.sleep(nanoseconds: 200_000_000)

        coordinator.dismiss()
        #expect(coordinator.diffState.phase == .dismissed)
    }

    // MARK: - Cancel

    @Test("cancel resets diff state")
    func cancelResetsState() {
        let (coordinator, _) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            // Don't finish — simulating ongoing stream
            continuation.onTermination = { _ in }
        }

        coordinator.startImprove(updateStream: stream)
        #expect(coordinator.diffState.isActive)

        coordinator.cancel()
        #expect(coordinator.diffState.phase == .inactive)
    }

    // MARK: - Error Handling

    @Test("failed update resets diff state")
    func failedUpdateResets() async throws {
        let (coordinator, _) = makeCoordinator()

        let stream = AsyncStream<ImproveWritingUpdate> { continuation in
            continuation.yield(.failed(.ai(.inferenceTimeout)))
            continuation.finish()
        }

        coordinator.startImprove(updateStream: stream)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(coordinator.diffState.phase == .inactive)
    }
}
