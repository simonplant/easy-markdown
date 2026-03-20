/// Computes ranges that should be excluded from spell checking per [A-054].
///
/// Walks the markdown AST and collects NSRanges for:
/// - Fenced and indented code blocks
/// - Inline code spans
/// - Link URLs (the destination part, not the link text)
/// - Image source paths
///
/// These ranges are used by the rendering pipeline to suppress spell checking
/// via the `.languageIdentifier` attribute set to "zxx" (BCP 47: no linguistic content).

import Foundation
import EMParser

/// Calculates which text ranges should be excluded from spell checking.
public enum SpellCheckExclusionCalculator {

    /// Returns NSRanges that should be excluded from spell checking.
    ///
    /// - Parameters:
    ///   - ast: The parsed markdown AST.
    ///   - sourceText: The raw markdown text matching the AST.
    /// - Returns: An array of NSRanges to exclude from spell checking.
    public static func exclusionRanges(
        from ast: MarkdownAST,
        sourceText: String
    ) -> [NSRange] {
        let lineOffsets = computeLineOffsets(in: sourceText)
        var ranges: [NSRange] = []
        collectExclusions(in: ast.root, sourceText: sourceText, lineOffsets: lineOffsets, into: &ranges)
        return ranges
    }

    // MARK: - Private

    private static func collectExclusions(
        in node: MarkdownNode,
        sourceText: String,
        lineOffsets: [Int],
        into ranges: inout [NSRange]
    ) {
        switch node.type {
        case .codeBlock:
            // Entire code block is excluded
            if let range = node.range,
               let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) {
                ranges.append(nsRange)
            }
            return // No need to recurse into code blocks

        case .inlineCode:
            // Entire inline code span is excluded
            if let range = node.range,
               let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) {
                ranges.append(nsRange)
            }
            return

        case .link:
            // Exclude the URL portion of the link, not the link text.
            // The link text (children) should still be spell-checked.
            // The URL is in the syntax after "](" — we exclude the full node range
            // minus the children's text ranges. However, since the children (link text)
            // should be checked, we add only the syntax/URL parts.
            if let nodeRange = node.range,
               let nodeNSRange = nsRange(from: nodeRange, in: sourceText, lineOffsets: lineOffsets) {
                excludeLinkSyntax(
                    node: node,
                    nodeNSRange: nodeNSRange,
                    sourceText: sourceText,
                    lineOffsets: lineOffsets,
                    into: &ranges
                )
            }
            // Recurse into children (link text) — they should be spell-checked normally
            for child in node.children {
                collectExclusions(in: child, sourceText: sourceText, lineOffsets: lineOffsets, into: &ranges)
            }
            return

        case .image:
            // Entire image node is excluded (source path + alt text are not prose)
            if let range = node.range,
               let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) {
                ranges.append(nsRange)
            }
            return

        default:
            break
        }

        // Recurse into children
        for child in node.children {
            collectExclusions(in: child, sourceText: sourceText, lineOffsets: lineOffsets, into: &ranges)
        }
    }

    /// Excludes the syntax portions of a link (brackets and URL) while allowing
    /// the link text (between [ and ]) to remain spell-checkable.
    private static func excludeLinkSyntax(
        node: MarkdownNode,
        nodeNSRange: NSRange,
        sourceText: String,
        lineOffsets: [Int],
        into ranges: inout [NSRange]
    ) {
        let text = sourceText
        guard let swiftRange = Range(nodeNSRange, in: text) else { return }
        let content = text[swiftRange]

        // Find "](" which separates link text from URL
        guard let closeBracketParen = content.range(of: "](") else {
            // Fallback: exclude the whole node if we can't parse the syntax
            ranges.append(nodeNSRange)
            return
        }

        // Exclude opening "[" (1 character)
        let openBracket = NSRange(location: nodeNSRange.location, length: 1)
        ranges.append(openBracket)

        // Exclude "](url)" portion — from "](" to end of node.
        // Use NSRange conversion to get correct UTF-16 offsets (safe for emoji/CJK).
        let syntaxNSRange = NSRange(closeBracketParen.lowerBound..<swiftRange.upperBound, in: text)
        if syntaxNSRange.length > 0 {
            ranges.append(syntaxNSRange)
        }
    }

    // MARK: - Line Offset Computation

    /// Pre-computes UTF-16 offsets for each line start for fast range conversion.
    private static func computeLineOffsets(in text: String) -> [Int] {
        var offsets: [Int] = [0]
        var utf16Offset = 0
        for char in text {
            let charWidth = String(char).utf16.count
            utf16Offset += charWidth
            if char == "\n" {
                offsets.append(utf16Offset)
            }
        }
        return offsets
    }

    /// Converts a SourceRange (1-based line:column) to an NSRange using pre-computed line offsets.
    private static func nsRange(from sourceRange: SourceRange, in text: String, lineOffsets: [Int]) -> NSRange? {
        guard !text.isEmpty else { return nil }

        let startLine = sourceRange.start.line - 1
        let endLine = sourceRange.end.line - 1

        guard startLine >= 0, startLine < lineOffsets.count,
              endLine >= 0, endLine < lineOffsets.count else {
            return nil
        }

        let startOffset = lineOffsets[startLine] + max(0, sourceRange.start.column - 1)
        let endOffset = lineOffsets[endLine] + max(0, sourceRange.end.column - 1)

        let length = endOffset - startOffset
        guard length >= 0, startOffset >= 0, endOffset <= text.utf16.count else {
            return nil
        }

        return NSRange(location: startOffset, length: length)
    }
}
