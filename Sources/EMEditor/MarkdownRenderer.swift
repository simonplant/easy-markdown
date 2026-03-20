/// AST → NSAttributedString rendering pipeline per [A-018].
///
/// Walks the parsed AST and applies styled attributes to an `NSMutableAttributedString`
/// that shares the same text as the underlying `NSTextContentStorage`. In rich view,
/// syntax characters (e.g., `#`, `**`, `- `) are hidden via zero-width font.
/// In source view, raw markdown is shown with syntax coloring.
///
/// Thread-safe: rendering operates on value types (AST, config) and produces
/// attribute arrays that are applied on the main actor.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMParser

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "renderer")

// MARK: - Rendering Configuration

/// Configuration for the markdown rendering pipeline.
public struct RenderConfiguration: Sendable {
    public let typeScale: TypeScale
    public let colors: ThemeColors
    public let isSourceView: Bool
    /// Identifies the color variant (e.g. "light" or "dark") for change detection.
    public let colorVariant: String
    /// Device-aware layout metrics for spacing and typography per FEAT-010.
    public let layoutMetrics: LayoutMetrics
    /// URL of the current document file, used to resolve relative image paths per [A-053].
    public let documentURL: URL?

    public init(
        typeScale: TypeScale,
        colors: ThemeColors,
        isSourceView: Bool,
        colorVariant: String = "light",
        layoutMetrics: LayoutMetrics = .current,
        documentURL: URL? = nil
    ) {
        self.typeScale = typeScale
        self.colors = colors
        self.isSourceView = isSourceView
        self.colorVariant = colorVariant
        self.layoutMetrics = layoutMetrics
        self.documentURL = documentURL
    }
}

// MARK: - Custom Attribute Keys

/// Custom attribute keys for markdown-specific rendering.
extension NSAttributedString.Key {
    /// Marks a range as a blockquote for custom border drawing.
    static let blockquoteBorder = NSAttributedString.Key("em.blockquoteBorder")

    /// Marks a range as a thematic break for custom line drawing.
    static let thematicBreak = NSAttributedString.Key("em.thematicBreak")

    /// Marks a range with its markdown node type for accessibility.
    static let markdownNodeType = NSAttributedString.Key("em.markdownNodeType")

    /// Marks a range as a table header row for distinct styling per FEAT-047.
    static let tableHeader = NSAttributedString.Key("em.tableHeader")

    /// Marks a range as a task list checkbox for tap detection per FEAT-049.
    /// Value is "checked" or "unchecked".
    static let taskListCheckbox = NSAttributedString.Key("em.taskListCheckbox")

    /// Marks a range as excluded from spell checking per [A-054].
    static let spellCheckExcluded = NSAttributedString.Key("em.spellCheckExcluded")

    /// Marks a range as an inline image per FEAT-048.
    /// Value is the resolved URL string of the image source.
    static let imageSource = NSAttributedString.Key("em.imageSource")

    /// Alt text for an inline image per FEAT-048.
    static let imageAltText = NSAttributedString.Key("em.imageAltText")

    /// Language identifier attribute for spell check suppression.
    /// "NSLanguage" is the CoreText/Foundation key recognized by the text system
    /// on both iOS and macOS for per-range language identification.
    static let spellCheckLanguage = NSAttributedString.Key("NSLanguage")
}

// MARK: - Markdown Renderer

/// Renders a markdown AST as styled `NSAttributedString` attributes per [A-018].
///
/// The renderer walks the AST and computes attribute ranges that map to the raw
/// markdown text. It supports two modes:
/// - **Rich view**: Styled text with syntax characters hidden
/// - **Source view**: Raw markdown with syntax coloring
///
/// Performance target: <16ms for a typical document per [D-PERF-2].
public struct MarkdownRenderer {

    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "render"
    )

    /// Image loader for inline image rendering per [A-053] and FEAT-048.
    public let imageLoader = ImageLoader()

    public init() {}

    /// Renders the given AST onto a mutable attributed string.
    ///
    /// - Parameters:
    ///   - attributedString: The mutable attributed string to style (text must match source).
    ///   - ast: The parsed markdown AST.
    ///   - sourceText: The raw markdown text (must match attributedString's string).
    ///   - config: Rendering configuration (fonts, colors, mode).
    @MainActor
    public func render(
        into attributedString: NSMutableAttributedString,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration
    ) {
        signpost.begin("render")
        defer { signpost.end("render") }

        let fullRange = NSRange(location: 0, length: attributedString.length)

        // Reset to base attributes
        let baseAttributes = baseAttributes(config: config)
        attributedString.setAttributes(baseAttributes, range: fullRange)

        // Pre-compute line offsets for fast SourceRange → NSRange conversion.
        // This avoids O(lines * nodes) performance from repeated splitting.
        let lineOffsets = computeLineOffsets(in: sourceText)

        if config.isSourceView {
            renderSourceView(
                into: attributedString,
                ast: ast,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )
        } else {
            renderRichView(
                into: attributedString,
                ast: ast,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )
        }

        // Apply spell check exclusions per [A-054].
        // Marks code blocks, code spans, URLs, and image paths with
        // language "zxx" (BCP 47: no linguistic content) so the system
        // spell checker skips them.
        applySpellCheckExclusions(
            to: attributedString,
            ast: ast,
            sourceText: sourceText
        )
    }

    /// Pre-computes UTF-16 offsets for each line start for fast range conversion.
    /// Index i holds the UTF-16 offset of the start of line (i+1) in 1-based terms.
    private func computeLineOffsets(in text: String) -> [Int] {
        var offsets: [Int] = [0] // Line 1 starts at offset 0
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

    // MARK: - Base Attributes

    private func baseAttributes(config: RenderConfiguration) -> [NSAttributedString.Key: Any] {
        let metrics = config.layoutMetrics
        let bodySize = config.typeScale.bodyFontSize

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = metrics.lineSpacing(forFontSize: bodySize)
        paragraphStyle.paragraphSpacing = metrics.paragraphSpacing(forFontSize: bodySize)
        paragraphStyle.alignment = .natural

        return [
            .font: config.typeScale.body,
            .foregroundColor: config.colors.foreground,
            .paragraphStyle: paragraphStyle,
        ]
    }

    // MARK: - Rich View Rendering

    private func renderRichView(
        into attrStr: NSMutableAttributedString,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        for block in ast.blocks {
            renderBlockNode(
                block,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                nestingLevel: 0,
                lineOffsets: lineOffsets
            )
        }
    }

    private func renderBlockNode(
        _ node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        nestingLevel: Int,
        lineOffsets: [Int]
    ) {
        guard let range = node.range,
              let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) else {
            return
        }

        switch node.type {
        case .heading(let level):
            renderHeading(
                node,
                level: level,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )

        case .paragraph:
            renderInlineChildren(
                of: node,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )

        case .blockQuote:
            renderBlockquote(
                node,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                nestingLevel: nestingLevel,
                lineOffsets: lineOffsets
            )

        case .orderedList, .unorderedList:
            for child in node.children {
                renderBlockNode(
                    child,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    nestingLevel: nestingLevel,
                    lineOffsets: lineOffsets
                )
            }

        case .listItem:
            renderListItem(
                node,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                nestingLevel: nestingLevel,
                lineOffsets: lineOffsets
            )

        case .codeBlock:
            renderCodeBlock(
                node,
                nsRange: nsRange,
                into: attrStr,
                config: config
            )

        case .thematicBreak:
            renderThematicBreak(
                nsRange: nsRange,
                into: attrStr,
                config: config
            )

        case .table:
            renderTable(
                node,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )

        default:
            // Recurse into children for unknown block types
            for child in node.children {
                renderBlockNode(
                    child,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    nestingLevel: nestingLevel,
                    lineOffsets: lineOffsets
                )
            }
        }
    }

    // MARK: - Headings

    private func renderHeading(
        _ node: MarkdownNode,
        level: Int,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        let font = config.typeScale.headingFont(level: level)
        let metrics = config.layoutMetrics
        let headingSize = font.pointSize

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = metrics.lineSpacing(forFontSize: headingSize)
        paragraphStyle.alignment = .natural
        // More spacing around higher-level headings, scaled from metrics
        let baseSpacing = metrics.paragraphSpacing(forFontSize: headingSize)
        paragraphStyle.paragraphSpacingBefore = level <= 2 ? baseSpacing * 1.5 : baseSpacing * 1.2
        paragraphStyle.paragraphSpacing = level <= 2 ? baseSpacing * 1.2 : baseSpacing

        attrStr.addAttributes([
            .font: font,
            .foregroundColor: config.colors.heading,
            .paragraphStyle: paragraphStyle,
            .markdownNodeType: "heading\(level)",
        ], range: nsRange)

        // Hide heading markers (e.g., "# ", "## ")
        hideSyntaxPrefix(
            pattern: "^#{1,6}\\s",
            in: nsRange,
            attrStr: attrStr,
            sourceText: sourceText
        )

        // Render inline formatting within heading text
        renderInlineChildren(
            of: node,
            into: attrStr,
            sourceText: sourceText,
            config: config,
            lineOffsets: lineOffsets
        )

        // Accessibility: mark as heading
        #if canImport(UIKit)
        attrStr.addAttribute(
            .accessibilityTextHeadingLevel,
            value: NSNumber(value: level),
            range: nsRange
        )
        #endif
    }

    // MARK: - Lists

    private func renderListItem(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        nestingLevel: Int,
        lineOffsets: [Int]
    ) {
        // Determine effective nesting by walking up through list/listItem ancestors
        let effectiveNesting = countListNesting(node, sourceText: sourceText)
        let indentLevel = max(effectiveNesting, nestingLevel)

        let metrics = config.layoutMetrics
        let bodySize = config.typeScale.bodyFontSize
        let indent = CGFloat(indentLevel) * 24.0 + 24.0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.lineSpacing = metrics.lineSpacing(forFontSize: bodySize)
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent - 18.0
        paragraphStyle.paragraphSpacing = metrics.paragraphSpacing(forFontSize: bodySize) * 0.5
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]

        attrStr.addAttributes([
            .paragraphStyle: paragraphStyle,
            .markdownNodeType: "listItem",
        ], range: nsRange)

        // Hide the raw list marker in rich view (e.g., "- ", "* ", "1. ")
        hideSyntaxPrefix(
            pattern: "^\\s*(?:[*\\-+]|\\d+[.)]) ",
            in: nsRange,
            attrStr: attrStr,
            sourceText: sourceText
        )

        // Render task list checkbox per FEAT-049
        if case .listItem(checkbox: let checkbox) = node.type, let checkbox {
            renderTaskListCheckbox(
                checkbox: checkbox,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config
            )
        }

        // Process child blocks (paragraphs, nested lists)
        for child in node.children {
            switch child.type {
            case .orderedList, .unorderedList:
                for listChild in child.children {
                    renderBlockNode(
                        listChild,
                        into: attrStr,
                        sourceText: sourceText,
                        config: config,
                        nestingLevel: indentLevel + 1,
                        lineOffsets: lineOffsets
                    )
                }
            case .paragraph:
                renderInlineChildren(
                    of: child,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    lineOffsets: lineOffsets
                )
            default:
                renderBlockNode(
                    child,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    nestingLevel: indentLevel,
                    lineOffsets: lineOffsets
                )
            }
        }
    }

    /// Counts list nesting depth by examining the source indentation.
    private func countListNesting(_ node: MarkdownNode, sourceText: String) -> Int {
        guard let range = node.range else { return 0 }
        // Use column position as a proxy for nesting depth
        // Each indent level is typically 2-4 characters
        let column = range.start.column
        return max(0, (column - 1) / 2)
    }

    // MARK: - Task List Checkboxes (FEAT-049)

    /// Renders a task list checkbox with interactive styling and custom attribute.
    ///
    /// Finds `[ ]` or `[x]` within the list item range and applies the
    /// `.taskListCheckbox` attribute for tap detection, plus link color
    /// to signal interactivity.
    private func renderTaskListCheckbox(
        checkbox: Checkbox,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration
    ) {
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let content = text[swiftRange]

        // Find [ ] or [x]/[X] within the list item text
        let checkboxRange: Range<Substring.Index>
        if checkbox == .checked {
            // GFM allows both [x] and [X]
            if let r = content.range(of: "[x]") {
                checkboxRange = r
            } else if let r = content.range(of: "[X]") {
                checkboxRange = r
            } else {
                return
            }
        } else {
            guard let r = content.range(of: "[ ]") else { return }
            checkboxRange = r
        }
        let checkboxNSRange = NSRange(checkboxRange, in: text)

        // Apply custom attribute for tap detection per FEAT-049
        let state = checkbox == .checked ? "checked" : "unchecked"
        attrStr.addAttribute(.taskListCheckbox, value: state, range: checkboxNSRange)

        // Style with link color to signal interactivity
        attrStr.addAttribute(.foregroundColor, value: config.colors.link, range: checkboxNSRange)
    }

    // MARK: - Blockquotes

    private func renderBlockquote(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        nestingLevel: Int,
        lineOffsets: [Int]
    ) {
        let metrics = config.layoutMetrics
        let bodySize = config.typeScale.bodyFontSize
        let indent: CGFloat = 16.0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.lineSpacing = metrics.lineSpacing(forFontSize: bodySize)
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = metrics.paragraphSpacing(forFontSize: bodySize) * 0.5

        attrStr.addAttributes([
            .foregroundColor: config.colors.blockquoteForeground,
            .paragraphStyle: paragraphStyle,
            .blockquoteBorder: config.colors.blockquoteBorder,
            .markdownNodeType: "blockquote",
        ], range: nsRange)

        // Hide blockquote markers ("> ")
        hideBlockquoteMarkers(in: nsRange, attrStr: attrStr, sourceText: sourceText)

        // Recurse into blockquote children
        for child in node.children {
            renderBlockNode(
                child,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                nestingLevel: nestingLevel,
                lineOffsets: lineOffsets
            )
        }
    }

    private func hideBlockquoteMarkers(
        in nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let substring = text[swiftRange]

        // Find all "> " prefixes in each line
        var searchStart = substring.startIndex
        while searchStart < substring.endIndex {
            let lineEnd = substring[searchStart...].firstIndex(of: "\n") ?? substring.endIndex
            let line = substring[searchStart..<lineEnd]

            // Match leading "> " or ">" at start of line within blockquote
            if line.hasPrefix("> ") {
                let markerRange = searchStart..<substring.index(searchStart, offsetBy: 2)
                let markerNSRange = NSRange(markerRange, in: text)
                applySyntaxHiding(to: markerNSRange, in: attrStr)
            } else if line.hasPrefix(">") {
                let markerRange = searchStart..<substring.index(searchStart, offsetBy: 1)
                let markerNSRange = NSRange(markerRange, in: text)
                applySyntaxHiding(to: markerNSRange, in: attrStr)
            }

            searchStart = lineEnd < substring.endIndex
                ? substring.index(after: lineEnd)
                : substring.endIndex
        }
    }

    // MARK: - Code Blocks

    private let syntaxHighlighter = SyntaxHighlighter()

    private func renderCodeBlock(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        config: RenderConfiguration
    ) {
        let metrics = config.layoutMetrics
        let codeSize = config.typeScale.code.pointSize
        let blockSpacing = metrics.paragraphSpacing(forFontSize: codeSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.lineSpacing = metrics.lineSpacing(forFontSize: codeSize) * 0.75
        paragraphStyle.paragraphSpacing = blockSpacing
        paragraphStyle.paragraphSpacingBefore = blockSpacing

        attrStr.addAttributes([
            .font: config.typeScale.code,
            .foregroundColor: config.colors.codeForeground,
            .backgroundColor: config.colors.codeBackground,
            .paragraphStyle: paragraphStyle,
            .markdownNodeType: "codeBlock",
        ], range: nsRange)

        // Apply syntax highlighting to the code content per FEAT-006
        let language = node.codeBlockLanguage
        if let contentRange = codeContentRange(in: nsRange, sourceText: attrStr.string) {
            syntaxHighlighter.highlight(
                in: attrStr,
                contentRange: contentRange,
                language: language,
                colors: config.colors,
                codeFont: config.typeScale.code
            )
        }

        // Hide fence markers (``` lines) in rich view
        hideFenceMarkers(in: nsRange, attrStr: attrStr, sourceText: attrStr.string)
    }

    /// Extracts the NSRange of code content between opening and closing fence lines.
    /// Returns nil for empty code blocks or blocks without fences.
    private func codeContentRange(in nsRange: NSRange, sourceText: String) -> NSRange? {
        guard let swiftRange = Range(nsRange, in: sourceText) else { return nil }
        let substring = sourceText[swiftRange]
        let lines = substring.split(separator: "\n", omittingEmptySubsequences: false)

        guard lines.count >= 2 else { return nil }

        // Opening fence is first line, closing fence is last line
        guard let firstLine = lines.first, firstLine.hasPrefix("```") else { return nil }

        // Content starts after the first line (+ 1 for the newline)
        let contentStart = substring.index(substring.startIndex, offsetBy: firstLine.count + 1,
                                           limitedBy: substring.endIndex) ?? substring.endIndex

        // Content ends before the last line
        let lastLine = lines.last ?? Substring("")
        let closingFenceLength = lastLine.hasPrefix("```") ? lastLine.count : 0
        // Subtract closing fence length and the preceding newline (if present)
        let contentEnd: String.Index
        if closingFenceLength > 0 && substring.endIndex > substring.startIndex {
            let beforeClosing = substring.index(substring.endIndex, offsetBy: -closingFenceLength,
                                                 limitedBy: substring.startIndex) ?? substring.startIndex
            // Also skip the newline before closing fence
            if beforeClosing > contentStart && beforeClosing > substring.startIndex,
               sourceText[sourceText.index(before: beforeClosing)] == "\n" {
                contentEnd = sourceText.index(before: beforeClosing)
            } else {
                contentEnd = beforeClosing
            }
        } else {
            contentEnd = substring.endIndex
        }

        guard contentStart <= contentEnd else { return nil }

        let contentNSRange = NSRange(contentStart..<contentEnd, in: sourceText)
        guard contentNSRange.length > 0 else { return nil }
        return contentNSRange
    }

    private func hideFenceMarkers(
        in nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        guard let swiftRange = Range(nsRange, in: sourceText) else { return }
        let substring = sourceText[swiftRange]
        let lines = substring.split(separator: "\n", omittingEmptySubsequences: false)

        guard lines.count >= 2 else { return }

        // Hide opening fence (first line if it starts with ```)
        if let firstLine = lines.first, firstLine.hasPrefix("```") {
            let lineRange = substring.startIndex..<substring.index(
                substring.startIndex,
                offsetBy: firstLine.count
            )
            let lineNSRange = NSRange(lineRange, in: sourceText)
            applySyntaxHiding(to: lineNSRange, in: attrStr)
        }

        // Hide closing fence (last line if it starts with ```)
        if let lastLine = lines.last, lastLine.hasPrefix("```") {
            let lastLineStart = substring.index(
                substring.endIndex,
                offsetBy: -lastLine.count
            )
            let lineRange = lastLineStart..<substring.endIndex
            let lineNSRange = NSRange(lineRange, in: sourceText)
            applySyntaxHiding(to: lineNSRange, in: attrStr)
        }
    }

    // MARK: - Thematic Break

    private func renderThematicBreak(
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        config: RenderConfiguration
    ) {
        let metrics = config.layoutMetrics
        let bodySize = config.typeScale.bodyFontSize
        let breakSpacing = metrics.paragraphSpacing(forFontSize: bodySize) * 1.2
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacingBefore = breakSpacing
        paragraphStyle.paragraphSpacing = breakSpacing

        attrStr.addAttributes([
            .foregroundColor: config.colors.thematicBreak,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: config.colors.thematicBreak,
            .paragraphStyle: paragraphStyle,
            .thematicBreak: true,
            .markdownNodeType: "thematicBreak",
        ], range: nsRange)
    }

    // MARK: - Tables (FEAT-047)

    /// Renders a GFM table with column alignment, header styling, and cell padding.
    ///
    /// Strategy: monospace font for natural column alignment, bold header row,
    /// hidden separator row, pipe characters styled as visual dividers, and
    /// subtle background to distinguish the table region.
    private func renderTable(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        let codeFont = config.typeScale.code
        let codeSize = codeFont.pointSize
        let metrics = config.layoutMetrics

        // Compact paragraph style for table rows — tighter than body text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = metrics.lineSpacing(forFontSize: codeSize) * 0.5
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.paragraphSpacingBefore = 0
        paragraphStyle.alignment = .natural

        // Base table attributes: monospace font + subtle background
        attrStr.addAttributes([
            .font: codeFont,
            .foregroundColor: config.colors.foreground,
            .backgroundColor: config.colors.codeBackground,
            .paragraphStyle: paragraphStyle,
            .markdownNodeType: "table",
        ], range: nsRange)

        // Style header and body from AST structure
        for child in node.children {
            switch child.type {
            case .tableHead:
                renderTableHead(
                    child,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    lineOffsets: lineOffsets
                )
            case .tableBody:
                renderTableBody(
                    child,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    lineOffsets: lineOffsets
                )
            default:
                break
            }
        }

        // Hide the separator row (e.g., |---|---|) — purely syntactic
        hideTableSeparatorRow(in: nsRange, attrStr: attrStr, sourceText: sourceText)

        // Style pipe characters as visual dividers
        styleTablePipes(in: nsRange, attrStr: attrStr, colors: config.colors)
    }

    /// Renders the table header row with bold font for visual distinction.
    private func renderTableHead(
        _ node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        guard let range = node.range,
              let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) else {
            return
        }

        let boldCodeFont = fontWithTrait(config.typeScale.code, trait: .traitBold)
        attrStr.addAttributes([
            .font: boldCodeFont,
            .foregroundColor: config.colors.heading,
            .tableHeader: true,
        ], range: nsRange)

        // Render inline formatting within header cells
        for row in node.children {
            for cell in row.children {
                renderInlineChildren(
                    of: cell,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    lineOffsets: lineOffsets
                )
            }
        }
    }

    /// Renders inline formatting within table body cells.
    private func renderTableBody(
        _ node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        for row in node.children {
            for cell in row.children {
                renderInlineChildren(
                    of: cell,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config,
                    lineOffsets: lineOffsets
                )
            }
        }
    }

    /// Hides the GFM separator row (e.g., `|---|:---:|---:`) with zero-width font.
    private func hideTableSeparatorRow(
        in nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        guard let swiftRange = Range(nsRange, in: sourceText) else { return }
        let tableText = sourceText[swiftRange]

        var lineStart = tableText.startIndex
        while lineStart < tableText.endIndex {
            let lineEnd = tableText[lineStart...].firstIndex(of: "\n") ?? tableText.endIndex
            let line = tableText[lineStart..<lineEnd]

            if isTableSeparatorRow(line) {
                let hideRange = NSRange(lineStart..<lineEnd, in: sourceText)
                applySyntaxHiding(to: hideRange, in: attrStr)
            }

            lineStart = lineEnd < tableText.endIndex
                ? tableText.index(after: lineEnd)
                : tableText.endIndex
        }
    }

    /// Checks if a line is a GFM table separator row (only `|`, `-`, `:`, and whitespace).
    private func isTableSeparatorRow(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|:- ".contains($0) }
    }

    /// Colors pipe characters as visual dividers within visible table rows.
    private func styleTablePipes(
        in nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        colors: ThemeColors
    ) {
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }

        var index = swiftRange.lowerBound
        while index < swiftRange.upperBound {
            if text[index] == "|" {
                let charNSRange = NSRange(index...index, in: text)
                // Skip pipes in the hidden separator row (font < 0.1pt)
                if let font = attrStr.attribute(.font, at: charNSRange.location, effectiveRange: nil) as? PlatformFont,
                   font.pointSize > 0.1 {
                    attrStr.addAttribute(.foregroundColor, value: colors.divider, range: charNSRange)
                }
            }
            index = text.index(after: index)
        }
    }

    // MARK: - Inline Rendering

    private func renderInlineChildren(
        of node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        for child in node.children {
            renderInlineNode(
                child,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )
        }
    }

    private func renderInlineNode(
        _ node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        guard let range = node.range,
              let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) else {
            return
        }

        switch node.type {
        case .strong:
            renderStrong(node, nsRange: nsRange, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)

        case .emphasis:
            renderEmphasis(node, nsRange: nsRange, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)

        case .strikethrough:
            renderStrikethrough(node, nsRange: nsRange, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)

        case .inlineCode:
            renderInlineCode(nsRange: nsRange, into: attrStr, config: config)

        case .link(let destination):
            renderLink(
                node,
                destination: destination,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )

        case .image(let source):
            renderImage(
                node,
                source: source,
                nsRange: nsRange,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )

        case .softBreak, .lineBreak, .text:
            break // Use base attributes

        default:
            // Recurse for nested inline elements
            renderInlineChildren(of: node, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
        }
    }

    // MARK: - Bold

    private func renderStrong(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        // Apply bold trait to existing font
        if let existingFont = attrStr.attribute(.font, at: nsRange.location, effectiveRange: nil) as? PlatformFont {
            let boldFont = fontWithTrait(existingFont, trait: .traitBold)
            attrStr.addAttribute(.font, value: boldFont, range: nsRange)
        }

        // Hide ** or __ delimiters
        hideSurroundingDelimiters(
            node: node,
            nsRange: nsRange,
            delimiterLength: 2,
            attrStr: attrStr,
            sourceText: sourceText
        )

        // Recurse into children (e.g., bold+italic)
        renderInlineChildren(of: node, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
    }

    // MARK: - Italic

    private func renderEmphasis(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        if let existingFont = attrStr.attribute(.font, at: nsRange.location, effectiveRange: nil) as? PlatformFont {
            let italicFont = fontWithTrait(existingFont, trait: .traitItalic)
            attrStr.addAttribute(.font, value: italicFont, range: nsRange)
        }

        // Hide * or _ delimiters
        hideSurroundingDelimiters(
            node: node,
            nsRange: nsRange,
            delimiterLength: 1,
            attrStr: attrStr,
            sourceText: sourceText
        )

        renderInlineChildren(of: node, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
    }

    // MARK: - Strikethrough

    private func renderStrikethrough(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        attrStr.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: nsRange
        )

        // Hide ~~ delimiters
        hideSurroundingDelimiters(
            node: node,
            nsRange: nsRange,
            delimiterLength: 2,
            attrStr: attrStr,
            sourceText: sourceText
        )

        renderInlineChildren(of: node, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
    }

    // MARK: - Inline Code

    private func renderInlineCode(
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        config: RenderConfiguration
    ) {
        attrStr.addAttributes([
            .font: config.typeScale.code,
            .foregroundColor: config.colors.codeForeground,
            .backgroundColor: config.colors.codeBackground,
        ], range: nsRange)

        // Hide backtick delimiters
        let text = attrStr.string
        if nsRange.length >= 2,
           let swiftRange = Range(nsRange, in: text) {
            let content = text[swiftRange]
            // Find leading backticks
            let leadingTicks = content.prefix(while: { $0 == "`" })
            if !leadingTicks.isEmpty {
                let leadRange = NSRange(
                    location: nsRange.location,
                    length: leadingTicks.count
                )
                applySyntaxHiding(to: leadRange, in: attrStr)

                // Trailing backticks (same count as leading)
                let trailStart = nsRange.location + nsRange.length - leadingTicks.count
                if trailStart > leadRange.location + leadRange.length {
                    let trailRange = NSRange(
                        location: trailStart,
                        length: leadingTicks.count
                    )
                    applySyntaxHiding(to: trailRange, in: attrStr)
                }
            }
        }
    }

    // MARK: - Links

    private func renderLink(
        _ node: MarkdownNode,
        destination: String?,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        attrStr.addAttributes([
            .foregroundColor: config.colors.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: nsRange)

        if let dest = destination, let url = URL(string: dest) {
            attrStr.addAttribute(.link, value: url, range: nsRange)
        }

        // In rich view, show only the link text, hide the [](url) syntax
        // Find the text content range (inside [ ]) and hide the rest
        hideLinkSyntax(node: node, nsRange: nsRange, attrStr: attrStr, sourceText: sourceText)

        renderInlineChildren(of: node, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
    }

    private func hideLinkSyntax(
        node: MarkdownNode,
        nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let content = text[swiftRange]

        // Hide opening "["
        if content.hasPrefix("[") {
            let bracketRange = NSRange(location: nsRange.location, length: 1)
            applySyntaxHiding(to: bracketRange, in: attrStr)
        }

        // Find "](url)" and hide it
        if let closeBracket = content.range(of: "](") {
            let hideStart = closeBracket.lowerBound
            let hideNSStart = text.distance(from: text.startIndex, to: hideStart)
            let hideLength = text.distance(from: hideStart, to: swiftRange.upperBound)
            if hideLength > 0 {
                let hideRange = NSRange(location: hideNSStart, length: hideLength)
                applySyntaxHiding(to: hideRange, in: attrStr)
            }
        }
    }

    // MARK: - Images (FEAT-048)

    /// Default content width for image scaling when no container width is available.
    private static let defaultContentWidth: CGFloat = 600

    /// Renders an inline image in rich view per [A-053] and FEAT-048.
    ///
    /// - Resolves the image source against the document URL.
    /// - If the image is cached, inserts an `NSTextAttachment` on the first character
    ///   and hides the rest of the image syntax.
    /// - If not cached, kicks off async loading and shows a styled placeholder
    ///   with the alt text visible.
    /// - Broken images show alt text with warning styling per AC-3.
    private func renderImage(
        _ node: MarkdownNode,
        source: String?,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        let altText = extractAltText(from: node)

        // Resolve image URL
        let resolvedURL: URL?
        if let source, !source.isEmpty {
            resolvedURL = ImageLoader.resolveImageURL(source: source, documentURL: config.documentURL)
        } else {
            resolvedURL = nil
        }

        // Mark the entire range with image metadata attributes
        attrStr.addAttributes([
            .markdownNodeType: "image",
            .imageAltText: altText,
        ], range: nsRange)

        if let url = resolvedURL {
            attrStr.addAttribute(.imageSource, value: url.absoluteString, range: nsRange)
        }

        // Check cache for loaded image
        if let url = resolvedURL, let cached = imageLoader.cachedImage(for: url) {
            switch cached {
            case .success(let image, let imageSize):
                renderLoadedImage(
                    image: image,
                    imageSize: imageSize,
                    nsRange: nsRange,
                    into: attrStr,
                    config: config
                )
                return

            case .failure:
                renderBrokenImage(
                    altText: altText,
                    nsRange: nsRange,
                    into: attrStr,
                    sourceText: sourceText,
                    config: config
                )
                return
            }
        }

        // No URL or not yet cached — show placeholder and trigger async load
        if let url = resolvedURL {
            imageLoader.loadImageIfNeeded(from: url, maxWidth: Self.defaultContentWidth)
        }

        renderBrokenImage(
            altText: altText,
            nsRange: nsRange,
            into: attrStr,
            sourceText: sourceText,
            config: config
        )
    }

    /// Renders a successfully loaded image as an NSTextAttachment.
    private func renderLoadedImage(
        image: PlatformImage,
        imageSize: CGSize,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        config: RenderConfiguration
    ) {
        let displaySize = ImageLoader.displaySize(
            for: imageSize,
            maxWidth: Self.defaultContentWidth
        )

        let attachment = ImageTextAttachment(image: image, displaySize: displaySize)

        // Apply the attachment to the first character of the range
        if nsRange.length > 0 {
            attrStr.addAttribute(.attachment, value: attachment, range: NSRange(location: nsRange.location, length: 1))
        }

        // Hide the remaining characters of the image syntax
        if nsRange.length > 1 {
            let hideRange = NSRange(location: nsRange.location + 1, length: nsRange.length - 1)
            applySyntaxHiding(to: hideRange, in: attrStr)
        }
    }

    /// Renders a broken/missing image with alt text and placeholder styling per AC-3.
    private func renderBrokenImage(
        altText: String,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration
    ) {
        // Hide the full image syntax in rich view
        hideImageSyntax(nsRange: nsRange, attrStr: attrStr, sourceText: sourceText)

        // Find the alt text range within the image syntax and make it visible
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let content = text[swiftRange]

        // Alt text is between "![" and "]("
        if let altStart = content.range(of: "!["),
           let altEnd = content.range(of: "](") {
            let altContentStart = altStart.upperBound
            let altContentEnd = altEnd.lowerBound

            if altContentStart < altContentEnd {
                let altNSRange = NSRange(altContentStart..<altContentEnd, in: text)

                // Make the alt text visible with placeholder styling
                attrStr.addAttributes([
                    .font: config.typeScale.caption,
                    .foregroundColor: config.colors.blockquoteForeground,
                ], range: altNSRange)

                // Add italic trait for visual distinction
                if let font = attrStr.attribute(.font, at: altNSRange.location, effectiveRange: nil) as? PlatformFont {
                    let italicFont = fontWithTrait(font, trait: .traitItalic)
                    attrStr.addAttribute(.font, value: italicFont, range: altNSRange)
                }
            }
        }
    }

    /// Hides the image syntax characters in rich view: `![`, `](source)`.
    private func hideImageSyntax(
        nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let content = text[swiftRange]

        // Hide "!["
        if content.hasPrefix("![") {
            let hideRange = NSRange(location: nsRange.location, length: 2)
            applySyntaxHiding(to: hideRange, in: attrStr)
        }

        // Hide "](source)"
        if let closeBracket = content.range(of: "](") {
            let hideStart = closeBracket.lowerBound
            let hideNSStart = text.distance(from: text.startIndex, to: hideStart)
            let hideLength = text.distance(from: hideStart, to: swiftRange.upperBound)
            if hideLength > 0 {
                let hideRange = NSRange(location: hideNSStart, length: hideLength)
                applySyntaxHiding(to: hideRange, in: attrStr)
            }
        }
    }

    /// Extracts alt text from an image node's children.
    private func extractAltText(from node: MarkdownNode) -> String {
        node.children.compactMap { child -> String? in
            if case .text = child.type {
                return child.literalText
            }
            return nil
        }.joined()
    }

    // MARK: - Source View Rendering

    private func renderSourceView(
        into attrStr: NSMutableAttributedString,
        ast: MarkdownAST,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        // In source view, apply syntax coloring without hiding anything
        for block in ast.blocks {
            renderSourceBlock(
                block,
                into: attrStr,
                sourceText: sourceText,
                config: config,
                lineOffsets: lineOffsets
            )
        }
    }

    private func renderSourceBlock(
        _ node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        guard let range = node.range,
              let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) else {
            return
        }

        switch node.type {
        case .heading(let level):
            // Color heading markers and text
            let headingFont = config.typeScale.headingFont(level: level)
            attrStr.addAttributes([
                .font: headingFont,
                .foregroundColor: config.colors.heading,
            ], range: nsRange)

        case .codeBlock:
            attrStr.addAttributes([
                .font: config.typeScale.code,
                .foregroundColor: config.colors.codeForeground,
                .backgroundColor: config.colors.codeBackground,
            ], range: nsRange)

            // Apply syntax highlighting in source view per FEAT-006
            let language = node.codeBlockLanguage
            if let contentRange = codeContentRange(in: nsRange, sourceText: sourceText) {
                syntaxHighlighter.highlight(
                    in: attrStr,
                    contentRange: contentRange,
                    language: language,
                    colors: config.colors,
                    codeFont: config.typeScale.code
                )
            }

        case .blockQuote:
            attrStr.addAttribute(
                .foregroundColor,
                value: config.colors.blockquoteForeground,
                range: nsRange
            )

        case .table:
            // Source view: monospace font with code background, like code blocks
            attrStr.addAttributes([
                .font: config.typeScale.code,
                .foregroundColor: config.colors.codeForeground,
                .backgroundColor: config.colors.codeBackground,
            ], range: nsRange)

        default:
            break
        }

        // Color inline elements in source view
        for child in node.children {
            renderSourceInline(child, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
        }
    }

    private func renderSourceInline(
        _ node: MarkdownNode,
        into attrStr: NSMutableAttributedString,
        sourceText: String,
        config: RenderConfiguration,
        lineOffsets: [Int]
    ) {
        guard let range = node.range,
              let nsRange = nsRange(from: range, in: sourceText, lineOffsets: lineOffsets) else {
            return
        }

        switch node.type {
        case .strong:
            if let font = attrStr.attribute(.font, at: nsRange.location, effectiveRange: nil) as? PlatformFont {
                attrStr.addAttribute(.font, value: fontWithTrait(font, trait: .traitBold), range: nsRange)
            }

        case .emphasis:
            if let font = attrStr.attribute(.font, at: nsRange.location, effectiveRange: nil) as? PlatformFont {
                attrStr.addAttribute(.font, value: fontWithTrait(font, trait: .traitItalic), range: nsRange)
            }

        case .strikethrough:
            attrStr.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: nsRange
            )

        case .inlineCode:
            attrStr.addAttributes([
                .font: config.typeScale.code,
                .backgroundColor: config.colors.codeBackground,
            ], range: nsRange)

        case .link:
            attrStr.addAttribute(.foregroundColor, value: config.colors.link, range: nsRange)

        case .image:
            // Source view: color image syntax like links for visual identification
            attrStr.addAttribute(.foregroundColor, value: config.colors.link, range: nsRange)

        default:
            break
        }

        for child in node.children {
            renderSourceInline(child, into: attrStr, sourceText: sourceText, config: config, lineOffsets: lineOffsets)
        }
    }

    // MARK: - Syntax Hiding Utilities

    /// Applies zero-width font to hide syntax characters in rich view.
    private func applySyntaxHiding(to range: NSRange, in attrStr: NSMutableAttributedString) {
        guard range.length > 0, range.location + range.length <= attrStr.length else { return }

        // Use a very small font size to effectively hide the syntax characters.
        // We keep the characters in the text storage for round-trip fidelity per AC-2.
        #if canImport(UIKit)
        let hiddenFont = UIFont.systemFont(ofSize: 0.01)
        #elseif canImport(AppKit)
        let hiddenFont = NSFont.systemFont(ofSize: 0.01)
        #endif

        attrStr.addAttributes([
            .font: hiddenFont,
            .foregroundColor: PlatformColor.clear,
        ], range: range)
    }

    /// Hides a regex-matched prefix within the given range.
    private func hideSyntaxPrefix(
        pattern: String,
        in nsRange: NSRange,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        let text = attrStr.string
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let substring = String(text[swiftRange])

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: substring,
                range: NSRange(location: 0, length: substring.utf16.count)
              ) else {
            return
        }

        let hideRange = NSRange(
            location: nsRange.location + match.range.location,
            length: match.range.length
        )
        applySyntaxHiding(to: hideRange, in: attrStr)
    }

    /// Hides surrounding delimiters (e.g., **, *, ~~) for inline elements.
    private func hideSurroundingDelimiters(
        node: MarkdownNode,
        nsRange: NSRange,
        delimiterLength: Int,
        attrStr: NSMutableAttributedString,
        sourceText: String
    ) {
        guard nsRange.length > delimiterLength * 2 else { return }

        // Leading delimiter
        let leadRange = NSRange(location: nsRange.location, length: delimiterLength)
        applySyntaxHiding(to: leadRange, in: attrStr)

        // Trailing delimiter
        let trailRange = NSRange(
            location: nsRange.location + nsRange.length - delimiterLength,
            length: delimiterLength
        )
        applySyntaxHiding(to: trailRange, in: attrStr)
    }

    // MARK: - Spell Check Exclusion per [A-054]

    /// Applies spell check suppression attributes to ranges that should not
    /// be spell-checked: code blocks, code spans, URLs, and image paths.
    private func applySpellCheckExclusions(
        to attrStr: NSMutableAttributedString,
        ast: MarkdownAST,
        sourceText: String
    ) {
        let exclusions = SpellCheckExclusionCalculator.exclusionRanges(
            from: ast,
            sourceText: sourceText
        )

        for range in exclusions {
            guard range.location >= 0,
                  range.location + range.length <= attrStr.length else {
                continue
            }
            // Mark as excluded for custom attribute queries
            attrStr.addAttribute(.spellCheckExcluded, value: true, range: range)
            // BCP 47 "zxx" = no linguistic content — system spell checker skips these ranges
            attrStr.addAttribute(.spellCheckLanguage, value: "zxx", range: range)
        }
    }

    // MARK: - Font Utilities

    /// Returns a font with the specified symbolic trait added.
    private func fontWithTrait(_ font: PlatformFont, trait: FontTrait) -> PlatformFont {
        #if canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(UIFontDescriptor.SymbolicTraits(rawValue: trait.rawValue))
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: 0) // size 0 = keep original
        }
        return font
        #elseif canImport(AppKit)
        let manager = NSFontManager.shared
        switch trait {
        case .traitBold:
            return manager.convert(font, toHaveTrait: .boldFontMask)
        case .traitItalic:
            return manager.convert(font, toHaveTrait: .italicFontMask)
        }
        #endif
    }

    // MARK: - Range Conversion

    /// Converts a `SourceRange` (1-based line:column) to an `NSRange` using pre-computed line offsets.
    /// This is O(1) per call instead of O(lines).
    private func nsRange(from sourceRange: SourceRange, in text: String, lineOffsets: [Int]) -> NSRange? {
        guard !text.isEmpty else { return nil }

        let startLine = sourceRange.start.line - 1  // 0-based index into lineOffsets
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

    /// Converts a `SourceRange` (1-based line:column) to an `NSRange` in the source text.
    /// Used by tests and one-off conversions. For batch rendering, use the lineOffsets variant.
    func nsRange(from sourceRange: SourceRange, in text: String) -> NSRange? {
        let lineOffsets = computeLineOffsets(in: text)
        return nsRange(from: sourceRange, in: text, lineOffsets: lineOffsets)
    }
}

// MARK: - MarkdownNode Convenience

extension MarkdownNode {
    /// Extracts the language identifier from a code block node type.
    var codeBlockLanguage: String? {
        if case .codeBlock(let language) = type {
            return language
        }
        return nil
    }
}

// MARK: - Font Trait Abstraction

/// Cross-platform font trait abstraction.
enum FontTrait: UInt32 {
    #if canImport(UIKit)
    case traitBold = 0x00000002     // UIFontDescriptor.SymbolicTraits.traitBold
    case traitItalic = 0x00000001   // UIFontDescriptor.SymbolicTraits.traitItalic
    #elseif canImport(AppKit)
    case traitBold = 0
    case traitItalic = 1
    #endif
}

// MARK: - Accessibility Attribute Key

#if canImport(UIKit)
extension NSAttributedString.Key {
    /// Custom key for heading level accessibility.
    static let accessibilityTextHeadingLevel = NSAttributedString.Key("NSAccessibilityTextHeadingLevel")
}
#endif
