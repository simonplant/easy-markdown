import Foundation
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore
import EMParser
import EMEditor

/// Renders markdown text to a polished PDF with rich formatting per [A-056] and FEAT-018.
///
/// Parses markdown into an AST, walks it to build a styled NSAttributedString
/// (headings, lists, code blocks with syntax highlighting, images, blockquotes,
/// tables), then renders to multi-page PDF using TextKit 1's NSLayoutManager
/// which handles text attachments (images) natively.
///
/// Watermark per FEAT-061: optional "Made with easy-markdown" footer.
struct PDFExporter {

    /// Configuration for the watermark appearance.
    private enum WatermarkStyle {
        static let text = "Made with easy-markdown"
        static let fontSize: CGFloat = 8
        #if canImport(UIKit)
        static let color = UIColor.lightGray.withAlphaComponent(0.5)
        #else
        static let color = NSColor.lightGray.withAlphaComponent(0.5)
        #endif
        /// Bottom margin from the page edge.
        static let bottomMargin: CGFloat = 20
    }

    /// Page dimensions matching US Letter (default PDF page size).
    private enum PageLayout {
        static let width: CGFloat = 612
        static let height: CGFloat = 792
        static let contentMargin: CGFloat = 72 // 1 inch
        static var contentWidth: CGFloat { width - contentMargin * 2 }
        static var contentHeight: CGFloat { height - contentMargin * 2 }
    }

    // MARK: - Print colors (always light theme for paper)

    private static let colors = ThemeColors.defaultLight

    // MARK: - Print-optimized type scale

    /// Print-optimized type scale: slightly smaller than editor for paper density.
    private static let typeScale: TypeScale = {
        FontRegistration.registerFonts()

        #if canImport(UIKit)
        // For PDF, use fixed-size fonts (no Dynamic Type scaling)
        let font: (String, CGFloat) -> PlatformFont = { name, size in
            FontRegistration.font(named: name, size: size)
        }
        #else
        let font: (String, CGFloat) -> PlatformFont = { name, size in
            FontRegistration.font(named: name, size: size)
        }
        #endif

        return TypeScale(
            heading1: font(FontRegistration.FontName.serifDisplayBold, 24),
            heading2: font(FontRegistration.FontName.serifDisplayBold, 20),
            heading3: font(FontRegistration.FontName.serifDisplaySemibold, 17),
            heading4: font(FontRegistration.FontName.serifSemibold, 14),
            heading5: font(FontRegistration.FontName.serifSemibold, 12),
            heading6: font(FontRegistration.FontName.serifRegular, 11),
            body: font(FontRegistration.FontName.serifRegular, 12),
            code: font(FontRegistration.FontName.monoRegular, 10),
            caption: PlatformFont.systemFont(ofSize: 9),
            ui: PlatformFont.systemFont(ofSize: 9)
        )
    }()

    // MARK: - Public API

    /// Generates PDF data from the given markdown text.
    ///
    /// - Parameters:
    ///   - text: The markdown text to render.
    ///   - documentURL: URL of the source document for resolving relative image paths.
    ///   - includeWatermark: Whether to draw the footer watermark.
    /// - Returns: The rendered PDF as `Data`.
    static func exportPDF(text: String, documentURL: URL?, includeWatermark: Bool) -> Data {
        let parser = MarkdownParser()
        let parseResult = parser.parse(text)
        let attributedText = buildAttributedString(from: parseResult.ast, sourceText: text, documentURL: documentURL)
        return renderPDF(attributedText: attributedText, includeWatermark: includeWatermark)
    }

    /// Generates a rich NSAttributedString suitable for printing.
    ///
    /// Used by both PDF export and the print flow to share the same rendering pipeline.
    static func renderAttributedString(text: String, documentURL: URL?) -> NSAttributedString {
        let parser = MarkdownParser()
        let parseResult = parser.parse(text)
        return buildAttributedString(from: parseResult.ast, sourceText: text, documentURL: documentURL)
    }

    // MARK: - AST → NSAttributedString

    private static func buildAttributedString(
        from ast: MarkdownAST,
        sourceText: String,
        documentURL: URL?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in ast.blocks.enumerated() {
            appendBlock(block, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: 0)
            // Add paragraph separator between top-level blocks (except after last)
            if index < ast.blocks.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            }
        }
        return result
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 6
        style.alignment = .natural
        style.baseWritingDirection = .natural

        return [
            .font: typeScale.body,
            .foregroundColor: colors.foreground,
            .paragraphStyle: style,
        ]
    }

    // MARK: - Block Node Rendering

    private static func appendBlock(
        _ node: MarkdownNode,
        to result: NSMutableAttributedString,
        sourceText: String,
        documentURL: URL?,
        nestingLevel: Int
    ) {
        switch node.type {
        case .heading(let level):
            appendHeading(node, level: level, to: result, sourceText: sourceText, documentURL: documentURL)

        case .paragraph:
            appendInlineChildren(of: node, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: typeScale.body)

        case .blockQuote:
            appendBlockquote(node, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel)

        case .orderedList, .unorderedList:
            for (itemIndex, child) in node.children.enumerated() {
                if case .listItem(let checkbox) = child.type {
                    let marker: String
                    if let checkbox {
                        marker = checkbox == .checked ? "☑ " : "☐ "
                    } else if case .orderedList = node.type {
                        marker = "\(itemIndex + 1). "
                    } else {
                        marker = "• "
                    }
                    appendListItem(child, marker: marker, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel)
                } else {
                    appendBlock(child, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel)
                }
            }

        case .listItem:
            appendListItem(node, marker: "• ", to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel)

        case .codeBlock(let language):
            appendCodeBlock(node, language: language, to: result)

        case .thematicBreak:
            appendThematicBreak(to: result)

        case .table:
            appendTable(node, to: result, sourceText: sourceText)

        default:
            for child in node.children {
                appendBlock(child, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel)
            }
        }
    }

    // MARK: - Headings

    private static func appendHeading(
        _ node: MarkdownNode,
        level: Int,
        to result: NSMutableAttributedString,
        sourceText: String,
        documentURL: URL?
    ) {
        let font = typeScale.headingFont(level: level)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.alignment = .natural
        style.baseWritingDirection = .natural
        style.paragraphSpacingBefore = level <= 2 ? 12 : 8
        style.paragraphSpacing = level <= 2 ? 8 : 6

        let headingStr = NSMutableAttributedString()
        appendInlineChildren(of: node, to: headingStr, sourceText: sourceText, documentURL: documentURL, baseFont: font)

        // Apply heading color and paragraph style without overwriting per-span fonts
        let headingRange = NSRange(location: 0, length: headingStr.length)
        if headingRange.length > 0 {
            headingStr.addAttributes([
                .foregroundColor: colors.heading,
                .paragraphStyle: style,
            ], range: headingRange)
        }
        result.append(headingStr)
    }

    // MARK: - Lists

    private static func appendListItem(
        _ node: MarkdownNode,
        marker: String,
        to result: NSMutableAttributedString,
        sourceText: String,
        documentURL: URL?,
        nestingLevel: Int
    ) {
        let indent = CGFloat(nestingLevel) * 20.0 + 20.0
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.alignment = .natural
        style.baseWritingDirection = .natural
        style.headIndent = indent
        style.firstLineHeadIndent = indent - 14.0
        style.paragraphSpacing = 3
        style.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]

        let listAttrs: [NSAttributedString.Key: Any] = [
            .font: typeScale.body,
            .foregroundColor: colors.foreground,
            .paragraphStyle: style,
        ]

        // Append marker
        result.append(NSAttributedString(string: marker, attributes: [
            .font: typeScale.body,
            .foregroundColor: colors.listMarker,
            .paragraphStyle: style,
        ]))

        // Append inline content from child paragraphs
        for child in node.children {
            switch child.type {
            case .paragraph:
                appendInlineChildren(of: child, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: typeScale.body)
            case .orderedList, .unorderedList:
                result.append(NSAttributedString(string: "\n", attributes: listAttrs))
                appendBlock(child, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel + 1)
            default:
                appendBlock(child, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel)
            }
        }
        // Trailing newline to separate from next item
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: typeScale.body,
            .paragraphStyle: style,
        ]))
    }

    // MARK: - Blockquotes

    private static func appendBlockquote(
        _ node: MarkdownNode,
        to result: NSMutableAttributedString,
        sourceText: String,
        documentURL: URL?,
        nestingLevel: Int
    ) {
        let indent = CGFloat(nestingLevel + 1) * 16.0
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.alignment = .natural
        style.baseWritingDirection = .natural
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        style.paragraphSpacing = 4

        let startPos = result.length
        for child in node.children {
            appendBlock(child, to: result, sourceText: sourceText, documentURL: documentURL, nestingLevel: nestingLevel + 1)
            result.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
        }

        // Apply blockquote styling over the appended content
        let quoteRange = NSRange(location: startPos, length: result.length - startPos)
        if quoteRange.length > 0 {
            result.addAttributes([
                .foregroundColor: colors.blockquoteForeground,
                .paragraphStyle: style,
            ], range: quoteRange)
        }
    }

    // MARK: - Code Blocks

    private static func appendCodeBlock(
        _ node: MarkdownNode,
        language: String?,
        to result: NSMutableAttributedString
    ) {
        let code = node.literalText ?? ""
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1
        style.paragraphSpacing = 8
        style.paragraphSpacingBefore = 8
        style.alignment = .natural
        style.baseWritingDirection = .natural

        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: typeScale.code,
            .foregroundColor: colors.codeForeground,
            .backgroundColor: colors.codeBackground,
            .paragraphStyle: style,
        ]

        let codeStr = NSMutableAttributedString(string: code, attributes: codeAttrs)

        // Apply syntax highlighting
        applySyntaxHighlighting(to: codeStr, language: language)

        result.append(codeStr)
    }

    // MARK: - Tables

    private static func appendTable(
        _ node: MarkdownNode,
        to result: NSMutableAttributedString,
        sourceText: String
    ) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1
        style.paragraphSpacing = 4
        style.paragraphSpacingBefore = 4
        style.alignment = .natural
        style.baseWritingDirection = .natural

        // Extract rows from table head and body
        var rows: [[String]] = []

        for section in node.children {
            for row in section.children where row.type == .tableRow {
                var cells: [String] = []
                for cell in row.children where cell.type == .tableCell {
                    let cellText = extractPlainText(from: cell)
                    cells.append(cellText)
                }
                rows.append(cells)
            }
        }

        guard !rows.isEmpty else { return }

        // Compute column widths
        let colCount = rows.map(\.count).max() ?? 0
        var colWidths = [CGFloat](repeating: 0, count: colCount)
        for row in rows {
            for (col, cell) in row.enumerated() where col < colCount {
                let size = (cell as NSString).size(withAttributes: [.font: typeScale.code])
                colWidths[col] = max(colWidths[col], size.width + 16)
            }
        }

        // Render table rows as monospace formatted text
        for (rowIndex, row) in rows.enumerated() {
            var line = ""
            for (col, cell) in row.enumerated() where col < colCount {
                let padded = cell.padding(toLength: max(Int(colWidths[col] / 7), cell.count), withPad: " ", startingAt: 0)
                line += padded + "  "
            }

            let font = rowIndex == 0 ? fontWithBoldTrait(typeScale.code) : typeScale.code
            let rowAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
                .backgroundColor: rowIndex == 0 ? colors.codeBackground : PlatformColor.clear,
                .paragraphStyle: style,
            ]
            result.append(NSAttributedString(string: line + "\n", attributes: rowAttrs))
        }
    }

    // MARK: - Thematic Break

    private static func appendThematicBreak(to result: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8

        let breakStr = NSAttributedString(
            string: "——————————————————————————————\n",
            attributes: [
                .foregroundColor: colors.thematicBreak,
                .font: typeScale.body,
                .paragraphStyle: style,
            ]
        )
        result.append(breakStr)
    }

    // MARK: - Inline Rendering

    private static func appendInlineChildren(
        of node: MarkdownNode,
        to result: NSMutableAttributedString,
        sourceText: String,
        documentURL: URL?,
        baseFont: PlatformFont
    ) {
        for child in node.children {
            appendInlineNode(child, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: baseFont)
        }
    }

    private static func appendInlineNode(
        _ node: MarkdownNode,
        to result: NSMutableAttributedString,
        sourceText: String,
        documentURL: URL?,
        baseFont: PlatformFont
    ) {
        switch node.type {
        case .text:
            let text = node.literalText ?? ""
            result.append(NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: colors.foreground,
            ]))

        case .softBreak:
            result.append(NSAttributedString(string: " ", attributes: [.font: baseFont]))

        case .lineBreak:
            result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))

        case .strong:
            let boldFont = fontWithBoldTrait(baseFont)
            appendInlineChildren(of: node, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: boldFont)

        case .emphasis:
            let italicFont = fontWithItalicTrait(baseFont)
            appendInlineChildren(of: node, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: italicFont)

        case .strikethrough:
            let startPos = result.length
            appendInlineChildren(of: node, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: baseFont)
            let range = NSRange(location: startPos, length: result.length - startPos)
            if range.length > 0 {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

        case .inlineCode:
            let code = node.literalText ?? ""
            result.append(NSAttributedString(string: code, attributes: [
                .font: typeScale.code,
                .foregroundColor: colors.codeForeground,
                .backgroundColor: colors.codeBackground,
            ]))

        case .link(let destination):
            let startPos = result.length
            appendInlineChildren(of: node, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: baseFont)
            let range = NSRange(location: startPos, length: result.length - startPos)
            if range.length > 0 {
                result.addAttributes([
                    .foregroundColor: colors.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
                if let dest = destination, let url = URL(string: dest) {
                    result.addAttribute(.link, value: url, range: range)
                }
            }

        case .image(let source):
            appendImage(source: source, node: node, to: result, documentURL: documentURL)

        case .inlineHTML:
            // Skip HTML in PDF
            break

        default:
            appendInlineChildren(of: node, to: result, sourceText: sourceText, documentURL: documentURL, baseFont: baseFont)
        }
    }

    // MARK: - Images

    private static func appendImage(
        source: String?,
        node: MarkdownNode,
        to result: NSMutableAttributedString,
        documentURL: URL?
    ) {
        guard let source, !source.isEmpty else { return }

        let resolvedURL = ImageLoader.resolveImageURL(source: source, documentURL: documentURL)
        guard let url = resolvedURL else { return }

        // Load image synchronously for PDF rendering
        guard let image = loadImageSync(from: url) else {
            // Show alt text for broken images
            let altText = extractPlainText(from: node)
            if !altText.isEmpty {
                result.append(NSAttributedString(string: "[\(altText)]", attributes: [
                    .font: typeScale.body,
                    .foregroundColor: colors.blockquoteForeground,
                ]))
            }
            return
        }

        let maxWidth = PageLayout.contentWidth
        let displaySize = ImageLoader.displaySize(for: image.size, maxWidth: maxWidth)
        let attachment = ImageTextAttachment(image: image, displaySize: displaySize)

        let imageStr = NSMutableAttributedString(attachment: attachment)
        // Ensure the attachment character has a paragraph style for proper layout
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacingBefore = 6
        style.paragraphSpacing = 6
        imageStr.addAttributes([
            .paragraphStyle: style,
        ], range: NSRange(location: 0, length: imageStr.length))
        result.append(imageStr)
    }

    private static func loadImageSync(from url: URL) -> PlatformImage? {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImageLoader.downsampleImage(data: data, maxDimension: 2048, maxWidth: PageLayout.contentWidth)
        } else if url.scheme == "http" || url.scheme == "https" {
            // Synchronous network load for PDF (best-effort)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImageLoader.downsampleImage(data: data, maxDimension: 2048, maxWidth: PageLayout.contentWidth)
        }
        return nil
    }

    // MARK: - Syntax Highlighting (simple regex for PDF)

    private static func applySyntaxHighlighting(
        to attrStr: NSMutableAttributedString,
        language: String?
    ) {
        guard let language, !language.isEmpty else { return }
        let text = attrStr.string
        let fullRange = NSRange(location: 0, length: attrStr.length)

        // Comment patterns (language-aware)
        let lang = language.lowercased()
        var commentPatterns: [String] = []
        let usesSlashComments = ["swift", "kotlin", "javascript", "js", "typescript", "ts",
                                  "jsx", "tsx", "java", "c", "cpp", "c++", "csharp", "cs",
                                  "go", "golang", "rust", "rs"].contains(lang)
        let usesHashComments = ["python", "py", "ruby", "rb", "bash", "sh", "zsh",
                                 "yaml", "yml", "toml", "perl"].contains(lang)
        if usesSlashComments {
            commentPatterns.append("//[^\n]*")
            commentPatterns.append("/\\*[\\s\\S]*?\\*/")
        }
        if usesHashComments {
            commentPatterns.append("#[^\n]*")
        }

        // String patterns
        let stringPatterns: [String] = [
            "\"(?:[^\"\\\\]|\\\\.)*\"",    // Double-quoted
            "'(?:[^'\\\\]|\\\\.)*'",       // Single-quoted
            "\"\"\"[\\s\\S]*?\"\"\"",      // Triple-quoted
        ]

        // Keyword sets by language family
        let keywords: String
        if ["swift", "kotlin"].contains(lang) {
            keywords = "\\b(func|var|let|class|struct|enum|protocol|import|return|if|else|guard|switch|case|for|while|do|try|catch|throw|throws|async|await|public|private|internal|static|self|super|nil|true|false|override|init|deinit|typealias|extension|where|in|is|as|break|continue|default|defer|fallthrough|repeat|subscript|associatedtype|convenience|dynamic|final|indirect|infix|lazy|mutating|nonmutating|operator|optional|postfix|prefix|required|unowned|weak|willSet|didSet|some|any)\\b"
        } else if ["python", "py"].contains(lang) {
            keywords = "\\b(def|class|import|from|return|if|elif|else|for|while|try|except|finally|raise|with|as|is|in|not|and|or|True|False|None|self|pass|break|continue|yield|lambda|global|nonlocal|assert|del|async|await)\\b"
        } else if ["javascript", "js", "typescript", "ts", "jsx", "tsx"].contains(lang) {
            keywords = "\\b(function|var|let|const|class|return|if|else|for|while|do|try|catch|throw|new|this|super|import|export|default|from|async|await|yield|typeof|instanceof|in|of|true|false|null|undefined|switch|case|break|continue|void|delete|debugger|extends|implements|interface|type|enum|abstract|static|public|private|protected|readonly|declare|module|namespace|require)\\b"
        } else if ["go", "golang"].contains(lang) {
            keywords = "\\b(func|var|const|type|struct|interface|import|return|if|else|for|range|switch|case|default|go|defer|select|chan|map|package|break|continue|fallthrough|goto|nil|true|false|make|new|len|cap|append|copy|delete|panic|recover|iota)\\b"
        } else if ["rust", "rs"].contains(lang) {
            keywords = "\\b(fn|let|mut|const|struct|enum|impl|trait|use|return|if|else|for|while|loop|match|pub|self|super|crate|mod|type|where|as|in|ref|move|static|unsafe|extern|async|await|dyn|true|false|None|Some|Ok|Err|break|continue|macro_rules)\\b"
        } else if ["java", "c", "cpp", "c++", "csharp", "cs"].contains(lang) {
            keywords = "\\b(class|public|private|protected|static|final|abstract|interface|extends|implements|return|if|else|for|while|do|try|catch|throw|throws|new|this|super|import|package|void|int|long|double|float|char|boolean|byte|short|true|false|null|switch|case|break|continue|default|enum|const|struct|unsigned|signed|typedef|include|define|ifdef|endif|pragma|namespace|using|virtual|override|template|typename|auto|register|volatile|extern|sizeof|delete)\\b"
        } else {
            keywords = "\\b(function|class|def|return|if|else|for|while|import|from|var|let|const|true|false|null|nil|None|self|this|new|try|catch|throw|switch|case|break|continue|public|private|static|void|int|string|bool)\\b"
        }

        // Number pattern
        let numberPattern = "\\b\\d+(\\.\\d+)?\\b"

        // Apply in order: comments first (highest priority), then strings, then keywords, then numbers
        // Track which ranges are already highlighted to avoid overlap
        var highlightedRanges: [NSRange] = []

        func applyPattern(_ pattern: String, color: PlatformColor, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                let range = match.range
                // Skip if overlapping with already highlighted range
                if highlightedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                    continue
                }
                attrStr.addAttribute(.foregroundColor, value: color, range: range)
                highlightedRanges.append(range)
            }
        }

        // Comments (highest priority)
        for pattern in commentPatterns {
            applyPattern(pattern, color: colors.syntaxComment, options: .dotMatchesLineSeparators)
        }

        // Strings
        for pattern in stringPatterns {
            applyPattern(pattern, color: colors.syntaxString, options: .dotMatchesLineSeparators)
        }

        // Keywords
        applyPattern(keywords, color: colors.syntaxKeyword)

        // Numbers
        applyPattern(numberPattern, color: colors.syntaxNumber)
    }

    // MARK: - PDF Rendering

    private static func renderPDF(
        attributedText: NSAttributedString,
        includeWatermark: Bool
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: PageLayout.width, height: PageLayout.height)
        let contentRect = pageRect.insetBy(dx: PageLayout.contentMargin, dy: PageLayout.contentMargin)

        #if canImport(UIKit)
        return renderWithUIKit(
            attributedText: attributedText,
            pageRect: pageRect,
            contentRect: contentRect,
            includeWatermark: includeWatermark
        )
        #else
        return renderWithCoreGraphics(
            attributedText: attributedText,
            pageRect: pageRect,
            contentRect: contentRect,
            includeWatermark: includeWatermark
        )
        #endif
    }

    #if canImport(UIKit)
    private static func renderWithUIKit(
        attributedText: NSAttributedString,
        pageRect: CGRect,
        contentRect: CGRect,
        includeWatermark: Bool
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "easy-markdown"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            renderPagesWithTextKit(
                attributedText: attributedText,
                pageRect: pageRect,
                contentRect: contentRect,
                includeWatermark: includeWatermark,
                beginPage: { context.beginPage() },
                cgContext: { context.cgContext }
            )
        }
    }
    #else
    private static func renderWithCoreGraphics(
        attributedText: NSAttributedString,
        pageRect: CGRect,
        contentRect: CGRect,
        includeWatermark: Bool
    ) -> Data {
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let pageInfo = [kCGPDFContextMediaBox: NSValue(rect: NSRect(origin: .zero, size: pageRect.size))] as CFDictionary
        renderPagesWithTextKit(
            attributedText: attributedText,
            pageRect: pageRect,
            contentRect: contentRect,
            includeWatermark: includeWatermark,
            beginPage: { cgContext.beginPDFPage(pageInfo) },
            cgContext: { cgContext },
            endPage: { cgContext.endPDFPage() }
        )

        cgContext.closePDF()
        return data as Data
    }
    #endif

    /// Renders pages using TextKit 1 (NSLayoutManager) for proper text attachment support.
    private static func renderPagesWithTextKit(
        attributedText: NSAttributedString,
        pageRect: CGRect,
        contentRect: CGRect,
        includeWatermark: Bool,
        beginPage: () -> Void,
        cgContext: () -> CGContext,
        endPage: (() -> Void)? = nil
    ) {
        // Handle empty documents
        if attributedText.length == 0 {
            beginPage()
            if includeWatermark {
                drawWatermark(in: cgContext(), pageRect: pageRect)
            }
            endPage?()
            return
        }

        // Use CTFramesetter for page layout (handles text attachments via CTRun delegates)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        var currentIndex = 0
        let totalLength = attributedText.length

        while currentIndex < totalLength {
            beginPage()
            let ctx = cgContext()

            let remainingRange = CFRange(location: currentIndex, length: totalLength - currentIndex)
            let path = CGPath(rect: contentRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, remainingRange, path, nil)

            // Draw code block backgrounds before drawing text
            drawCodeBlockBackgrounds(
                frame: frame,
                attributedText: attributedText,
                contentRect: contentRect,
                in: ctx,
                pageRect: pageRect
            )

            // Flip coordinate system for Core Text rendering
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageRect.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()

            // Draw images that are text attachments
            drawImageAttachments(
                frame: frame,
                attributedText: attributedText,
                contentRect: contentRect,
                in: ctx,
                pageRect: pageRect
            )

            if includeWatermark {
                drawWatermark(in: ctx, pageRect: pageRect)
            }

            endPage?()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentIndex += visibleRange.length

            // Safety: if no characters were laid out, break to prevent infinite loop
            if visibleRange.length == 0 { break }
        }
    }

    /// Draws background rectangles for code block regions in the current page.
    private static func drawCodeBlockBackgrounds(
        frame: CTFrame,
        attributedText: NSAttributedString,
        contentRect: CGRect,
        in ctx: CGContext,
        pageRect: CGRect
    ) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)

        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            guard lineRange.location >= 0, lineRange.location < attributedText.length else { continue }

            // Check if this line has a code background attribute
            var effectiveRange = NSRange(location: 0, length: 0)
            let charIndex = min(lineRange.location, attributedText.length - 1)
            if let bgColor = attributedText.attribute(.backgroundColor, at: charIndex, effectiveRange: &effectiveRange) as? PlatformColor,
               bgColor != PlatformColor.clear {

                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

                let origin = origins[lineIndex]
                // Convert from Core Text coordinates (origin at bottom-left of contentRect)
                let lineY = contentRect.origin.y + origin.y - descent
                let lineHeight = ascent + descent + leading

                let bgRect = CGRect(
                    x: contentRect.origin.x,
                    y: pageRect.height - lineY - lineHeight,
                    width: contentRect.width,
                    height: lineHeight
                )

                ctx.saveGState()
                #if canImport(UIKit)
                ctx.setFillColor(bgColor.cgColor)
                #else
                ctx.setFillColor(bgColor.cgColor)
                #endif
                ctx.fill(bgRect)
                ctx.restoreGState()
            }
        }
    }

    /// Draws image attachments that Core Text can't render natively.
    private static func drawImageAttachments(
        frame: CTFrame,
        attributedText: NSAttributedString,
        contentRect: CGRect,
        in ctx: CGContext,
        pageRect: CGRect
    ) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)

        for (lineIndex, line) in lines.enumerated() {
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            for run in runs {
                let runRange = CTRunGetStringRange(run)
                guard runRange.location >= 0, runRange.location < attributedText.length else { continue }

                let attrs = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
                guard let attachment = attrs[.attachment] as? NSTextAttachment,
                      let image = attachment.image else { continue }

                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let runWidth = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))

                let origin = origins[lineIndex]
                var runPosition = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &runPosition)

                let x = contentRect.origin.x + origin.x + runPosition.x
                // Core Text origin is bottom-left of contentRect
                let y = contentRect.origin.y + origin.y - descent

                let imageRect = CGRect(
                    x: x,
                    y: pageRect.height - y - ascent - descent,
                    width: runWidth,
                    height: ascent + descent
                )

                #if canImport(UIKit)
                if let cgImage = image.cgImage {
                    ctx.saveGState()
                    // Flip for image drawing
                    ctx.translateBy(x: imageRect.origin.x, y: imageRect.origin.y + imageRect.height)
                    ctx.scaleBy(x: 1.0, y: -1.0)
                    ctx.draw(cgImage, in: CGRect(origin: .zero, size: imageRect.size))
                    ctx.restoreGState()
                }
                #else
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ctx.saveGState()
                    ctx.translateBy(x: imageRect.origin.x, y: imageRect.origin.y + imageRect.height)
                    ctx.scaleBy(x: 1.0, y: -1.0)
                    ctx.draw(cgImage, in: CGRect(origin: .zero, size: imageRect.size))
                    ctx.restoreGState()
                }
                #endif
            }
        }
    }

    // MARK: - Watermark

    /// Draws the watermark text centered at the bottom of the page.
    private static func drawWatermark(in context: CGContext, pageRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: WatermarkStyle.fontSize),
            .foregroundColor: WatermarkStyle.color
        ]
        let watermark = NSAttributedString(string: WatermarkStyle.text, attributes: attributes)
        let size = watermark.size()

        let x = (pageRect.width - size.width) / 2
        let y = pageRect.height - WatermarkStyle.bottomMargin

        #if canImport(UIKit)
        // UIKit PDF context has top-left origin — draw directly
        watermark.draw(at: CGPoint(x: x, y: y))
        #else
        // AppKit uses flipped coordinates for PDF context — push graphics context and draw
        NSGraphicsContext.saveGraphicsState()
        if let nsContext = NSGraphicsContext(cgContext: context, flipped: true) {
            NSGraphicsContext.current = nsContext
            watermark.draw(at: CGPoint(x: x, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        #endif
    }

    // MARK: - Font Helpers

    private static func fontWithBoldTrait(_ font: PlatformFont) -> PlatformFont {
        #if canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitBold)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return font
        #elseif canImport(AppKit)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #endif
    }

    private static func fontWithItalicTrait(_ font: PlatformFont) -> PlatformFont {
        #if canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return font
        #elseif canImport(AppKit)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #endif
    }

    // MARK: - Text Extraction

    /// Extracts plain text from a node tree (for tables, alt text, etc.)
    private static func extractPlainText(from node: MarkdownNode) -> String {
        if let literal = node.literalText {
            return literal
        }
        return node.children.map { extractPlainText(from: $0) }.joined()
    }
}
