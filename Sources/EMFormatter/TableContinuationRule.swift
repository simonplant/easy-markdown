import EMCore
import EMParser

/// Handles Enter key in tables per FEAT-052.
///
/// - In the last row: creates a new row with the correct column count.
/// - Auto-inserts a missing header separator row when adding a new row.
/// - Re-aligns the table after modification.
/// - Does not fire inside fenced code blocks.
public struct TableContinuationRule: FormattingRule, Sendable {

    public init() {}

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        guard context.trigger == .enter else { return nil }

        let text = context.text
        let cursor = context.cursorPosition

        guard let table = findTable(in: text, at: cursor) else { return nil }
        guard let rowIdx = tableRowIndex(cursor: cursor, lineRanges: table.lineRanges) else {
            return nil
        }

        // Don't handle Enter on the separator row
        if table.separatorLineIndex == rowIdx { return nil }

        // Only handle Enter in the last row
        guard rowIdx == table.lines.count - 1 else { return nil }

        return addNewRow(text: text, table: table)
    }

    // MARK: - Add New Row

    private func addNewRow(text: String, table: TableMatch) -> TextMutation {
        var rows = normalizeRows(
            table.lines.map { splitTableCells($0) },
            columnCount: table.columnCount
        )
        let colCount = table.columnCount

        // Auto-insert separator if missing
        var sepIdx = table.separatorLineIndex
        if sepIdx == nil && rows.count >= 1 {
            rows.insert(Array(repeating: "", count: colCount), at: 1)
            sepIdx = 1
        }

        // Add empty data row
        rows.append(Array(repeating: "", count: colCount))
        let newRowIndex = rows.count - 1

        let aligned = alignTable(rows: rows, separatorIndex: sepIdx, columnCount: colCount)
        let prefixOffset = text.distance(from: text.startIndex, to: table.range.lowerBound)
        let cellOffset = cursorOffsetInAlignedTable(
            alignedText: aligned, row: newRowIndex, cellIndex: 0
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
