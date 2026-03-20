import EMCore

// MARK: - Table Row Detection

/// Checks if a line looks like a markdown table row.
/// Requires at least two pipe characters and must start with `|` (after optional whitespace).
func isTableRow(_ line: String) -> Bool {
    var idx = line.startIndex
    // Skip leading whitespace
    while idx < line.endIndex && (line[idx] == " " || line[idx] == "\t") {
        idx = line.index(after: idx)
    }
    guard idx < line.endIndex && line[idx] == "|" else { return false }
    // Need at least one more pipe
    idx = line.index(after: idx)
    while idx < line.endIndex {
        if line[idx] == "|" { return true }
        idx = line.index(after: idx)
    }
    return false
}

/// Checks if a line is a table separator row (e.g., `|---|---|`).
func isSeparatorRow(_ line: String) -> Bool {
    let cells = splitTableCells(line)
    guard !cells.isEmpty else { return false }
    return cells.allSatisfy { isSeparatorCell($0) }
}

/// Checks if a single cell value matches the separator pattern: dashes with optional colons.
private func isSeparatorCell(_ cell: String) -> Bool {
    guard !cell.isEmpty else { return false }
    var s = cell[...]
    if s.first == ":" { s = s.dropFirst() }
    if s.last == ":" { s = s.dropLast() }
    return !s.isEmpty && s.allSatisfy { $0 == "-" }
}

// MARK: - Cell Parsing

/// Splits a table row line into individual cell contents, with whitespace trimmed.
/// Handles leading and trailing pipes: `| A | B |` → `["A", "B"]`.
func splitTableCells(_ line: String) -> [String] {
    var trimmed = line[...]
    // Trim leading whitespace
    while let first = trimmed.first, first == " " || first == "\t" {
        trimmed = trimmed.dropFirst()
    }
    // Trim trailing whitespace
    while let last = trimmed.last, last == " " || last == "\t" {
        trimmed = trimmed.dropLast()
    }
    // Remove leading pipe
    if trimmed.first == "|" { trimmed = trimmed.dropFirst() }
    // Remove trailing pipe
    if trimmed.last == "|" { trimmed = trimmed.dropLast() }

    guard !trimmed.isEmpty else { return [] }

    return String(trimmed)
        .split(separator: "|" as Character, omittingEmptySubsequences: false)
        .map { part in
            var cell = part[...]
            while let f = cell.first, f == " " || f == "\t" { cell = cell.dropFirst() }
            while let l = cell.last, l == " " || l == "\t" { cell = cell.dropLast() }
            return String(cell)
        }
}

// MARK: - Table Detection

/// Information about a markdown table found in the document.
struct TableMatch {
    /// The range in the document text covering the entire table.
    let range: Range<String.Index>
    /// The lines of the table as strings.
    let lines: [String]
    /// The line ranges in the document text.
    let lineRanges: [Range<String.Index>]
    /// Index of the separator row within `lines`, if present.
    let separatorLineIndex: Int?
    /// The number of columns (max across non-separator rows).
    let columnCount: Int
}

/// Finds the table containing the cursor position.
/// Returns nil if the cursor is not on a table row or is inside a code block.
func findTable(in text: String, at cursor: String.Index) -> TableMatch? {
    guard !isInsideCodeBlock(text: text, at: cursor) else { return nil }

    let cursorLineRng = lineRange(in: text, at: cursor)
    let cursorLine = String(text[cursorLineRng])
    guard isTableRow(cursorLine) else { return nil }

    var items: [(line: String, range: Range<String.Index>)] = [(cursorLine, cursorLineRng)]

    // Expand upward
    var start = cursorLineRng.lowerBound
    while start > text.startIndex {
        let prev = text.index(before: start)
        let prevRange = lineRange(in: text, at: prev)
        let prevLine = String(text[prevRange])
        guard isTableRow(prevLine) else { break }
        items.insert((prevLine, prevRange), at: 0)
        start = prevRange.lowerBound
    }

    // Expand downward
    var end = cursorLineRng.upperBound
    while end < text.endIndex {
        guard text[end] == "\n" else { break }
        let nextStart = text.index(after: end)
        guard nextStart < text.endIndex else { break }
        let nextRange = lineRange(in: text, at: nextStart)
        let nextLine = String(text[nextRange])
        guard isTableRow(nextLine) else { break }
        items.append((nextLine, nextRange))
        end = nextRange.upperBound
    }

    guard !items.isEmpty else { return nil }

    // Find separator row
    var sepIdx: Int?
    for (i, item) in items.enumerated() {
        if isSeparatorRow(item.line) {
            sepIdx = i
            break
        }
    }

    // Column count from non-separator rows
    let colCount = items.enumerated()
        .filter { $0.offset != sepIdx }
        .map { splitTableCells($0.element.line).count }
        .max() ?? 0
    guard colCount > 0 else { return nil }

    return TableMatch(
        range: items.first!.range.lowerBound..<items.last!.range.upperBound,
        lines: items.map(\.line),
        lineRanges: items.map(\.range),
        separatorLineIndex: sepIdx,
        columnCount: colCount
    )
}

// MARK: - Table Alignment

/// Aligns table columns with space padding.
/// Each cell is padded to match the widest cell in its column.
func alignTable(rows: [[String]], separatorIndex: Int?, columnCount: Int) -> String {
    // Compute max width per column (minimum 3 for separator dashes "---")
    var widths = Array(repeating: 3, count: columnCount)
    for (i, row) in rows.enumerated() {
        if i == separatorIndex { continue }
        for (j, cell) in row.enumerated() where j < columnCount {
            widths[j] = max(widths[j], cell.count)
        }
    }

    // Build aligned lines
    var result: [String] = []
    for (i, row) in rows.enumerated() {
        if i == separatorIndex {
            let dashes = (0..<columnCount).map { String(repeating: "-", count: widths[$0]) }
            result.append("| " + dashes.joined(separator: " | ") + " |")
        } else {
            let padded = (0..<columnCount).map { j -> String in
                let cell = j < row.count ? row[j] : ""
                let padding = max(0, widths[j] - cell.count)
                return cell + String(repeating: " ", count: padding)
            }
            result.append("| " + padded.joined(separator: " | ") + " |")
        }
    }

    return result.joined(separator: "\n")
}

// MARK: - Cursor Utilities

/// Determines which row of the table the cursor is in.
func tableRowIndex(cursor: String.Index, lineRanges: [Range<String.Index>]) -> Int? {
    for (i, range) in lineRanges.enumerated() {
        if cursor >= range.lowerBound && cursor <= range.upperBound {
            return i
        }
    }
    return nil
}

/// Determines which cell the cursor is in within a table row line.
func tableCellIndex(in line: String, cursorOffsetInLine: Int) -> Int {
    var cellIdx = -1
    let clamped = min(cursorOffsetInLine, line.count)
    for (i, ch) in line.enumerated() {
        if i >= clamped { break }
        if ch == "|" { cellIdx += 1 }
    }
    return max(0, cellIdx)
}

/// Returns the character offset to position the cursor at the start of a cell
/// in an aligned table row (right after `| `).
func cursorOffsetForCell(in alignedLine: String, cellIndex: Int) -> Int {
    var pipesSeen = 0
    for (i, ch) in alignedLine.enumerated() {
        if ch == "|" {
            if pipesSeen == cellIndex {
                return min(i + 2, alignedLine.count)
            }
            pipesSeen += 1
        }
    }
    return alignedLine.count
}

/// Computes the cursor offset within the full aligned table text for a given row and cell.
func cursorOffsetInAlignedTable(alignedText: String, row: Int, cellIndex: Int) -> Int {
    var lineStart = alignedText.startIndex
    var currentRow = 0

    while currentRow < row && lineStart < alignedText.endIndex {
        // Find end of current line
        var lineEnd = lineStart
        while lineEnd < alignedText.endIndex && alignedText[lineEnd] != "\n" {
            lineEnd = alignedText.index(after: lineEnd)
        }
        if lineEnd < alignedText.endIndex {
            lineStart = alignedText.index(after: lineEnd)
        } else {
            lineStart = alignedText.endIndex
        }
        currentRow += 1
    }

    // Find end of target line
    var lineEnd = lineStart
    while lineEnd < alignedText.endIndex && alignedText[lineEnd] != "\n" {
        lineEnd = alignedText.index(after: lineEnd)
    }

    let targetLine = String(alignedText[lineStart..<lineEnd])
    let cellOffset = cursorOffsetForCell(in: targetLine, cellIndex: cellIndex)
    return alignedText.distance(from: alignedText.startIndex, to: lineStart) + cellOffset
}

// MARK: - Row Normalization

/// Normalizes all rows to the given column count (pads with empty cells or truncates).
func normalizeRows(_ rows: [[String]], columnCount: Int) -> [[String]] {
    rows.map { row in
        var r = row
        while r.count < columnCount { r.append("") }
        return Array(r.prefix(columnCount))
    }
}
