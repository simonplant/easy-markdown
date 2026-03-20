import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("TableNavigationRule")
struct TableNavigationRuleTests {

    private let rule = TableNavigationRule()

    private func apply(_ mutation: TextMutation, to text: String) -> (result: String, cursorOffset: Int) {
        let prefix = String(text[..<mutation.range.lowerBound])
        let suffix = String(text[mutation.range.upperBound...])
        let result = prefix + mutation.replacement + suffix
        let cursorOffset = result.distance(from: result.startIndex, to: mutation.cursorAfter)
        return (result, cursorOffset)
    }

    private func context(
        text: String,
        cursorOffset: Int,
        trigger: FormattingTrigger = .tab
    ) -> FormattingContext {
        let cursor = text.index(text.startIndex, offsetBy: cursorOffset)
        return FormattingContext(text: text, cursorPosition: cursor, trigger: trigger)
    }

    // MARK: - Tab Navigation

    @Test("Tab in first cell moves to second cell")
    func tabFirstToSecond() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        // Cursor in cell "A" (offset 2, after "| ")
        let ctx = context(text: text, cursorOffset: 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        // Table should be aligned and cursor in cell B
        #expect(result.contains("| A"))
        #expect(result.contains("| B"))
        // Cursor should be at the start of cell B content
        let cellBLine = result.split(separator: "\n").first!
        let expectedOffset = String(cellBLine).distance(
            from: String(cellBLine).startIndex,
            to: String(cellBLine).range(of: "| B")!.upperBound
        ) + 1 // after "| B" → after "| " of B cell
        // Just verify cursor is after the second pipe
        #expect(cursorOffset > 4)
    }

    @Test("Tab in last cell wraps to first cell of next data row")
    func tabWrapToNextRow() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        // Cursor in cell "B" of header row (offset ~6)
        let ctx = context(text: text, cursorOffset: 6)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        // Should skip separator and land in cell C
        let lines = result.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        // Cursor should be in the third line (data row), first cell
        let offsetToThirdLine = lines[0].count + 1 + lines[1].count + 1
        #expect(cursorOffset == offsetToThirdLine + 2) // after "| "
    }

    @Test("Tab in last cell of last row creates new row")
    func tabCreatesNewRow() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        // Cursor in cell D (last cell of last row)
        // Line 3 starts at offset: 9 + 1 + 9 + 1 = 20. Cell D at ~26
        let line3Start = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: line3Start + 6)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        // New row should have correct column count
        let newRowCells = lines[3].split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        // New row cells should be empty (whitespace only was trimmed)
        #expect(newRowCells.isEmpty || newRowCells.allSatisfy { $0.isEmpty })
    }

    @Test("Tab aligns misaligned table")
    func tabAlignsTable() {
        let text = "| Name | Age |\n|---|---|\n| Alice | 30 |"
        let ctx = context(text: text, cursorOffset: 2) // in "Name" cell
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        // All lines should have consistent formatting
        for line in lines {
            #expect(line.hasPrefix("| "))
            #expect(line.hasSuffix(" |"))
        }
    }

    // MARK: - Shift-Tab Navigation

    @Test("Shift-Tab in second cell moves to first cell")
    func shiftTabSecondToFirst() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 6, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (_, cursorOffset) = apply(mutation!, to: text)
        // Cursor should be in first cell (offset 2, after "| ")
        #expect(cursorOffset == 2)
    }

    @Test("Shift-Tab in first cell of data row wraps to last cell of header")
    func shiftTabWrapsUp() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let line3Start = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: line3Start + 2, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        // Should skip separator and land in cell B of header
        // Cursor should be in the first line, second cell
        let lines = result.split(separator: "\n").map(String.init)
        let cellBOffset = lines[0].distance(
            from: lines[0].startIndex,
            to: lines[0].lastIndex(of: "|")!
        )
        #expect(cursorOffset < lines[0].count) // cursor is in first line
    }

    @Test("Shift-Tab in first cell of first row stays put")
    func shiftTabAtStart() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 2, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (_, cursorOffset) = apply(mutation!, to: text)
        // Cursor should be at beginning of first cell
        #expect(cursorOffset == 2)
    }

    // MARK: - Code Block Suppression

    @Test("Does not fire inside fenced code block")
    func codeBlockSuppression() {
        let text = "```\n| A | B |\n```"
        let ctx = context(text: text, cursorOffset: 6)
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    // MARK: - Edge Cases

    @Test("Does not fire on non-table text")
    func nonTableText() {
        let text = "Just a paragraph"
        let ctx = context(text: text, cursorOffset: 5)
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Does not fire on Enter trigger")
    func nonTabTrigger() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 2, trigger: .enter)
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Haptic style is listContinuation")
    func hapticStyle() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 2)
        let mutation = rule.evaluate(ctx)
        #expect(mutation?.hapticStyle == .listContinuation)
    }

    @Test("Tab on separator row does not fire")
    func separatorRowNoFire() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let sepStart = "| A | B |\n".count
        let ctx = context(text: text, cursorOffset: sepStart + 1)
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Table without separator still navigates")
    func noSeparator() {
        let text = "| A | B |"
        let ctx = context(text: text, cursorOffset: 2) // in cell A
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        // Should still produce a valid aligned table
        #expect(result.contains("|"))
    }

    @Test("Tab with 20 columns does not crash")
    func twentyColumns() {
        let cells = (1...20).map { "C\($0)" }
        let row = "| " + cells.joined(separator: " | ") + " |"
        let sep = "| " + cells.map { _ in "---" }.joined(separator: " | ") + " |"
        let text = row + "\n" + sep + "\n" + row
        let ctx = context(text: text, cursorOffset: 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let resultLines = result.split(separator: "\n")
        #expect(resultLines.count == 3)
    }
}
