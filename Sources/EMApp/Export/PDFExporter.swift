import Foundation
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// Renders markdown text to PDF data with optional watermark per [A-056] and FEAT-061.
///
/// The watermark is a subtle "Made with easy-markdown" footer in small, light-gray text.
/// It appears on every page when enabled.
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
    }

    /// Generates PDF data from the given text content.
    ///
    /// - Parameters:
    ///   - text: The markdown text to render.
    ///   - includeWatermark: Whether to draw the footer watermark.
    /// - Returns: The rendered PDF as `Data`.
    static func exportPDF(text: String, includeWatermark: Bool) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: PageLayout.width, height: PageLayout.height)
        let contentRect = pageRect.insetBy(dx: PageLayout.contentMargin, dy: PageLayout.contentMargin)
        let attributedText = makeAttributedString(from: text)

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

    // MARK: - Platform Rendering

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
            renderPages(
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
        renderPages(
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

    // MARK: - Shared Rendering Logic

    private static func renderPages(
        attributedText: NSAttributedString,
        pageRect: CGRect,
        contentRect: CGRect,
        includeWatermark: Bool,
        beginPage: () -> Void,
        cgContext: () -> CGContext,
        endPage: (() -> Void)? = nil
    ) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        var currentIndex = 0
        let totalLength = attributedText.length

        while currentIndex < totalLength {
            beginPage()
            let ctx = cgContext()

            let remainingRange = CFRange(location: currentIndex, length: totalLength - currentIndex)
            let path = CGPath(rect: contentRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, remainingRange, path, nil)

            // Flip coordinate system for Core Text rendering
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageRect.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()

            if includeWatermark {
                drawWatermark(in: ctx, pageRect: pageRect)
            }

            endPage?()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentIndex += visibleRange.length

            // Safety: if no characters were laid out, break to prevent infinite loop
            if visibleRange.length == 0 { break }
        }

        // Handle empty documents — still produce one page
        if totalLength == 0 {
            beginPage()
            if includeWatermark {
                drawWatermark(in: cgContext(), pageRect: pageRect)
            }
            endPage?()
        }
    }

    // MARK: - Private

    private static func makeAttributedString(from text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12),
            .foregroundColor: PlatformColor.black,
            .paragraphStyle: style
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

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
}
