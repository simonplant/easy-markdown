import Testing
import Foundation
@testable import EMEditor

@MainActor
@Suite("EditorState")
struct EditorStateTests {

    @Test("Initial state has sensible defaults")
    func initialState() {
        let state = EditorState()
        #expect(state.selectedRange == NSRange(location: 0, length: 0))
        #expect(state.isSourceView == false)
        #expect(state.scrollOffset == 0)
        #expect(state.selectionWordCount == nil)
        #expect(state.documentStats == .zero)
    }

    @Test("Undo manager has unlimited depth")
    func undoManagerUnlimitedDepth() {
        let state = EditorState()
        // levelsOfUndo == 0 means unlimited per Apple docs
        #expect(state.undoManager.levelsOfUndo == 0)
    }

    @Test("Update selected range")
    func updateSelectedRange() {
        let state = EditorState()
        let range = NSRange(location: 5, length: 10)
        state.updateSelectedRange(range)
        #expect(state.selectedRange == range)
    }

    @Test("Update scroll offset")
    func updateScrollOffset() {
        let state = EditorState()
        state.updateScrollOffset(42.5)
        #expect(state.scrollOffset == 42.5)
    }

    @Test("Update selection word count")
    func updateSelectionWordCount() {
        let state = EditorState()
        #expect(state.selectionWordCount == nil)

        state.updateSelectionWordCount(7)
        #expect(state.selectionWordCount == 7)

        state.updateSelectionWordCount(nil)
        #expect(state.selectionWordCount == nil)
    }

    @Test("Update document stats")
    func updateDocumentStats() {
        let state = EditorState()
        let stats = DocumentStats(
            wordCount: 42,
            characterCount: 200,
            characterCountNoSpaces: 170,
            readingTimeSeconds: 11,
            paragraphCount: 3,
            sentenceCount: 5,
            fleschKincaidGradeLevel: 8.2
        )
        state.updateDocumentStats(stats)
        #expect(state.documentStats == stats)
    }

    @Test("Toggle source view")
    func toggleSourceView() {
        let state = EditorState()
        #expect(state.isSourceView == false)
        state.isSourceView = true
        #expect(state.isSourceView == true)
        state.isSourceView = false
        #expect(state.isSourceView == false)
    }

    @Test("Undo manager registers and undoes operations")
    func undoManagerOperations() {
        let state = EditorState()
        var value = 0

        state.undoManager.registerUndo(withTarget: state) { _ in
            value = 0
        }
        value = 1
        #expect(value == 1)
        #expect(state.undoManager.canUndo == true)

        state.undoManager.undo()
        #expect(value == 0)
    }
}
