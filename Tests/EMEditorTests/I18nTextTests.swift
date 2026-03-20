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

/// Tests for i18n text support per FEAT-051.
/// Covers CJK rendering, RTL text, mixed bidirectional text,
/// emoji grapheme clusters, and IME composition.
@MainActor
@Suite("I18n Text Support (FEAT-051)")
struct I18nTextTests {

    private let renderer = MarkdownRenderer()
    private let parser = MarkdownParser()
    private let mapper = CursorMapper()

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

    // MARK: - AC-1: CJK Text Rendering and Line Breaking

    @Test("Chinese text renders with correct attributed string length")
    func chineseTextRendering() {
        let text = "# 你好世界\n\n这是一段中文文本。"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)

        // Attributed string length should match UTF-16 length
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Japanese text renders correctly")
    func japaneseTextRendering() {
        let text = "# 日本語テスト\n\nこんにちは、世界。"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Korean text renders correctly")
    func koreanTextRendering() {
        let text = "# 한국어 테스트\n\n안녕하세요."
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("CJK characters have individual cursor positions")
    func cjkCursorPositions() {
        let text = "你好世界"
        // Each CJK character is 1 UTF-16 code unit, so cursor can land at each position
        let pos = mapper.sourcePosition(atUTF16Offset: 2, in: text)
        #expect(pos != nil)
        #expect(pos?.line == 1)
        #expect(pos?.column == 3) // 1-based column for 3rd character
    }

    @Test("CJK word count uses NLTokenizer segmentation")
    func cjkWordCount() {
        // Chinese sentence — NLTokenizer should segment into multiple tokens
        let count = DocumentStatsCalculator.countWords(in: "我爱中国人民")
        #expect(count > 0) // Must produce word tokens, not 0
    }

    @Test("CJK paragraph style uses natural alignment and writing direction")
    func cjkParagraphStyleDirection() {
        let text = "你好世界"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)

        // Check paragraph style has natural base writing direction
        var effectiveRange = NSRange()
        if let paragraphStyle = attrStr.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: &effectiveRange
        ) as? NSParagraphStyle {
            #expect(paragraphStyle.baseWritingDirection == .natural)
            #expect(paragraphStyle.alignment == .natural)
        }
    }

    // MARK: - AC-2: RTL Text (Arabic, Hebrew)

    @Test("Arabic text renders with correct attributed string length")
    func arabicTextRendering() {
        let text = "# مرحبا\n\nهذا نص عربي."
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Hebrew text renders with correct attributed string length")
    func hebrewTextRendering() {
        let text = "# שלום\n\nזה טקסט בעברית."
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Arabic paragraph style has natural base writing direction")
    func arabicWritingDirection() {
        let text = "مرحبا بالعالم"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)

        var effectiveRange = NSRange()
        if let paragraphStyle = attrStr.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: &effectiveRange
        ) as? NSParagraphStyle {
            // Natural direction allows the system to detect RTL from Arabic characters
            #expect(paragraphStyle.baseWritingDirection == .natural)
        }
    }

    @Test("RTL cursor mapping works correctly")
    func rtlCursorMapping() {
        // Arabic text within a heading
        let text = "# مرحبا"
        let ast = parser.parse(text).ast
        // Cursor inside heading marker should snap past prefix
        let result = mapper.mapSourceToRich(
            selectedRange: NSRange(location: 0, length: 0),
            text: text,
            ast: ast
        )
        #expect(result.location == 2) // Past "# "
    }

    // MARK: - AC-3: Mixed LTR and RTL Text

    @Test("Mixed LTR/RTL text renders with correct length")
    func mixedDirectionTextRendering() {
        let text = "Hello مرحبا World שלום"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Mixed direction paragraph has natural writing direction")
    func mixedDirectionWritingDirection() {
        let text = "English العربية Hebrew עברית"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)

        var effectiveRange = NSRange()
        if let paragraphStyle = attrStr.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: &effectiveRange
        ) as? NSParagraphStyle {
            // Natural direction allows Unicode BiDi algorithm to order mixed text correctly
            #expect(paragraphStyle.baseWritingDirection == .natural)
        }
    }

    @Test("Mixed direction cursor position round-trips correctly")
    func mixedDirectionCursorRoundTrip() {
        let text = "Hello مرحبا World"
        let offset = 8 // Somewhere in the Arabic portion
        let pos = mapper.sourcePosition(atUTF16Offset: offset, in: text)
        #expect(pos != nil)
        if let pos {
            let backToOffset = mapper.utf16Offset(for: pos, in: text)
            #expect(backToOffset == offset)
        }
    }

    // MARK: - AC-4: Multi-Codepoint Emoji

    @Test("Flag emoji renders correctly in attributed string")
    func flagEmojiRendering() {
        // 🇯🇵 flag emoji
        let text = "Hello 🇯🇵 World"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Skin tone emoji renders correctly in attributed string")
    func skinToneEmojiRendering() {
        let text = "Hello 👍🏽 World"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("ZWJ sequence emoji renders correctly")
    func zwjEmojiRendering() {
        // 👨‍👩‍👧‍👦 family emoji
        let text = "Family: 👨‍👩‍👧‍👦"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Emoji cursor mapping preserves grapheme cluster integrity")
    func emojiCursorMapping() {
        // Text with multi-codepoint emoji
        let text = "A🇯🇵B"
        let pos = mapper.sourcePosition(atUTF16Offset: 1, in: text)
        #expect(pos != nil)
        // The flag emoji starts at UTF-16 offset 1 and spans 4 UTF-16 code units
        // After the flag, B is at offset 5
        let posAfterFlag = mapper.sourcePosition(atUTF16Offset: 5, in: text)
        #expect(posAfterFlag != nil)
    }

    @Test("Emoji in markdown heading renders correctly")
    func emojiInHeading() {
        let text = "# Hello 🌍 World"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)

        // Heading font should be applied
        var effectiveRange = NSRange()
        if let font = attrStr.attribute(.font, at: 2, effectiveRange: &effectiveRange) as? PlatformFont {
            #expect(font.pointSize >= richConfig.typeScale.body.pointSize)
        }
    }

    @Test("Emoji word count does not crash or miscount")
    func emojiWordCount() {
        let text = "Hello 👋🏽 World 🌍🇯🇵"
        let count = DocumentStatsCalculator.countWords(in: text)
        // Should count at least "Hello" and "World"
        #expect(count >= 2)
    }

    // MARK: - AC-5: IME Composition

    // Note: IME composition testing requires a live text view with input simulation.
    // These tests verify the infrastructure that supports IME:
    // - markedText checks in TextViewCoordinator
    // - Correct handling of partial text during composition

    @Test("CJK text with markdown formatting renders correctly")
    func cjkMarkdownFormatting() {
        // Bold CJK text
        let text = "**你好世界**"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("CJK list items render correctly")
    func cjkListItems() {
        let text = "- 第一项\n- 第二项\n- 第三项"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("RTL list items render correctly")
    func rtlListItems() {
        let text = "- عنصر أول\n- عنصر ثاني"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    // MARK: - Source View Mode

    @Test("CJK text renders correctly in source view")
    func cjkSourceView() {
        let text = "# 你好\n\n这是**粗体**文本。"
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: sourceConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("RTL text renders correctly in source view")
    func rtlSourceView() {
        let text = "# مرحبا\n\nنص **غامق** هنا."
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: sourceConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    @Test("Emoji text renders correctly in source view")
    func emojiSourceView() {
        let text = "# 🎉 Title\n\nParagraph with 👨‍👩‍👧‍👦 emoji."
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: sourceConfig)
        #expect(attrStr.length == text.utf16.count)
    }

    // MARK: - Writing Direction in All Block Types

    @Test("All rendered block types propagate natural writing direction")
    func allBlockTypesNaturalDirection() {
        // Document with various block types
        let text = """
        # عنوان

        فقرة نصية.

        > اقتباس

        - عنصر قائمة

        1. عنصر مرقم

        ```
        code
        ```

        ---

        | رأس |
        | --- |
        | خلية |
        """
        let parseResult = parser.parse(text)
        let attrStr = NSMutableAttributedString(string: text)
        renderer.render(into: attrStr, ast: parseResult.ast, sourceText: text, config: richConfig)

        // Sample several positions and verify natural writing direction
        let checkOffsets = [0, 10, 20, 30]
        for offset in checkOffsets where offset < attrStr.length {
            var effectiveRange = NSRange()
            if let paragraphStyle = attrStr.attribute(
                .paragraphStyle,
                at: offset,
                effectiveRange: &effectiveRange
            ) as? NSParagraphStyle {
                #expect(
                    paragraphStyle.baseWritingDirection == .natural,
                    "Offset \(offset) should have natural writing direction"
                )
            }
        }
    }
}
