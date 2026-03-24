@preconcurrency import Markdown

/// Options for formatting an AST back to markdown text.
/// Wraps swift-markdown's `MarkupFormatter.Options` with sensible defaults.
public struct MarkdownFormatOptions: Sendable {

    /// The underlying swift-markdown formatting options.
    let markupFormattingOptions: MarkupFormatter.Options

    /// Default options that preserve original formatting as closely as possible.
    public static let `default` = MarkdownFormatOptions(
        markupFormattingOptions: .init()
    )

    /// Options configured for ordered list renumbering.
    public static let renumberOrderedLists = MarkdownFormatOptions(
        markupFormattingOptions: .init(orderedListNumerals: .incrementing(start: 1))
    )

    public init(markupFormattingOptions: MarkupFormatter.Options) {
        self.markupFormattingOptions = markupFormattingOptions
    }
}
