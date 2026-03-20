/// Maps cursor positions between rich and source views per [A-021] and FEAT-050.
///
/// When toggling views, the cursor should land at the same logical paragraph
/// (best-effort same line). Both views share the same `NSTextContentStorage`
/// so NSRange positions map to the same raw text — but in rich view, syntax
/// characters are hidden via zero-width font, so a cursor "between" hidden
/// characters should snap to the nearest visible content boundary.

import Foundation
import EMParser

/// Maps cursor positions between rich and source views using AST source positions.
public struct CursorMapper {

    public init() {}

    /// Maps a cursor position when toggling from source view to rich view.
    ///
    /// In rich view, some ranges are hidden (e.g., `#`, `**`, `` ` ``).
    /// If the cursor is inside a syntax marker, snap it to the start of the
    /// visible content for that AST node.
    ///
    /// - Parameters:
    ///   - range: The current selected range (in source view).
    ///   - text: The raw markdown text.
    ///   - ast: The current parsed AST (may be nil for empty/unparsed docs).
    /// - Returns: The adjusted NSRange for rich view.
    public func mapSourceToRich(
        selectedRange range: NSRange,
        text: String,
        ast: MarkdownAST?
    ) -> NSRange {
        guard !text.isEmpty, range.location <= text.utf16.count else {
            return NSRange(location: 0, length: 0)
        }

        guard let ast else { return range }

        // Find the source position at the cursor
        let cursorOffset = range.location
        guard let position = sourcePosition(atUTF16Offset: cursorOffset, in: text) else {
            return range
        }

        // Find the deepest node at this position
        guard let node = ast.node(at: position) else {
            return range
        }

        // If cursor is inside a syntax prefix (e.g., "# ", "```", "> "),
        // snap to the start of the node's visible content.
        let adjustedOffset = adjustForHiddenSyntax(
            cursorOffset: cursorOffset,
            node: node,
            text: text
        )

        if adjustedOffset != cursorOffset {
            return NSRange(location: adjustedOffset, length: 0)
        }

        return range
    }

    /// Maps a cursor position when toggling from rich view to source view.
    ///
    /// Source view shows everything, so the main concern is preserving
    /// the logical position (same paragraph/line).
    ///
    /// - Parameters:
    ///   - range: The current selected range (in rich view).
    ///   - text: The raw markdown text.
    ///   - ast: The current parsed AST (may be nil for empty/unparsed docs).
    /// - Returns: The NSRange for source view.
    public func mapRichToSource(
        selectedRange range: NSRange,
        text: String,
        ast: MarkdownAST?
    ) -> NSRange {
        guard !text.isEmpty, range.location <= text.utf16.count else {
            return NSRange(location: 0, length: 0)
        }

        // Rich and source share the same text, so the NSRange is valid in
        // both views. The position is already correct for source view.
        return range
    }

    // MARK: - Source Position Conversion

    /// Converts a UTF-16 offset to a 1-based SourcePosition.
    func sourcePosition(atUTF16Offset offset: Int, in text: String) -> SourcePosition? {
        guard offset >= 0, offset <= text.utf16.count else { return nil }

        var line = 1
        var column = 1
        var currentOffset = 0

        for char in text {
            let charWidth = String(char).utf16.count
            if currentOffset >= offset {
                break
            }
            if char == "\n" {
                line += 1
                column = 1
            } else {
                column += charWidth
            }
            currentOffset += charWidth
        }

        return SourcePosition(line: line, column: column)
    }

    /// Converts a 1-based SourcePosition to a UTF-16 offset.
    func utf16Offset(for position: SourcePosition, in text: String) -> Int? {
        guard position.line >= 1, position.column >= 1 else { return nil }

        var currentLine = 1
        var utf16Offset = 0

        for char in text {
            if currentLine == position.line {
                break
            }
            let charWidth = String(char).utf16.count
            utf16Offset += charWidth
            if char == "\n" {
                currentLine += 1
            }
        }

        guard currentLine == position.line else { return nil }

        // Add column offset (1-based)
        utf16Offset += max(0, position.column - 1)
        return min(utf16Offset, text.utf16.count)
    }

    // MARK: - Syntax-Aware Adjustment

    /// If the cursor is inside a hidden syntax prefix for a block-level node,
    /// returns an offset snapped past the prefix. Otherwise returns the original offset.
    private func adjustForHiddenSyntax(
        cursorOffset: Int,
        node: MarkdownNode,
        text: String
    ) -> Int {
        guard let range = node.range else { return cursorOffset }

        // Get the UTF-16 offset of the node start
        guard let nodeStartOffset = utf16Offset(
            for: range.start,
            in: text
        ) else {
            return cursorOffset
        }

        // Only adjust if cursor is very close to the node start (within syntax prefix)
        let offsetIntoNode = cursorOffset - nodeStartOffset
        guard offsetIntoNode >= 0 else { return cursorOffset }

        // Determine the syntax prefix length for this node type
        let prefixLength = syntaxPrefixLength(for: node, in: text, at: nodeStartOffset)

        if prefixLength > 0 && offsetIntoNode < prefixLength {
            // Snap cursor past the syntax prefix
            return nodeStartOffset + prefixLength
        }

        return cursorOffset
    }

    /// Returns the UTF-16 length of the syntax prefix that gets hidden in rich view.
    private func syntaxPrefixLength(
        for node: MarkdownNode,
        in text: String,
        at nodeStartUTF16: Int
    ) -> Int {
        guard let swiftStart = text.utf16.index(
            text.startIndex,
            offsetBy: nodeStartUTF16,
            limitedBy: text.endIndex
        ) else {
            return 0
        }

        let remaining = text[swiftStart...]

        switch node.type {
        case .heading(_):
            // "# ", "## ", "### ", etc.
            var count = 0
            for char in remaining {
                if char == "#" {
                    count += 1
                } else if char == " " && count > 0 {
                    return count + 1 // hashes + space
                } else {
                    break
                }
            }
            return 0

        case .blockQuote:
            // "> " prefix
            if remaining.hasPrefix("> ") { return 2 }
            if remaining.hasPrefix(">") { return 1 }
            return 0

        case .listItem(_):
            // "- ", "* ", "+ ", "1. ", "12. ", etc.
            let line = remaining.prefix(while: { $0 != "\n" })
            // Skip leading whitespace
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let whitespaceCount = line.count - trimmed.count
                return whitespaceCount + 2
            }
            // Ordered list: digits followed by "." or ")" then space
            var digits = 0
            for char in trimmed {
                if char.isNumber {
                    digits += 1
                } else if digits > 0 && (char == "." || char == ")") {
                    // Check for trailing space
                    let markerLength = digits + 1
                    let afterMarker = trimmed.dropFirst(markerLength)
                    if afterMarker.hasPrefix(" ") {
                        let whitespaceCount = line.count - trimmed.count
                        return whitespaceCount + markerLength + 1
                    }
                    break
                } else {
                    break
                }
            }
            return 0

        default:
            return 0
        }
    }
}
