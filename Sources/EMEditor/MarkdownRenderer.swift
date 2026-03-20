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

    public init(typeScale: TypeScale, colors: ThemeColors, isSourceView: Bool) {
        self.typeScale = typeScale
        self.colors = colors
        self.isSourceView = isSourceView
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        // More spacing around higher-level headings
        paragraphStyle.paragraphSpacingBefore = level <= 2 ? 16 : 12
        paragraphStyle.paragraphSpacing = level <= 2 ? 12 : 8

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

        let indent = CGFloat(indentLevel) * 24.0 + 24.0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent - 18.0
        paragraphStyle.paragraphSpacing = 4
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
        let indent: CGFloat = 16.0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = 4

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

    private func renderCodeBlock(
        _ node: MarkdownNode,
        nsRange: NSRange,
        into attrStr: NSMutableAttributedString,
        config: RenderConfiguration
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.paragraphSpacingBefore = 8

        attrStr.addAttributes([
            .font: config.typeScale.code,
            .foregroundColor: config.colors.codeForeground,
            .backgroundColor: config.colors.codeBackground,
            .paragraphStyle: paragraphStyle,
            .markdownNodeType: "codeBlock",
        ], range: nsRange)

        // Hide fence markers (``` lines) in rich view
        hideFenceMarkers(in: nsRange, attrStr: attrStr, sourceText: attrStr.string)
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacingBefore = 12
        paragraphStyle.paragraphSpacing = 12

        attrStr.addAttributes([
            .foregroundColor: config.colors.thematicBreak,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: config.colors.thematicBreak,
            .paragraphStyle: paragraphStyle,
            .thematicBreak: true,
            .markdownNodeType: "thematicBreak",
        ], range: nsRange)
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

        case .blockQuote:
            attrStr.addAttribute(
                .foregroundColor,
                value: config.colors.blockquoteForeground,
                range: nsRange
            )

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
