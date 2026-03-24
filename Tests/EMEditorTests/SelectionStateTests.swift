import Testing
import Foundation
@testable import EMEditor

@MainActor
@Suite("SelectionState")
struct SelectionStateTests {

    @Test("Initial state has sensible defaults")
    func initialState() {
        let selection = SelectionState()
        #expect(selection.selectedRange == NSRange(location: 0, length: 0))
        #expect(selection.selectionWordCount == nil)
        #expect(selection.selectionRect == nil)
    }

    @Test("Update selected range")
    func updateSelectedRange() {
        let selection = SelectionState()
        let range = NSRange(location: 5, length: 10)
        selection.updateSelectedRange(range)
        #expect(selection.selectedRange == range)
    }

    @Test("Update selection word count")
    func updateSelectionWordCount() {
        let selection = SelectionState()
        selection.updateSelectionWordCount(42)
        #expect(selection.selectionWordCount == 42)

        selection.updateSelectionWordCount(nil)
        #expect(selection.selectionWordCount == nil)
    }

    @Test("Update selection rect")
    func updateSelectionRect() {
        let selection = SelectionState()
        let rect = CGRect(x: 10, y: 20, width: 200, height: 16)
        selection.updateSelectionRect(rect)
        #expect(selection.selectionRect == rect)

        selection.updateSelectionRect(nil)
        #expect(selection.selectionRect == nil)
    }
}
