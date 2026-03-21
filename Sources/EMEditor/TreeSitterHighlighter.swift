/// Tree-sitter-based syntax highlighting prototype for SPIKE-007 per [A-005].
///
/// Evaluates `swift-tree-sitter` package for syntax highlighting of fenced code blocks.
/// Parses source code into a concrete syntax tree, runs highlight queries, and maps
/// tree-sitter capture names to `SyntaxTokenType` for theme color application.
///
/// Supports Swift, Python, and JavaScript for this spike. If tree-sitter is adopted,
/// this replaces the regex-based `SyntaxHighlighter`.

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import SwiftTreeSitter
import TreeSitterSwift
import TreeSitterPython
import TreeSitterJavaScript

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "tree-sitter")

// MARK: - Tree-Sitter Highlighter

/// Syntax highlighter backed by tree-sitter parsers with highlight queries.
///
/// Thread-safety: Each `TreeSitterHighlighter` instance owns its own `Parser`.
/// Call from `@MainActor` context (same as `SyntaxHighlighter`).
@MainActor
struct TreeSitterHighlighter {

    /// Cached language configurations, keyed by language name.
    private static var languageConfigs: [String: LanguageConfiguration] = [:]

    /// Cached parsers per language (parser language must be set before use).
    private static var parsers: [String: Parser] = [:]

    // MARK: - Public API

    /// Applies tree-sitter-based syntax highlighting to a code block's content range.
    ///
    /// Same signature as `SyntaxHighlighter.highlight` for drop-in replacement.
    func highlight(
        in attrStr: NSMutableAttributedString,
        contentRange: NSRange,
        language: String?,
        colors: ThemeColors,
        codeFont: PlatformFont
    ) {
        guard contentRange.length > 0 else { return }

        let normalizedLang = normalizeLanguage(language)
        guard let lang = normalizedLang else { return }

        guard let config = languageConfig(for: lang) else {
            logger.debug("No tree-sitter config for language: \(lang)")
            return
        }

        let text = attrStr.string
        guard let swiftRange = Range(contentRange, in: text) else { return }
        let codeText = String(text[swiftRange])

        let tokens = tokenize(codeText, language: lang, config: config)

        for token in tokens {
            let absoluteRange = NSRange(
                location: contentRange.location + token.range.location,
                length: token.range.length
            )
            guard absoluteRange.location + absoluteRange.length <= attrStr.length else { continue }

            let color = color(for: token.type, colors: colors)
            attrStr.addAttribute(.foregroundColor, value: color, range: absoluteRange)
        }
    }

    // MARK: - Tokenization

    /// Parses code with tree-sitter and returns semantic tokens.
    func tokenize(_ code: String, language: String, config: LanguageConfiguration) -> [SyntaxToken] {
        let parser: Parser
        if let cached = Self.parsers[language] {
            parser = cached
        } else {
            parser = Parser()
            do {
                try parser.setLanguage(config.language)
                Self.parsers[language] = parser
            } catch {
                logger.warning("Failed to set tree-sitter language \(language): \(error)")
                return []
            }
        }

        guard let tree = parser.parse(code) else {
            logger.warning("Tree-sitter parse failed for \(language)")
            return []
        }

        guard let highlightsQuery = config.queries[.highlights] else {
            logger.debug("No highlights query for \(language)")
            return []
        }

        let cursor = highlightsQuery.execute(in: tree)
        let provider = code.predicateTextProvider
        let highlights = cursor.resolve(with: provider).highlights()

        var tokens: [SyntaxToken] = []

        for highlight in highlights {
            guard let tokenType = mapCaptureToTokenType(highlight.name) else { continue }

            // Convert the range — tree-sitter uses byte ranges, SwiftTreeSitter
            // provides NSRange in UTF-16 via .range
            let range = highlight.range
            guard range.length > 0 else { continue }

            tokens.append(SyntaxToken(range: range, type: tokenType))
        }

        return tokens
    }

    // MARK: - Language Configuration

    /// Returns a cached or newly created LanguageConfiguration for a language.
    func languageConfig(for language: String) -> LanguageConfiguration? {
        if let cached = Self.languageConfigs[language] {
            return cached
        }

        let config: LanguageConfiguration?
        do {
            switch language {
            case "swift":
                config = try LanguageConfiguration(
                    tree_sitter_swift(),
                    name: "Swift"
                )
            case "python":
                config = try LanguageConfiguration(
                    tree_sitter_python(),
                    name: "Python"
                )
            case "javascript":
                config = try LanguageConfiguration(
                    tree_sitter_javascript(),
                    name: "JavaScript"
                )
            default:
                return nil
            }
        } catch {
            logger.warning("Failed to create tree-sitter config for \(language): \(error)")
            return nil
        }

        if let config {
            Self.languageConfigs[language] = config
        }
        return config
    }

    // MARK: - Capture Name Mapping

    /// Maps tree-sitter highlight capture names to our `SyntaxTokenType`.
    ///
    /// Tree-sitter highlights.scm files use hierarchical names like "keyword.function",
    /// "string.special", etc. We map these to our 6 semantic categories.
    private func mapCaptureToTokenType(_ name: String) -> SyntaxTokenType? {
        // Handle hierarchical names: "keyword.function" → check "keyword" prefix
        let base = name.split(separator: ".").first.map(String.init) ?? name

        switch base {
        case "keyword", "include", "repeat", "conditional", "exception":
            return .keyword
        case "string", "character":
            return .string
        case "comment":
            return .comment
        case "number", "float", "boolean":
            return .number
        case "type", "storageclass", "structure":
            return .type
        case "function", "method", "constructor":
            return .function
        case "variable":
            // "variable.builtin" → type, plain "variable" → skip (too noisy)
            if name.contains("builtin") { return .type }
            return nil
        case "operator", "punctuation", "delimiter":
            return nil
        case "constant":
            if name.contains("builtin") { return .type }
            return .number
        case "attribute":
            return .keyword
        case "label", "namespace", "module":
            return .type
        case "property", "field":
            return nil
        case "parameter":
            return nil
        default:
            return nil
        }
    }

    // MARK: - Language Normalization

    /// Maps language aliases to tree-sitter supported identifiers.
    private func normalizeLanguage(_ language: String?) -> String? {
        guard let lang = language?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if lang.isEmpty { return nil }

        switch lang {
        case "swift":
            return "swift"
        case "python", "py", "python3":
            return "python"
        case "javascript", "js":
            return "javascript"
        default:
            return nil
        }
    }

    // MARK: - Color Mapping

    private func color(for tokenType: SyntaxTokenType, colors: ThemeColors) -> PlatformColor {
        switch tokenType {
        case .keyword:  return colors.syntaxKeyword
        case .string:   return colors.syntaxString
        case .comment:  return colors.syntaxComment
        case .number:   return colors.syntaxNumber
        case .type:     return colors.syntaxType
        case .function: return colors.syntaxFunction
        }
    }

    // MARK: - Benchmarking (SPIKE-007)

    /// Benchmarks parse performance for a given code string.
    ///
    /// - Parameters:
    ///   - code: The source code to parse.
    ///   - language: The language identifier.
    ///   - iterations: Number of iterations to average over.
    /// - Returns: A `BenchmarkResult` with timing data, or nil if the language is unsupported.
    func benchmark(
        code: String,
        language: String,
        iterations: Int = 10
    ) -> BenchmarkResult? {
        guard let config = languageConfig(for: language) else { return nil }

        let parser = Parser()
        do {
            try parser.setLanguage(config.language)
        } catch {
            return nil
        }

        // Cold parse (first run)
        let coldStart = CFAbsoluteTimeGetCurrent()
        let tree = parser.parse(code)
        let coldParseMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000

        guard tree != nil else { return nil }

        // Warm parse (average of N iterations)
        var warmTotalMs: Double = 0
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            _ = parser.parse(code)
            warmTotalMs += (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
        let warmAvgMs = warmTotalMs / Double(iterations)

        // Highlight query timing
        let highlightsQuery = config.queries[.highlights]
        var highlightMs: Double = 0
        var tokenCount: Int = 0
        if let query = highlightsQuery, let tree = parser.parse(code) {
            let hlStart = CFAbsoluteTimeGetCurrent()
            let cursor = query.execute(in: tree)
            let highlights = cursor.resolve(with: code.predicateTextProvider).highlights()
            tokenCount = Array(highlights).count
            highlightMs = (CFAbsoluteTimeGetCurrent() - hlStart) * 1000
        }

        return BenchmarkResult(
            language: language,
            codeLines: code.components(separatedBy: "\n").count,
            coldParseMs: coldParseMs,
            warmParseAvgMs: warmAvgMs,
            highlightQueryMs: highlightMs,
            tokenCount: tokenCount,
            iterations: iterations
        )
    }
}

// MARK: - Benchmark Result

/// Performance measurements from a tree-sitter benchmark run.
struct BenchmarkResult {
    let language: String
    let codeLines: Int
    let coldParseMs: Double
    let warmParseAvgMs: Double
    let highlightQueryMs: Double
    let tokenCount: Int
    let iterations: Int

    var totalHighlightMs: Double {
        warmParseAvgMs + highlightQueryMs
    }
}

// MARK: - String Extension for Predicate Text Provider

extension String {
    /// Provides text content for tree-sitter predicate resolution.
    var predicateTextProvider: SwiftTreeSitter.Predicate.TextProvider {
        return { range, _ in
            guard let swiftRange = Range(range, in: self) else { return nil }
            return String(self[swiftRange])
        }
    }
}
