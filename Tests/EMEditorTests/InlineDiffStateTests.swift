import Testing
import Foundation
@testable import EMEditor
@testable import EMCore

@MainActor
@Suite("InlineDiffState")
struct InlineDiffStateTests {

    // MARK: - Initial State

    @Test("starts inactive")
    func initialState() {
        let state = InlineDiffState()
        #expect(state.phase == .inactive)
        #expect(!state.isActive)
        #expect(state.originalText.isEmpty)
        #expect(state.improvedText.isEmpty)
    }

    // MARK: - Begin

    @Test("begin sets streaming phase and stores original")
    func beginSession() {
        let state = InlineDiffState()
        let range = NSRange(location: 10, length: 20)

        state.begin(originalText: "Hello world", range: range)

        #expect(state.phase == .streaming)
        #expect(state.isActive)
        #expect(state.originalText == "Hello world")
        #expect(state.originalRange == range)
        #expect(state.improvedText.isEmpty)
    }

    // MARK: - Token Streaming

    @Test("appendToken accumulates improved text")
    func appendTokens() {
        let state = InlineDiffState()
        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))

        state.appendToken("Hello")
        #expect(state.improvedText == "Hello")

        state.appendToken(" there")
        #expect(state.improvedText == "Hello there")
    }

    @Test("appendToken ignores tokens when not streaming")
    func appendTokenWhenInactive() {
        let state = InlineDiffState()
        state.appendToken("ignored")
        #expect(state.improvedText.isEmpty)
    }

    @Test("appendToken ignores tokens after ready")
    func appendTokenAfterReady() {
        let state = InlineDiffState()
        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))
        state.appendToken("Hello")
        state.markReady()

        state.appendToken(" extra")
        #expect(state.improvedText == "Hello")
    }

    // MARK: - Phase Transitions

    @Test("markReady transitions from streaming to ready")
    func markReady() {
        let state = InlineDiffState()
        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))
        state.appendToken("Hello")
        state.markReady()

        #expect(state.phase == .ready)
        #expect(state.isActive)
    }

    @Test("markReady is no-op when not streaming")
    func markReadyWhenInactive() {
        let state = InlineDiffState()
        state.markReady()
        #expect(state.phase == .inactive)
    }

    @Test("markAccepted transitions to accepted")
    func markAccepted() {
        let state = InlineDiffState()
        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))
        state.markReady()
        state.markAccepted()

        #expect(state.phase == .accepted)
        #expect(!state.isActive)
    }

    @Test("markDismissed transitions to dismissed")
    func markDismissed() {
        let state = InlineDiffState()
        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))
        state.markReady()
        state.markDismissed()

        #expect(state.phase == .dismissed)
        #expect(!state.isActive)
    }

    // MARK: - Reset

    @Test("reset clears all state")
    func reset() {
        let state = InlineDiffState()
        state.begin(originalText: "Hi", range: NSRange(location: 5, length: 2))
        state.appendToken("Hello")
        state.reset()

        #expect(state.phase == .inactive)
        #expect(state.originalText.isEmpty)
        #expect(state.improvedText.isEmpty)
        #expect(state.originalRange == NSRange(location: 0, length: 0))
    }

    // MARK: - isActive

    @Test("isActive is true only during streaming and ready")
    func isActivePhases() {
        let state = InlineDiffState()

        #expect(!state.isActive) // inactive

        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))
        #expect(state.isActive) // streaming

        state.markReady()
        #expect(state.isActive) // ready

        state.markAccepted()
        #expect(!state.isActive) // accepted

        state.reset()
        state.begin(originalText: "Hi", range: NSRange(location: 0, length: 2))
        state.markReady()
        state.markDismissed()
        #expect(!state.isActive) // dismissed
    }
}
