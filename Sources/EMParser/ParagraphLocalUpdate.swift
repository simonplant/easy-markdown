/// SPIKE-003: Lightweight per-paragraph local attribute update prototype per [A-017].
///
/// Validates the strategy for <16ms keystroke response between full re-parses.
/// Uses regex-based syntax detection to identify markdown inline elements and
/// leaf block prefixes within a single paragraph, without producing a full AST.
///
/// This is the "local update" half of the debounce + local-update strategy.

import Foundation
import os

// MARK: - Local Update Result

/// The result of a lightweight per-paragraph syntax scan.
/// Maps character ranges to detected markdown syntax types.
public struct ParagraphSyntaxResult: Sendable {
    /// Detected syntax spans within the paragraph.
    public let spans: [SyntaxSpan]
    /// Time taken for the local update, in seconds.
    public let duration: TimeInterval
    /// Whether the update completed within the <16ms keystroke budget.
    public var meetsTarget: Bool { duration * 1000 < 16.0 }
}

/// A detected syntax span within a paragraph.
public struct SyntaxSpan: Sendable, Equatable {
    /// The range within the paragraph string.
    public let range: Range<String.Index>
    /// The detected syntax type.
    public let type: InlineSyntaxType
}

/// Markdown syntax types detectable via lightweight regex scanning.
public enum InlineSyntaxType: Sendable, Equatable {
    case heading(level: Int)
    case bold
    case italic
    case boldItalic
    case codeSpan
    case strikethrough
    case link
    case image
    case listMarker
    case taskListMarker(checked: Bool)
    case blockquoteMarker
}

// MARK: - Paragraph Scanner

/// Lightweight paragraph-level syntax scanner for local attribute updates.
///
/// Scans a single paragraph for inline markdown syntax using compiled regex
/// patterns. Designed to run on the main thread within the <16ms keystroke
/// budget per [A-017] step 1.
///
/// This does NOT produce a full AST — it provides just enough information
/// to keep visual styling correct between full re-parses.
public struct ParagraphLocalUpdater: Sendable {

    private static let logger = Logger(
        subsystem: "com.easymarkdown.spike003",
        category: "local-update"
    )

    public init() {}

    /// Scans a paragraph for inline syntax spans.
    ///
    /// - Parameter paragraph: A single paragraph of markdown text.
    /// - Returns: A `ParagraphSyntaxResult` with detected spans and timing.
    public func scan(_ paragraph: String) -> ParagraphSyntaxResult {
        let start = ContinuousClock.now

        var spans: [SyntaxSpan] = []

        // Leaf block prefix detection (heading, list marker, blockquote)
        detectBlockPrefix(in: paragraph, spans: &spans)

        // Inline element detection
        detectCodeSpans(in: paragraph, spans: &spans)
        detectBoldItalic(in: paragraph, spans: &spans)
        detectStrikethrough(in: paragraph, spans: &spans)
        detectLinks(in: paragraph, spans: &spans)
        detectImages(in: paragraph, spans: &spans)

        let duration = ContinuousClock.now - start
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18

        return ParagraphSyntaxResult(spans: spans, duration: seconds)
    }

    // MARK: - Block Prefix Detection

    private func detectBlockPrefix(in text: String, spans: inout [SyntaxSpan]) {
        // ATX heading: # through ######
        if let match = text.prefixMatch(of: /^(#{1,6})\s/) {
            let level = match.output.1.count
            spans.append(SyntaxSpan(
                range: match.range,
                type: .heading(level: level)
            ))
        }

        // Unordered list marker: -, *, +
        if let match = text.prefixMatch(of: /^(\s*[-*+])\s/) {
            spans.append(SyntaxSpan(
                range: match.range,
                type: .listMarker
            ))
        }

        // Ordered list marker: 1. 2. etc.
        if let match = text.prefixMatch(of: /^(\s*\d+[.)]) /) {
            spans.append(SyntaxSpan(
                range: match.range,
                type: .listMarker
            ))
        }

        // Task list marker: - [x] or - [ ]
        if let match = text.prefixMatch(of: /^(\s*[-*+]\s+\[([ xX])\])\s/) {
            let checked = match.output.2 != " "
            spans.append(SyntaxSpan(
                range: match.range,
                type: .taskListMarker(checked: checked)
            ))
        }

        // Blockquote marker: >
        if let match = text.prefixMatch(of: /^(>\s?)+/) {
            spans.append(SyntaxSpan(
                range: match.range,
                type: .blockquoteMarker
            ))
        }
    }

    // MARK: - Inline Detection

    private func detectCodeSpans(in text: String, spans: inout [SyntaxSpan]) {
        // Backtick code spans: `code` or ``code``
        let pattern = /`{1,2}[^`]+`{1,2}/
        for match in text.matches(of: pattern) {
            spans.append(SyntaxSpan(range: match.range, type: .codeSpan))
        }
    }

    private func detectBoldItalic(in text: String, spans: inout [SyntaxSpan]) {
        // Bold+italic: ***text*** or ___text___
        let boldItalicPattern = /(\*{3}|_{3})(?!\s)(.+?)(?<!\s)\1/
        for match in text.matches(of: boldItalicPattern) {
            spans.append(SyntaxSpan(range: match.range, type: .boldItalic))
        }

        // Bold: **text** or __text__
        let boldPattern = /(\*{2}|_{2})(?!\s)(.+?)(?<!\s)\1/
        for match in text.matches(of: boldPattern) {
            // Skip if already covered by bold+italic
            let alreadyCovered = spans.contains { $0.range == match.range && $0.type == .boldItalic }
            if !alreadyCovered {
                spans.append(SyntaxSpan(range: match.range, type: .bold))
            }
        }

        // Italic: *text* or _text_
        let italicPattern = /(?<!\*)\*(?!\s)([^*]+?)(?<!\s)\*(?!\*)|(?<!_)_(?!\s)([^_]+?)(?<!\s)_(?!_)/
        for match in text.matches(of: italicPattern) {
            let alreadyCovered = spans.contains { span in
                span.range.overlaps(match.range) && (span.type == .bold || span.type == .boldItalic)
            }
            if !alreadyCovered {
                spans.append(SyntaxSpan(range: match.range, type: .italic))
            }
        }
    }

    private func detectStrikethrough(in text: String, spans: inout [SyntaxSpan]) {
        let pattern = /~~(?!\s)(.+?)(?<!\s)~~/
        for match in text.matches(of: pattern) {
            spans.append(SyntaxSpan(range: match.range, type: .strikethrough))
        }
    }

    private func detectLinks(in text: String, spans: inout [SyntaxSpan]) {
        // Inline links: [text](url)
        let pattern = /(?<!!)\[([^\]]+)\]\(([^)]+)\)/
        for match in text.matches(of: pattern) {
            spans.append(SyntaxSpan(range: match.range, type: .link))
        }
    }

    private func detectImages(in text: String, spans: inout [SyntaxSpan]) {
        // Images: ![alt](url)
        let pattern = /!\[([^\]]*)\]\(([^)]+)\)/
        for match in text.matches(of: pattern) {
            spans.append(SyntaxSpan(range: match.range, type: .image))
        }
    }
}

// MARK: - Local Update Benchmark

/// Benchmarks the per-paragraph local update strategy for SPIKE-003.
///
/// Runs the `ParagraphLocalUpdater` across representative paragraphs to validate
/// that local updates complete within the <16ms keystroke budget.
public enum ParagraphLocalUpdateBenchmark {

    /// Representative paragraphs for benchmarking (covers all inline types).
    private static let sampleParagraphs: [String] = [
        "# Heading Level 1",
        "## Heading with **bold** and *italic*",
        "This is a paragraph with **bold text**, *italic text*, `inline code`, and [a link](https://example.com). It also has ~~strikethrough~~ and ***bold italic*** text.",
        "- List item with `code` and **bold** formatting",
        "1. Ordered item with *emphasis* and [link](https://example.com)",
        "- [x] Completed task with **bold** description",
        "- [ ] Pending task with `code` reference",
        "> Blockquote with **bold** and *italic* text",
        "> > Nested blockquote with `code span`",
        "A very long paragraph that simulates real-world content. It contains **multiple bold sections**, *several italic phrases*, `inline code blocks`, [links to various places](https://example.com/page), ~~crossed out text~~, and ***bold italic combinations***. The paragraph continues with more text to ensure realistic length. Here is an image reference: ![alt text](https://example.com/image.png). And more text follows with additional **formatting** and *styling* that exercises the scanner.",
        "Simple paragraph with no formatting at all, just plain text that the scanner should process quickly without finding any spans.",
    ]

    /// Runs the local update benchmark across representative paragraphs.
    ///
    /// - Returns: Array of `ParagraphSyntaxResult`, one per sample paragraph.
    public static func run() -> [ParagraphSyntaxResult] {
        let updater = ParagraphLocalUpdater()
        let logger = Logger(subsystem: "com.easymarkdown.spike003", category: "local-benchmark")

        var results: [ParagraphSyntaxResult] = []
        for (index, paragraph) in sampleParagraphs.enumerated() {
            let result = updater.scan(paragraph)
            logger.info(
                "Paragraph \(index): \(result.spans.count) spans in \(result.duration * 1_000_000, format: .fixed(precision: 1))µs (target <16ms: \(result.meetsTarget ? "PASS" : "FAIL"))"
            )
            results.append(result)
        }

        return results
    }
}
