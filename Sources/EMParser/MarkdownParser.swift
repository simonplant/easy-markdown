import Foundation
import Markdown
import os

/// Thread-safe markdown parser wrapping Apple's `swift-markdown` per [A-003].
///
/// Produces a `MarkdownAST` from CommonMark + GFM markdown text.
/// Parsing is synchronous and stateless — safe to call from any thread or actor.
/// For background parsing, call from a `Task` with the document's `TextSnapshot`.
///
/// Malformed markdown always produces a partial AST; parsing never crashes.
public struct MarkdownParser: Sendable {

    private static let logger = Logger(
        subsystem: "com.easymarkdown.emparser",
        category: "parser"
    )

    /// Parse options controlling which GFM extensions are enabled.
    public let options: ParseOptions

    /// Creates a parser with the given options.
    /// - Parameter options: Parse options. Defaults to all GFM extensions enabled.
    public init(options: ParseOptions = .default) {
        self.options = options
    }

    /// Parses a markdown string into an AST.
    ///
    /// This method is synchronous and safe to call from any thread.
    /// For large documents, call from a background `Task`.
    ///
    /// - Parameter source: The markdown text to parse.
    /// - Returns: A `ParseResult` containing the AST and parse metadata.
    public func parse(_ source: String) -> ParseResult {
        let start = ContinuousClock.now

        let document = Markdown.Document(
            parsing: source,
            options: options.markupParsingOptions
        )

        let duration = ContinuousClock.now - start
        let durationSeconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18

        let ast = MarkdownAST(document: document)
        let lineCount = source.count(of: "\n") + (source.isEmpty ? 0 : 1)

        Self.logger.debug(
            "Parsed \(lineCount) lines in \(durationSeconds * 1000, format: .fixed(precision: 2))ms"
        )

        return ParseResult(
            ast: ast,
            sourceText: source,
            parseDuration: durationSeconds,
            lineCount: lineCount
        )
    }
}

// MARK: - Parse Options

/// Options controlling which markdown extensions are enabled during parsing.
public struct ParseOptions: Sendable {

    /// The underlying swift-markdown parsing options.
    let markupParsingOptions: Markdown.ParseOptions

    /// Default: CommonMark + all GFM extensions (tables, strikethrough, task lists, autolinks).
    public static let `default` = ParseOptions(
        markupParsingOptions: [
            .parseBlockDirectives,
            .parseMinimalDashes,
        ]
    )

    /// CommonMark only, no GFM extensions.
    public static let commonMarkOnly = ParseOptions(
        markupParsingOptions: []
    )

    public init(markupParsingOptions: Markdown.ParseOptions) {
        self.markupParsingOptions = markupParsingOptions
    }
}

// MARK: - String counting helper

private extension String {
    func count(of character: Character) -> Int {
        var count = 0
        for c in self where c == character {
            count += 1
        }
        return count
    }
}
