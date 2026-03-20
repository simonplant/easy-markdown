import Foundation

/// The result of parsing a markdown document.
/// Contains the AST and metadata about the parse operation.
public struct ParseResult: Sendable {
    /// The parsed AST. Always present — malformed input produces a partial AST.
    public let ast: MarkdownAST

    /// The source text that was parsed (retained for round-trip comparison).
    public let sourceText: String

    /// Time taken to parse, in seconds.
    public let parseDuration: TimeInterval

    /// The number of lines in the source text.
    public let lineCount: Int
}
