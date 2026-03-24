import Foundation
@preconcurrency import Markdown

/// The parsed AST representation of a markdown document per [A-003].
///
/// Wraps Apple's `swift-markdown` `Document` and provides a clean interface
/// for the rest of the app. The underlying swift-markdown types are not exposed.
///
/// `MarkdownAST` is `Sendable` — the node tree is a value type snapshot
/// safe to pass between actors. The backing swift-markdown `Document` is
/// retained internally for round-trip formatting.
public struct MarkdownAST: Sendable {

    /// The root node of the AST.
    public let root: MarkdownNode

    /// The raw swift-markdown document, retained for round-trip formatting.
    let markupDocument: Markdown.Document

    init(document: Markdown.Document) {
        self.markupDocument = document
        self.root = MarkdownNode.from(document)
    }

    // MARK: - Convenience Queries

    /// All block-level children of the document root.
    public var blocks: [MarkdownNode] {
        root.children
    }

    /// Finds all nodes of the given type in a depth-first traversal.
    public func nodes(ofType type: MarkdownNodeType) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        collectNodes(ofType: type, in: root, into: &result)
        return result
    }

    /// Finds the deepest node whose source range contains the given position.
    public func node(at position: SourcePosition) -> MarkdownNode? {
        findNode(at: position, in: root)
    }

    // MARK: - Round-Trip

    /// Converts the AST back to a markdown string.
    /// Uses swift-markdown's `MarkupFormatter` for faithful reproduction.
    public func format(options: MarkdownFormatOptions = .default) -> String {
        var formatter = MarkupFormatter(
            formattingOptions: options.markupFormattingOptions
        )
        formatter.visit(markupDocument)
        return formatter.result
    }

    // MARK: - Private Helpers

    private func collectNodes(
        ofType type: MarkdownNodeType,
        in node: MarkdownNode,
        into result: inout [MarkdownNode]
    ) {
        if node.type == type {
            result.append(node)
        }
        for child in node.children {
            collectNodes(ofType: type, in: child, into: &result)
        }
    }

    private func findNode(at position: SourcePosition, in node: MarkdownNode) -> MarkdownNode? {
        guard let range = node.range,
              position >= range.start && position <= range.end else {
            return nil
        }
        // Try to find a more specific child node at this position.
        for child in node.children {
            if let found = findNode(at: position, in: child) {
                return found
            }
        }
        return node
    }
}
