import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("TableContinuationRule")
struct TableContinuationRuleTests {

    private let rule = TableContinuationRule()

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
        trigger: FormattingTrigger = .enter
    ) -> FormattingContext {
        let cursor = text.index(text.startIndex, offsetBy: cursorOffset)
        return FormattingContext(text: text, cursorPosition: cursor, trigger: trigger)
    }

    // MARK: - New Row Creation

    @Test("Enter in last row creates new row")
    func enterCreatesNewRow() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 6)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        // New row should be the last line
        #expect(lines[3].hasPrefix("| "))
        #expect(lines[3].hasSuffix(" |"))
    }

    @Test("New row has correct column count")
    func newRowColumnCount() {
        let text = "| A | B | C |\n|---|---|---|\n| D | E | F |"
        let lastRowStart = "| A | B | C |\n|---|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        // Count pipes in new row (should be 4 for 3 columns: | | | |)
        let pipeCount = lines[3].filter { $0 == "|" }.count
        #expect(pipeCount == 4) // 3 columns → 4 pipes
    }

    @Test("Cursor placed in first cell of new row")
    func cursorInNewRow() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        // Cursor should be at start of new row's first cell (after "| ")
        let newRowStart = lines[0].count + 1 + lines[1].count + 1 + lines[2].count + 1
        #expect(cursorOffset == newRowStart + 2)
    }

    // MARK: - Auto-Insert Separator

    @Test("Enter after single header row inserts separator and new row")
    func autoInsertSeparator() {
        let text = "| Name | Age |"
        let ctx = context(text: text, cursorOffset: text.count - 1)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        #expect(lines.count == 3) // header + separator + new row
        // Second line should be separator
        #expect(lines[1].contains("---"))
        // Verify it's a valid separator
        #expect(lines[1].contains("-"))
    }

    @Test("Separator aligns with header columns")
    func separatorAlignedWithHeader() {
        let text = "| Name | Age |"
        let ctx = context(text: text, cursorOffset: text.count - 1)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        // All lines should have the same number of pipes
        let pipeCounts = lines.map { line in line.filter { $0 == "|" }.count }
        #expect(Set(pipeCounts).count == 1) // all same
    }

    @Test("Enter on multi-row table without separator adds separator")
    func multiRowNoSeparator() {
        let text = "| A | B |\n| C | D |"
        let lastRowStart = "| A | B |\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        // Should have: header, separator, original second row, new row
        #expect(lines.count >= 3)
        // At least one line should be a separator
        let hasSep = lines.contains { line in
            let cells = line.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            return !cells.isEmpty && cells.allSatisfy { cell in
                cell.allSatisfy { $0 == "-" || $0 == ":" }
            }
        }
        #expect(hasSep)
    }

    // MARK: - Non-Firing Cases

    @Test("Enter in middle row does not fire")
    func enterMiddleRow() {
        let text = "| A | B |\n|---|---|\n| C | D |\n| E | F |"
        let middleRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: middleRowStart + 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil) // Not the last row
    }

    @Test("Enter on header row (not last) does not fire")
    func enterHeaderNotLast() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil) // Header is not the last row
    }

    @Test("Enter on separator row does not fire")
    func enterSeparatorRow() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let sepStart = "| A | B |\n".count
        let ctx = context(text: text, cursorOffset: sepStart + 1)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire outside table")
    func notInTable() {
        let text = "Just a paragraph"
        let ctx = context(text: text, cursorOffset: 5)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire on Tab trigger")
    func tabTrigger() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire inside code block")
    func codeBlockSuppression() {
        let text = "```\n| A | B |\n```"
        let ctx = context(text: text, cursorOffset: 6)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Alignment

    @Test("Table is re-aligned after adding row")
    func alignmentAfterNewRow() {
        let text = "| Name | Age |\n|---|---|\n| Alice | 30 |"
        let lastRowStart = "| Name | Age |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let lines = result.split(separator: "\n").map(String.init)
        // All non-separator data lines should have matching widths
        let dataPipePositions = lines.filter { !$0.contains("---") }.map { line in
            line.enumerated().filter { $0.element == "|" }.map(\.offset)
        }
        // All data rows should have pipes at the same positions
        if dataPipePositions.count > 1 {
            for i in 1..<dataPipePositions.count {
                #expect(dataPipePositions[i] == dataPipePositions[0])
            }
        }
    }

    @Test("Haptic style is listContinuation")
    func hapticStyle() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2)
        let mutation = rule.evaluate(ctx)

        #expect(mutation?.hapticStyle == .listContinuation)
    }

    @Test("Each auto-format produces a single mutation for undo")
    func singleMutation() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(text: text, cursorOffset: lastRowStart + 2)
        let mutation = rule.evaluate(ctx)

        // Mutation is a single TextMutation — applied as one undo group
        #expect(mutation != nil)
        #expect(mutation!.range.lowerBound < mutation!.range.upperBound ||
                !mutation!.replacement.isEmpty)
    }
}
