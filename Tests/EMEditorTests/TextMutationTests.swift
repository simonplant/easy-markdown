import Testing
import Foundation
@testable import EMCore

@Suite("TextMutation")
struct TextMutationTests {

    @Test("TextMutation stores range, replacement, cursor, and haptic")
    func basicProperties() {
        let text = "Hello, world!"
        let range = text.index(text.startIndex, offsetBy: 7)..<text.index(text.startIndex, offsetBy: 12)
        let cursor = text.index(text.startIndex, offsetBy: 12)

        let mutation = TextMutation(
            range: range,
            replacement: "Swift",
            cursorAfter: cursor,
            hapticStyle: .listContinuation
        )

        #expect(mutation.replacement == "Swift")
        #expect(mutation.hapticStyle == .listContinuation)
        #expect(mutation.range == range)
        #expect(mutation.cursorAfter == cursor)
    }

    @Test("TextMutation default haptic is nil")
    func defaultHapticNil() {
        let text = "test"
        let range = text.startIndex..<text.endIndex

        let mutation = TextMutation(
            range: range,
            replacement: "replaced",
            cursorAfter: text.endIndex
        )

        #expect(mutation.hapticStyle == nil)
    }

    @Test("TextMutation can represent an insertion (empty range)")
    func insertion() {
        let text = "Hello world"
        let insertionPoint = text.index(text.startIndex, offsetBy: 5)
        let range = insertionPoint..<insertionPoint

        let mutation = TextMutation(
            range: range,
            replacement: ",",
            cursorAfter: text.index(after: insertionPoint)
        )

        #expect(mutation.range.isEmpty)
        #expect(mutation.replacement == ",")
    }

    @Test("TextMutation can represent a deletion (empty replacement)")
    func deletion() {
        let text = "Hello, world!"
        let start = text.index(text.startIndex, offsetBy: 5)
        let end = text.index(text.startIndex, offsetBy: 7)

        let mutation = TextMutation(
            range: start..<end,
            replacement: "",
            cursorAfter: start
        )

        #expect(mutation.replacement.isEmpty)
    }

    @Test("TextMutation is Sendable")
    func sendable() async {
        let text = "test"
        let mutation = TextMutation(
            range: text.startIndex..<text.endIndex,
            replacement: "done",
            cursorAfter: text.endIndex
        )

        // Verify Sendable by passing across isolation boundary
        let result = await Task.detached {
            mutation.replacement
        }.value

        #expect(result == "done")
    }
}
