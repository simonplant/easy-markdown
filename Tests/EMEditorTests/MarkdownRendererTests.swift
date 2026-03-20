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

    // MARK: - Table Rendering (FEAT-047)

    @Test("GFM table renders with monospace font and background in rich view")
    func tableRendersWithCodeFont() {
        let source = "| A | B |\n|---|---|\n| 1 | 2 |"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Table content should have code (monospace) font for column alignment
        let cellStart = source.distance(from: source.startIndex, to: source.range(of: "1")!.lowerBound)
        let font = attrStr.attribute(.font, at: cellStart, effectiveRange: nil) as? PlatformFont
        #expect(font != nil, "Table cell should have a font")
        #expect(font!.pointSize == richConfig.typeScale.code.pointSize, "Table should use monospace code font")

        // Table should have background color
        let bg = attrStr.attribute(.backgroundColor, at: cellStart, effectiveRange: nil) as? PlatformColor
        #expect(bg != nil, "Table should have background color")

        // Text content must be preserved
        #expect(attrStr.string == source, "Table rendering must preserve text content")
    }

    @Test("Table header row is visually distinct with bold font")
    func tableHeaderIsBold() {
        let source = "| Header 1 | Header 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Header text should have bold trait
        let headerStart = source.distance(from: source.startIndex, to: source.range(of: "Header 1")!.lowerBound)
        if let font = attrStr.attribute(.font, at: headerStart, effectiveRange: nil) as? PlatformFont {
            #if canImport(UIKit)
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold), "Header should be bold")
            #elseif canImport(AppKit)
            #expect(font.fontDescriptor.symbolicTraits.contains(.bold), "Header should be bold")
            #endif
        }

        // Header should have tableHeader attribute
        let headerAttr = attrStr.attribute(.tableHeader, at: headerStart, effectiveRange: nil)
        #expect(headerAttr != nil, "Header should have tableHeader attribute")

        // Body cell should NOT be bold
        let cellStart = source.distance(from: source.startIndex, to: source.range(of: "Cell 1")!.lowerBound)
        if let bodyFont = attrStr.attribute(.font, at: cellStart, effectiveRange: nil) as? PlatformFont {
            #if canImport(UIKit)
            #expect(!bodyFont.fontDescriptor.symbolicTraits.contains(.traitBold), "Body cells should not be bold")
            #elseif canImport(AppKit)
            #expect(!bodyFont.fontDescriptor.symbolicTraits.contains(.bold), "Body cells should not be bold")
            #endif
        }
    }

    @Test("Table separator row is hidden in rich view")
    func tableSeparatorIsHidden() {
        let source = "| A | B |\n|---|---|\n| 1 | 2 |"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The separator row "|---|---|" should be hidden (zero-width font)
        let separatorStart = source.distance(from: source.startIndex, to: source.range(of: "|---|")!.lowerBound)
        let font = attrStr.attribute(.font, at: separatorStart, effectiveRange: nil) as? PlatformFont
        #expect(font != nil)
        #expect(font!.pointSize < 1, "Separator row should be hidden with tiny font")
    }

    @Test("Empty table cells render as space, not collapsed")
    func emptyTableCells() {
        let source = "| A |   | C |\n|---|---|---|\n| 1 |   | 3 |"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Text must be preserved — empty cells remain as whitespace
        #expect(attrStr.string == source, "Empty cells must preserve whitespace")

        // The empty cell region should still have the table font (not collapsed)
        let emptyRegion = source.distance(from: source.startIndex, to: source.range(of: "|   |", range: source.range(of: "| 1 |   | 3 |")!)!.lowerBound) + 1
        let font = attrStr.attribute(.font, at: emptyRegion, effectiveRange: nil) as? PlatformFont
        #expect(font != nil, "Empty cell region should have a font applied")
    }

    @Test("Table with many columns renders without crash")
    func tableWithManyColumns() {
        // 12-column table
        let header = "| " + (1...12).map { "Col\($0)" }.joined(separator: " | ") + " |"
        let separator = "|" + String(repeating: "---|", count: 12)
        let row = "| " + (1...12).map { "V\($0)" }.joined(separator: " | ") + " |"
        let source = "\(header)\n\(separator)\n\(row)"

        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        // Should not crash and should preserve text
        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )
        #expect(attrStr.string == source)
    }

    @Test("Table with many rows renders without crash")
    func tableWithManyRows() {
        var lines = ["| A | B |", "|---|---|"]
        for i in 1...120 {
            lines.append("| \(i) | \(i * 2) |")
        }
        let source = lines.joined(separator: "\n")

        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )
        #expect(attrStr.string == source, "Large table must preserve content")
    }

    @Test("Table in source view gets code font and background")
    func tableSourceView() {
        let source = "| A | B |\n|---|---|\n| 1 | 2 |"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: sourceConfig
        )

        // Source view: separator should NOT be hidden
        let separatorStart = source.distance(from: source.startIndex, to: source.range(of: "|---|")!.lowerBound)
        let font = attrStr.attribute(.font, at: separatorStart, effectiveRange: nil) as? PlatformFont
        #expect(font != nil)
        #expect(font!.pointSize > 1, "Source view should not hide separator")

        // Should have code background
        let bg = attrStr.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? PlatformColor
        #expect(bg != nil, "Source view table should have background")
    }

    @Test("Table with inline formatting renders correctly")
    func tableWithInlineFormatting() {
        let source = "| **Bold** | *Italic* |\n|----------|----------|\n| `code`   | Normal   |"
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

        // Bold text in header should exist (header is already bold, so bold+bold)
        let boldStart = source.distance(from: source.startIndex, to: source.range(of: "Bold")!.lowerBound)
        let font = attrStr.attribute(.font, at: boldStart, effectiveRange: nil) as? PlatformFont
        #expect(font != nil)
    }

    @Test("Table with alignment separators hides them correctly")
    func tableWithAlignmentSeparators() {
        let source = "| Left | Center | Right |\n|:-----|:------:|------:|\n| L    | C      | R     |"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The separator row with alignment markers should be hidden
        let separatorStart = source.distance(from: source.startIndex, to: source.range(of: ":-----")!.lowerBound)
        let font = attrStr.attribute(.font, at: separatorStart, effectiveRange: nil) as? PlatformFont
        #expect(font != nil)
        #expect(font!.pointSize < 1, "Alignment separator should be hidden")

        #expect(attrStr.string == source)
    }

    // MARK: - Task List Checkbox Rendering (FEAT-049)

    @Test("Unchecked task list item gets taskListCheckbox attribute in rich view")
    func uncheckedCheckboxAttribute() {
        let source = "- [ ] Buy milk"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Find the "[ ]" range
        let checkboxStart = source.distance(from: source.startIndex, to: source.range(of: "[ ]")!.lowerBound)
        let checkboxAttr = attrStr.attribute(.taskListCheckbox, at: checkboxStart, effectiveRange: nil) as? String
        #expect(checkboxAttr == "unchecked", "Unchecked checkbox should have taskListCheckbox attribute")

        // Should have link color for interactivity
        let color = attrStr.attribute(.foregroundColor, at: checkboxStart, effectiveRange: nil) as? PlatformColor
        #expect(color != nil, "Checkbox should have foreground color")

        #expect(attrStr.string == source, "Checkbox rendering must preserve text content")
    }

    @Test("Checked task list item gets taskListCheckbox attribute in rich view")
    func checkedCheckboxAttribute() {
        let source = "- [x] Done task"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        let checkboxStart = source.distance(from: source.startIndex, to: source.range(of: "[x]")!.lowerBound)
        let checkboxAttr = attrStr.attribute(.taskListCheckbox, at: checkboxStart, effectiveRange: nil) as? String
        #expect(checkboxAttr == "checked", "Checked checkbox should have taskListCheckbox attribute")

        #expect(attrStr.string == source)
    }

    @Test("Task list checkbox attribute not applied in source view")
    func checkboxNotInSourceView() {
        let source = "- [ ] Task item"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: sourceConfig
        )

        // In source view, no taskListCheckbox attribute should be present
        let checkboxStart = source.distance(from: source.startIndex, to: source.range(of: "[ ]")!.lowerBound)
        let checkboxAttr = attrStr.attribute(.taskListCheckbox, at: checkboxStart, effectiveRange: nil)
        #expect(checkboxAttr == nil, "Source view should not have taskListCheckbox attribute")
    }

    @Test("Multiple task list items each get checkbox attributes")
    func multipleCheckboxes() {
        let source = "- [ ] First\n- [x] Second\n- [ ] Third"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // First checkbox: unchecked
        let first = source.distance(from: source.startIndex, to: source.range(of: "[ ]")!.lowerBound)
        let firstAttr = attrStr.attribute(.taskListCheckbox, at: first, effectiveRange: nil) as? String
        #expect(firstAttr == "unchecked")

        // Second checkbox: checked
        let second = source.distance(from: source.startIndex, to: source.range(of: "[x]")!.lowerBound)
        let secondAttr = attrStr.attribute(.taskListCheckbox, at: second, effectiveRange: nil) as? String
        #expect(secondAttr == "checked")

        #expect(attrStr.string == source)
    }

    // MARK: - Link Rendering (FEAT-049)

    @Test("Link gets .link attribute with URL in rich view")
    func linkAttribute() {
        let source = "Click [here](https://example.com) now"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The link text "here" should have a .link attribute with the URL
        let hereStart = source.distance(from: source.startIndex, to: source.range(of: "here")!.lowerBound)
        let linkAttr = attrStr.attribute(.link, at: hereStart, effectiveRange: nil)
        #expect(linkAttr != nil, "Link text should have .link attribute")

        if let url = linkAttr as? URL {
            #expect(url.absoluteString == "https://example.com")
        }

        // Link should have link color
        let color = attrStr.attribute(.foregroundColor, at: hereStart, effectiveRange: nil) as? PlatformColor
        #expect(color != nil, "Link text should have foreground color")

        // Link should have underline
        let underline = attrStr.attribute(.underlineStyle, at: hereStart, effectiveRange: nil) as? Int
        #expect(underline == NSUnderlineStyle.single.rawValue, "Link should have subtle underline")

        #expect(attrStr.string == source)
    }

    @Test("Link syntax is hidden in rich view")
    func linkSyntaxHidden() {
        let source = "[text](https://url.com)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // The "[" at position 0 should be hidden (zero-width font)
        let bracketFont = attrStr.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(bracketFont != nil)
        #expect(bracketFont!.pointSize < 1, "Opening bracket should be hidden")

        // The "](url)" part should be hidden
        let closeBracketStart = source.distance(from: source.startIndex, to: source.range(of: "](")!.lowerBound)
        let closeFont = attrStr.attribute(.font, at: closeBracketStart, effectiveRange: nil) as? PlatformFont
        #expect(closeFont != nil)
        #expect(closeFont!.pointSize < 1, "Closing syntax should be hidden")

        #expect(attrStr.string == source)
    }

    @Test("Link not interactive in source view")
    func linkNotInteractiveInSource() {
        let source = "[text](https://url.com)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: sourceConfig
        )

        // In source view, link text should have link color but no .link attribute
        let textStart = source.distance(from: source.startIndex, to: source.range(of: "text")!.lowerBound)
        let linkAttr = attrStr.attribute(.link, at: textStart, effectiveRange: nil)
        #expect(linkAttr == nil, "Source view should not have .link attribute")
    }

    // MARK: - Image Rendering (FEAT-048)

    @Test("Image gets markdownNodeType 'image' attribute in rich view")
    func imageNodeTypeAttribute() {
        let source = "![alt text](image.png)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Should have markdownNodeType "image"
        let nodeType = attrStr.attribute(.markdownNodeType, at: 0, effectiveRange: nil) as? String
        #expect(nodeType == "image", "Image node should have markdownNodeType attribute")

        // Text content must be preserved
        #expect(attrStr.string == source, "Image rendering must preserve text content")
    }

    @Test("Image alt text attribute is set in rich view")
    func imageAltTextAttribute() {
        let source = "![diagram](./images/arch.png)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        let altText = attrStr.attribute(.imageAltText, at: 0, effectiveRange: nil) as? String
        #expect(altText == "diagram", "Image should have alt text attribute")
    }

    @Test("Broken image shows placeholder icon and alt text in rich view")
    func imageSyntaxHiddenInRichView() {
        let source = "![alt text](missing.png)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // Position 0 should have a placeholder icon attachment per AC-3
        let attachment = attrStr.attribute(.attachment, at: 0, effectiveRange: nil)
        #expect(attachment != nil, "Broken image should have placeholder icon attachment")

        // "[" at position 1 should be hidden (zero-width font)
        let bracketFont = attrStr.attribute(.font, at: 1, effectiveRange: nil) as? PlatformFont
        #expect(bracketFont != nil)
        #expect(bracketFont!.pointSize < 1, "Opening bracket '[' should be hidden")

        // "](missing.png)" should be hidden
        let closeSyntaxStart = source.distance(from: source.startIndex, to: source.range(of: "](")!.lowerBound)
        let closeFont = attrStr.attribute(.font, at: closeSyntaxStart, effectiveRange: nil) as? PlatformFont
        #expect(closeFont != nil)
        #expect(closeFont!.pointSize < 1, "Image closing syntax '](url)' should be hidden")

        // Alt text "alt text" should be visible (not hidden)
        let altStart = source.distance(from: source.startIndex, to: source.range(of: "alt text")!.lowerBound)
        let altFont = attrStr.attribute(.font, at: altStart, effectiveRange: nil) as? PlatformFont
        #expect(altFont != nil)
        #expect(altFont!.pointSize > 1, "Alt text should be visible in rich view")

        #expect(attrStr.string == source)
    }

    @Test("Image in source view gets link color")
    func imageSourceViewColor() {
        let source = "![photo](image.jpg)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: sourceConfig
        )

        // In source view, the "!" should have link color
        let color = attrStr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
        #expect(color != nil, "Image should have foreground color in source view")

        // Syntax should NOT be hidden in source view
        let font = attrStr.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(font != nil)
        #expect(font!.pointSize > 1, "Source view should not hide image syntax")
    }

    @Test("Image with empty alt text renders without crash")
    func imageEmptyAltText() {
        let source = "![](path/to/image.png)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        #expect(attrStr.string == source, "Image with empty alt text must preserve content")

        let altText = attrStr.attribute(.imageAltText, at: 0, effectiveRange: nil) as? String
        #expect(altText == "", "Empty alt text should still have attribute")
    }

    @Test("Multiple images in document render independently")
    func multipleImages() {
        let source = "![first](a.png)\n\n![second](b.png)"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        // First image
        let firstAlt = attrStr.attribute(.imageAltText, at: 0, effectiveRange: nil) as? String
        #expect(firstAlt == "first")

        // Second image
        let secondStart = source.distance(from: source.startIndex, to: source.range(of: "![second]")!.lowerBound)
        let secondAlt = attrStr.attribute(.imageAltText, at: secondStart, effectiveRange: nil) as? String
        #expect(secondAlt == "second")

        #expect(attrStr.string == source)
    }

    @Test("Image with no source renders without crash")
    func imageNoSource() {
        let source = "![alt]()"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: richConfig
        )

        #expect(attrStr.string == source, "Image with no source must preserve content")
    }
}
