import Testing
import Foundation
@testable import EMEditor

@MainActor
@Suite("FormattingActions")
struct FormattingActionsTests {

    @Test("Initial state has nil actions and false focusAISection")
    func initialState() {
        let formatting = FormattingActions()
        #expect(formatting.performBold == nil)
        #expect(formatting.performItalic == nil)
        #expect(formatting.performLink == nil)
        #expect(formatting.focusAISection == false)
    }

    @Test("Formatting actions dispatch correctly")
    func actionsDispatch() {
        let formatting = FormattingActions()
        var boldCalled = false
        var italicCalled = false
        var linkCalled = false

        formatting.performBold = { boldCalled = true }
        formatting.performItalic = { italicCalled = true }
        formatting.performLink = { linkCalled = true }

        formatting.performBold?()
        #expect(boldCalled)

        formatting.performItalic?()
        #expect(italicCalled)

        formatting.performLink?()
        #expect(linkCalled)
    }

    @Test("focusAISection can be toggled")
    func focusAISectionToggle() {
        let formatting = FormattingActions()
        formatting.focusAISection = true
        #expect(formatting.focusAISection)
        formatting.focusAISection = false
        #expect(!formatting.focusAISection)
    }
}
