import EMCore
import EMParser

/// Handles Tab and Shift-Tab for navigating between table cells per FEAT-052.
///
/// - **Tab**: Moves cursor to the next cell, re-aligns columns with space padding.
///   At the last cell of the last row, creates a new row.
/// - **Shift-Tab**: Moves cursor to the previous cell, re-aligns columns.
/// - Skips separator rows during navigation.
/// - Does not fire inside fenced code blocks.
public struct TableNavigationRule: FormattingRule, Sendable {

    public init() {}

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        guard context.trigger == .tab || context.trigger == .shiftTab else { return nil }

        let text = context.text
        let cursor = context.cursorPosition

        guard let table = findTable(in: text, at: cursor) else { return nil }
        guard let rowIdx = tableRowIndex(cursor: cursor, lineRanges: table.lineRanges) else {
            return nil
        }

        // Don't navigate within the separator row
        if table.separatorLineIndex == rowIdx { return nil }

        let cursorInLine = text.distance(from: table.lineRanges[rowIdx].lowerBound, to: cursor)
        let cellIdx = tableCellIndex(in: table.lines[rowIdx], cursorOffsetInLine: cursorInLine)

        if context.trigger == .tab {
            return navigateNext(text: text, table: table, rowIdx: rowIdx, cellIdx: cellIdx)
        } else {
            return navigatePrevious(text: text, table: table, rowIdx: rowIdx, cellIdx: cellIdx)
        }
    }

    // MARK: - Navigate Next (Tab)

    private func navigateNext(
        text: String,
        table: TableMatch,
        rowIdx: Int,
        cellIdx: Int
    ) -> TextMutation {
        var rows = normalizeRows(
            table.lines.map { splitTableCells($0) },
            columnCount: table.columnCount
        )
        let colCount = table.columnCount

        var targetRow = rowIdx
        var targetCell = cellIdx + 1

        if targetCell >= colCount {
            // Wrap to first cell of next row, skipping separator
            targetCell = 0
            targetRow += 1
            if targetRow == table.separatorLineIndex {
                targetRow += 1
            }
        }

        // If past the last row, add a new row
        var sepIdx = table.separatorLineIndex
        if targetRow >= rows.count {
            // Auto-insert separator if missing
            if sepIdx == nil && rows.count >= 1 {
                rows.insert(Array(repeating: "", count: colCount), at: 1)
                sepIdx = 1
                targetRow = rows.count // will become rows.count after append
            }
            rows.append(Array(repeating: "", count: colCount))
            targetRow = rows.count - 1
            targetCell = 0
        }

        let aligned = alignTable(rows: rows, separatorIndex: sepIdx, columnCount: colCount)
        let prefixOffset = text.distance(from: text.startIndex, to: table.range.lowerBound)
        let cellOffset = cursorOffsetInAlignedTable(
            alignedText: aligned, row: targetRow, cellIndex: targetCell
        )

        return makeMutation(
            text: text,
            range: table.range,
            replacement: aligned,
            cursorOffsetInResult: prefixOffset + cellOffset,
            hapticStyle: .listContinuation
        )
    }

    // MARK: - Navigate Previous (Shift-Tab)

    private func navigatePrevious(
        text: String,
        table: TableMatch,
        rowIdx: Int,
        cellIdx: Int
    ) -> TextMutation {
        let rows = normalizeRows(
            table.lines.map { splitTableCells($0) },
            columnCount: table.columnCount
        )
        let colCount = table.columnCount

        var targetRow = rowIdx
        var targetCell = cellIdx - 1

        if targetCell < 0 {
            // Wrap to last cell of previous row, skipping separator
            targetCell = colCount - 1
            targetRow -= 1
            if targetRow == table.separatorLineIndex {
                targetRow -= 1
            }
        }

        // Clamp to first data row
        if targetRow < 0 {
            targetRow = 0
            targetCell = 0
            if targetRow == table.separatorLineIndex && rows.count > 1 {
                targetRow = 1
            }
        }

        let aligned = alignTable(
            rows: rows, separatorIndex: table.separatorLineIndex, columnCount: colCount
        )
        let prefixOffset = text.distance(from: text.startIndex, to: table.range.lowerBound)
        let cellOffset = cursorOffsetInAlignedTable(
            alignedText: aligned, row: targetRow, cellIndex: targetCell
        )

        return makeMutation(
            text: text,
            range: table.range,
            replacement: aligned,
            cursorOffsetInResult: prefixOffset + cellOffset,
            hapticStyle: .listContinuation
        )
    }
}
