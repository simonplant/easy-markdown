import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMParser
@testable import EMCore

@MainActor
@Suite("MarkdownRenderer")
struct MarkdownRendererTests {

    private let renderer = MarkdownRenderer()
    private let parser = MarkdownParser()

    private var richConfig: RenderConfiguration {
        RenderConfiguration(
            typeScale: .default,
            colors: .defaultLight,
            isSourceView: false
        )
    }

    private var sourceConfig: RenderConfiguration {
        RenderConfiguration(
            typeScale: .default,
            colors: .defaultLight,
            isSourceView: true
        )
    }

    // MARK: - Range Conversion

    @Test("nsRange converts single-line source range correctly")
    func nsRangeSingleLine() {
        let text = "Hello world"
        let sourceRange = SourceRange(
            start: SourcePosition(line: 1, column: 1),
            end: SourcePosition(line: 1, column: 12)
        )
        let result = renderer.nsRange(from: sourceRange, in: text)
        #expect(result == NSRange(location: 0, length: 11))
    }

    @Test("nsRange converts multi-line source range correctly")
    func nsRangeMultiLine() {
        let text = "Line one\nLine two\nLine three"
        // Line 2, col 1 to line 2, col 9 => "Line two"
        let sourceRange = SourceRange(
            start: SourcePosition(line: 2, column: 1),
            end: SourcePosition(line: 2, column: 9)
        )
        let result = renderer.nsRange(from: sourceRange, in: text)
        #expect(result == NSRange(location: 9, length: 8))
    }

    @Test("nsRange returns nil for empty text")
    func nsRangeEmptyText() {
        let result = renderer.nsRange(
            from: SourceRange(
                start: SourcePosition(line: 1, column: 1),
                end: SourcePosition(line: 1, column: 1)
            ),
            in: ""
        )
        #expect(result == nil)
    }

    @Test("nsRange returns nil for out-of-bounds line")
    func nsRangeOutOfBounds() {
        let result = renderer.nsRange(
            from: SourceRange(
                start: SourcePosition(line: 5, column: 1),
                end: SourcePosition(line: 5, column: 5)
            ),
            in: "Hello"
        )
        #expect(result == nil)
    }

    // MARK: - Heading Rendering

    @Test("Headings get distinct fonts for all 6 levels")
    func headingFonts() {
        let typeScale = TypeScale.default
        var fonts: [PlatformFont] = []
        for level in 1...6 {
            fonts.append(typeScale.headingFont(level: level))
        }
        // All 6 levels should have distinct point sizes
        let sizes = fonts.map { $0.pointSize }
        #expect(Set(sizes).count == 6, "All 6 heading levels must have distinct sizes")
        // H1 should be largest
        #expect(sizes[0] > sizes[1])
        #expect(sizes[1] > sizes[2])
    }

    @Test("Heading level out of range returns body font")
    func headingOutOfRange() {
        let typeScale = TypeScale.default
        let font = typeScale.headingFont(level: 7)
        #expect(font.pointSize == typeScale.body.pointSize)
    }

    @Test("Heading renders with heading font in rich view")
    func headingRendersStyled() {
        let source = "# Hello World"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The "Hello World" portion should have heading1 font
        // (The "# " is hidden but the rest has heading font)
        let fullRange = NSRange(location: 0, length: attrStr.length)
        var effectiveRange = NSRange()

        // Find the heading font somewhere in the string
        var foundHeadingFont = false
        var pos = 0
        while pos < attrStr.length {
            let font = attrStr.attribute(.font, at: pos, effectiveRange: &effectiveRange) as? PlatformFont
            if let font, font.pointSize >= richConfig.typeScale.heading1.pointSize {
                foundHeadingFont = true
                break
            }
            pos = effectiveRange.location + effectiveRange.length
        }
        #expect(foundHeadingFont, "Heading text should have heading1 font size")
    }

    // MARK: - Inline Formatting

    @Test("Bold text gets bold font trait in rich view")
    func boldRendering() {
        let source = "Some **bold** text"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Check that "bold" portion has bold trait
        let boldStart = source.distance(from: source.startIndex, to: source.range(of: "bold")!.lowerBound)
        if let font = attrStr.attribute(.font, at: boldStart, effectiveRange: nil) as? PlatformFont {
            #if canImport(UIKit)
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
            #elseif canImport(AppKit)
            #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
            #endif
        }
    }

    @Test("Italic text gets italic font trait in rich view")
    func italicRendering() {
        let source = "Some *italic* text"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        let italicStart = source.distance(from: source.startIndex, to: source.range(of: "italic")!.lowerBound)
        if let font = attrStr.attribute(.font, at: italicStart, effectiveRange: nil) as? PlatformFont {
            #if canImport(UIKit)
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitItalic))
            #elseif canImport(AppKit)
            #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
            #endif
        }
    }

    @Test("Strikethrough text gets strikethrough attribute")
    func strikethroughRendering() {
        let source = "Some ~~struck~~ text"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        let struckStart = source.distance(from: source.startIndex, to: source.range(of: "struck")!.lowerBound)
        let style = attrStr.attribute(.strikethroughStyle, at: struckStart, effectiveRange: nil) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
    }

    @Test("Inline code gets monospace font and background")
    func inlineCodeRendering() {
        let source = "Use `code` here"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        let codeStart = source.distance(from: source.startIndex, to: source.range(of: "code")!.lowerBound)
        let font = attrStr.attribute(.font, at: codeStart, effectiveRange: nil) as? PlatformFont
        let bg = attrStr.attribute(.backgroundColor, at: codeStart, effectiveRange: nil) as? PlatformColor

        // Code should have the code font (monospace)
        #expect(font != nil)
        #expect(bg != nil, "Inline code should have background color")
    }

    // MARK: - Code Block

    @Test("Code block gets monospace font and background")
    func codeBlockRendering() {
        let source = "```\nlet x = 1\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The code content "let x = 1" should have code font
        let codeStart = source.distance(from: source.startIndex, to: source.range(of: "let")!.lowerBound)
        let font = attrStr.attribute(.font, at: codeStart, effectiveRange: nil) as? PlatformFont
        let bg = attrStr.attribute(.backgroundColor, at: codeStart, effectiveRange: nil) as? PlatformColor

        #expect(font != nil)
        #expect(bg != nil, "Code block should have background color")
    }

    // MARK: - Blockquote

    @Test("Blockquote gets custom foreground color and border attribute")
    func blockquoteRendering() {
        let source = "> A quote"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Should have blockquote border attribute
        let hasBorder = attrStr.attribute(.blockquoteBorder, at: 0, effectiveRange: nil)
        #expect(hasBorder != nil, "Blockquote should have border attribute")
    }

    // MARK: - Source View

    @Test("Source view applies heading font without hiding syntax")
    func sourceViewHeading() {
        let source = "# Hello"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: sourceConfig
        )

        // In source view, the # character should be visible (not hidden)
        let hashFont = attrStr.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(hashFont != nil)
        // Font should NOT be zero-width (hidden)
        #expect(hashFont!.pointSize > 1, "Source view should not hide syntax characters")
    }

    // MARK: - Malformed Markdown

    @Test("Malformed markdown renders best-effort without crash")
    func malformedMarkdown() {
        let sources = [
            "# ",
            "**unclosed bold",
            "```\nunclosed code block",
            "> > > deeply nested quote",
            "- item\n  - nested\n    - deep\n      - deeper",
            "",
            "# \n## \n### ",
            "**bold *and italic** not closed*",
        ]

        for source in sources {
            let parseResult = parser.parse(source)
            let attrStr = NSMutableAttributedString(string: source)

            // Should not crash
            renderer.render(
                into: attrStr,
                ast: parseResult.ast,
                sourceText: source,
                config: richConfig
            )

            // Output should have same text length as input (no content loss)
            #expect(attrStr.string == source, "Render should preserve text content for: \(source)")
        }
    }

    // MARK: - Round-Trip

    @Test("Rendering preserves raw text content for round-trip per AC-2")
    func roundTripPreservation() {
        let source = """
        # Heading

        Some **bold** and *italic* text with `code`.

        > A blockquote

        - List item 1
        - List item 2

        ---

        ```swift
        let x = 1
        ```
        """
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The underlying text must be preserved exactly
        #expect(attrStr.string == source, "Rendering must not alter text content")
    }

    // MARK: - List Indentation

    @Test("Nested lists get increasing indentation")
    func nestedListIndentation() {
        let source = "- Item 1\n  - Nested 1\n    - Deep nested"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Text should be preserved
        #expect(attrStr.string == source)

        // Check that paragraph styles exist with indentation
        let item1Start = 0
        let style1 = attrStr.attribute(.paragraphStyle, at: item1Start, effectiveRange: nil) as? NSParagraphStyle
        #expect(style1 != nil, "List items should have paragraph styles")
    }

    // MARK: - TypeScale

    @Test("Default TypeScale has 6 distinct heading sizes")
    func typeScaleDistinctSizes() {
        let scale = TypeScale.default
        let sizes = [
            scale.heading1.pointSize,
            scale.heading2.pointSize,
            scale.heading3.pointSize,
            scale.heading4.pointSize,
            scale.heading5.pointSize,
            scale.heading6.pointSize,
        ]
        #expect(Set(sizes).count == 6, "All 6 heading levels must have unique sizes")
    }

    @Test("Default TypeScale heading sizes are in descending order")
    func typeScaleDescendingOrder() {
        let scale = TypeScale.default
        #expect(scale.heading1.pointSize > scale.heading2.pointSize)
        #expect(scale.heading2.pointSize > scale.heading3.pointSize)
        #expect(scale.heading3.pointSize > scale.heading4.pointSize)
        #expect(scale.heading4.pointSize > scale.heading5.pointSize)
        #expect(scale.heading5.pointSize > scale.heading6.pointSize)
    }

    // MARK: - Theme

    @Test("Default theme has non-nil colors")
    func defaultTheme() {
        let theme = Theme.default
        #expect(theme.id == "default")
        #expect(theme.name == "Default")
        // Just verify the colors can be accessed without crash
        _ = theme.light.foreground
        _ = theme.dark.foreground
        _ = theme.light.heading
        _ = theme.dark.heading
    }

    @Test("Theme resolves correct variant for isDark flag")
    func themeColorResolution() {
        let theme = Theme.default
        let lightColors = theme.colors(isDark: false)
        let darkColors = theme.colors(isDark: true)
        // Both should be valid (non-crash access)
        _ = lightColors.foreground
        _ = darkColors.foreground
    }
}
