import Foundation
import Markdown

/// Task list checkbox state for list items.
public enum Checkbox: Sendable, Equatable {
    case checked
    case unchecked
}

/// The type of a markdown AST node.
/// Maps to CommonMark + GFM element types per [D-MD-1].
public enum MarkdownNodeType: Sendable, Equatable {
    // Block elements
    case document
    case heading(level: Int)
    case paragraph
    case blockQuote
    case orderedList
    case unorderedList
    case listItem(checkbox: Checkbox?)
    case codeBlock(language: String?)
    case htmlBlock
    case thematicBreak
    case table
    case tableHead
    case tableBody
    case tableRow
    case tableCell

    // Inline elements
    case text
    case emphasis
    case strong
    case strikethrough
    case inlineCode
    case link(destination: String?)
    case image(source: String?)
    case lineBreak
    case softBreak
    case inlineHTML
}

/// A wrapper around a swift-markdown `Markup` node providing a stable,
/// clean interface for the rest of the app per [A-003].
///
/// `MarkdownNode` exposes the node type, source range, raw text content,
/// and children without leaking the underlying swift-markdown types.
public struct MarkdownNode: Sendable {
    /// The type of this node.
    public let type: MarkdownNodeType

    /// The source range of this node within the original document.
    /// `nil` if the node has no source position (e.g., programmatically created).
    public let range: SourceRange?

    /// The child nodes of this element.
    public let children: [MarkdownNode]

    /// The literal text content for leaf nodes (text, code spans, code blocks).
    /// `nil` for non-leaf or structural nodes.
    public let literalText: String?

    public init(
        type: MarkdownNodeType,
        range: SourceRange?,
        children: [MarkdownNode] = [],
        literalText: String? = nil
    ) {
        self.type = type
        self.range = range
        self.children = children
        self.literalText = literalText
    }
}

// MARK: - Conversion from swift-markdown Markup

extension MarkdownNode {
    /// Creates a `MarkdownNode` tree from a swift-markdown `Markup` node.
    static func from(_ markup: any Markup) -> MarkdownNode {
        let type = nodeType(for: markup)
        let range = sourceRange(for: markup)
        let children = markup.children.map { MarkdownNode.from($0) }
        let literal = literalText(for: markup)

        return MarkdownNode(
            type: type,
            range: range,
            children: children,
            literalText: literal
        )
    }

    private static func nodeType(for markup: any Markup) -> MarkdownNodeType {
        switch markup {
        case let heading as Markdown.Heading:
            return .heading(level: heading.level)
        case is Markdown.Paragraph:
            return .paragraph
        case is Markdown.BlockQuote:
            return .blockQuote
        case is Markdown.OrderedList:
            return .orderedList
        case is Markdown.UnorderedList:
            return .unorderedList
        case let listItem as Markdown.ListItem:
            let checkbox: Checkbox? = listItem.checkbox.map { $0 == .checked ? .checked : .unchecked }
            return .listItem(checkbox: checkbox)
        case let codeBlock as Markdown.CodeBlock:
            let lang = codeBlock.language.flatMap { $0.isEmpty ? nil : $0 }
            return .codeBlock(language: lang)
        case is Markdown.HTMLBlock:
            return .htmlBlock
        case is Markdown.ThematicBreak:
            return .thematicBreak
        case is Markdown.Table:
            return .table
        case is Markdown.Table.Head:
            return .tableHead
        case is Markdown.Table.Body:
            return .tableBody
        case is Markdown.Table.Row:
            return .tableRow
        case is Markdown.Table.Cell:
            return .tableCell
        case is Markdown.Text:
            return .text
        case is Markdown.Emphasis:
            return .emphasis
        case is Markdown.Strong:
            return .strong
        case is Markdown.Strikethrough:
            return .strikethrough
        case is Markdown.InlineCode:
            return .inlineCode
        case let link as Markdown.Link:
            return .link(destination: link.destination)
        case let image as Markdown.Image:
            return .image(source: image.source)
        case is Markdown.InlineHTML:
            return .inlineHTML
        case is Markdown.LineBreak:
            return .lineBreak
        case is Markdown.SoftBreak:
            return .softBreak
        case is Markdown.Document:
            return .document
        default:
            // Treat unknown node types as paragraphs for forward compatibility.
            return .paragraph
        }
    }

    private static func sourceRange(for markup: any Markup) -> SourceRange? {
        guard let range = markup.range else { return nil }
        return SourceRange(
            start: SourcePosition(
                line: range.lowerBound.line,
                column: range.lowerBound.column
            ),
            end: SourcePosition(
                line: range.upperBound.line,
                column: range.upperBound.column
            )
        )
    }

    private static func literalText(for markup: any Markup) -> String? {
        switch markup {
        case let text as Markdown.Text:
            return text.string
        case let code as Markdown.InlineCode:
            return code.code
        case let codeBlock as Markdown.CodeBlock:
            return codeBlock.code
        case let html as Markdown.HTMLBlock:
            return html.rawHTML
        case let inlineHTML as Markdown.InlineHTML:
            return inlineHTML.rawHTML
        default:
            return nil
        }
    }
}
