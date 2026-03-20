import EMCore
import EMParser
import Foundation

/// Detects missing blank lines between block-level elements.
///
/// CommonMark requires blank lines between certain block elements for
/// correct parsing. Even where not strictly required, blank lines between
/// blocks improve readability. This rule checks for missing blank lines
/// between adjacent block elements (headings, paragraphs, code blocks,
/// blockquotes, lists, thematic breaks, tables).
struct MissingBlankLineRule: DoctorRule {
    let ruleID = "missing-blank-line"

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let blocks = context.ast.root.children
        guard blocks.count > 1 else { return [] }

        let lines = context.text.split(separator: "\n", omittingEmptySubsequences: false)
        var diagnostics: [Diagnostic] = []

        for i in 0..<(blocks.count - 1) {
            guard let currentRange = blocks[i].range,
                  let nextRange = blocks[i + 1].range else {
                continue
            }

            let currentEnd = currentRange.end.line
            let nextStart = nextRange.start.line

            // If the next block starts on the line immediately after the current block ends,
            // there is no blank line between them.
            if nextStart == currentEnd + 1 {
                // Verify by checking if the line between is truly not blank
                // (the AST positions are 1-based, array is 0-based)
                let needsFix = isBlockPairRequiringBlankLine(blocks[i].type, blocks[i + 1].type)
                if needsFix {
                    // Calculate the offset at the end of currentEnd line
                    let insertOffset: Int
                    if currentEnd - 1 < lines.count {
                        var offset = 0
                        for lineIdx in 0..<currentEnd {
                            offset += lines[lineIdx].utf8.count + 1 // +1 for newline
                        }
                        insertOffset = offset
                    } else {
                        continue
                    }

                    diagnostics.append(Diagnostic(
                        ruleID: ruleID,
                        message: "Missing blank line before \(blockName(blocks[i + 1].type)).",
                        severity: .warning,
                        line: nextStart,
                        fix: DiagnosticFix(
                            label: "Insert blank line",
                            range: DiagnosticTextRange(startOffset: insertOffset, length: 0),
                            replacement: "\n"
                        )
                    ))
                }
            }
        }

        return diagnostics
    }

    /// Determines whether a blank line should exist between two block types.
    private func isBlockPairRequiringBlankLine(_ a: MarkdownNodeType, _ b: MarkdownNodeType) -> Bool {
        // Heading followed by anything or anything followed by heading
        if isHeading(a) || isHeading(b) { return true }
        // Code block boundaries
        if isCodeBlock(a) || isCodeBlock(b) { return true }
        // Blockquote boundaries
        if isBlockQuote(a) != isBlockQuote(b) { return true }
        // List followed by non-list or vice versa
        if isList(a) != isList(b) { return true }
        // Thematic break
        if isThematicBreak(a) || isThematicBreak(b) { return true }
        // Table boundaries
        if isTable(a) != isTable(b) { return true }
        return false
    }

    private func isHeading(_ type: MarkdownNodeType) -> Bool {
        if case .heading = type { return true }
        return false
    }

    private func isCodeBlock(_ type: MarkdownNodeType) -> Bool {
        if case .codeBlock = type { return true }
        return false
    }

    private func isBlockQuote(_ type: MarkdownNodeType) -> Bool {
        type == .blockQuote
    }

    private func isList(_ type: MarkdownNodeType) -> Bool {
        type == .orderedList || type == .unorderedList
    }

    private func isThematicBreak(_ type: MarkdownNodeType) -> Bool {
        type == .thematicBreak
    }

    private func isTable(_ type: MarkdownNodeType) -> Bool {
        type == .table
    }

    private func blockName(_ type: MarkdownNodeType) -> String {
        switch type {
        case .heading: return "heading"
        case .paragraph: return "paragraph"
        case .codeBlock: return "code block"
        case .blockQuote: return "blockquote"
        case .orderedList, .unorderedList: return "list"
        case .thematicBreak: return "thematic break"
        case .table: return "table"
        default: return "block"
        }
    }
}
