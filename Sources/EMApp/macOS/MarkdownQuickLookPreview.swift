#if os(macOS)
import AppKit
import QuickLookUI

/// Quick Look preview controller for .md files in Finder per FEAT-021 AC-3.
/// Renders markdown as styled HTML for preview display.
///
/// To deploy: create a Quick Look Preview Extension target in Xcode that references this class,
/// and register it for UTI `net.daringfireball.markdown` (and custom .mdx, .mdown, .mkd, .mkdn)
/// in the extension's Info.plist.
///
/// This controller is designed to be embedded in a QLPreviewingController conformance:
/// ```swift
/// class PreviewViewController: NSViewController, QLPreviewingController {
///     func preparePreviewOfFile(at url: URL) async throws {
///         let preview = MarkdownQuickLookPreview()
///         let htmlView = try preview.createPreviewView(for: url, frame: view.bounds)
///         view.addSubview(htmlView)
///     }
/// }
/// ```
@MainActor
public final class MarkdownQuickLookPreview {
    /// Creates an NSView containing the rendered markdown preview.
    ///
    /// - Parameters:
    ///   - url: The markdown file URL.
    ///   - frame: The frame for the preview view.
    /// - Returns: An NSView rendering the markdown content.
    public func createPreviewView(for url: URL, frame: NSRect) throws -> NSView {
        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "com.easymarkdown.quicklook",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File is not valid UTF-8"]
            )
        }

        let html = renderMarkdownToHTML(markdown)

        let scrollView = NSScrollView(frame: frame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = NSTextView(frame: frame)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 24, height: 24)

        // Use attributed string rendering for styled preview
        if let htmlData = html.data(using: .utf8),
           let attributedString = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
           ) {
            textView.textStorage?.setAttributedString(attributedString)
        } else {
            // Fallback: plain text
            textView.string = markdown
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }

        scrollView.documentView = textView
        return scrollView
    }

    /// Renders markdown text to styled HTML for Quick Look preview.
    /// Uses a minimal CSS stylesheet that matches the app's default theme.
    private func renderMarkdownToHTML(_ markdown: String) -> String {
        // Convert basic markdown to HTML using simple pattern matching.
        // This is intentionally lightweight for Quick Look — the full parser
        // lives in EMParser and is not available in the QL extension context.
        var html = escapeHTML(markdown)

        // Headings
        html = html.replacingOccurrences(
            of: #"(?m)^######\s+(.+)$"#,
            with: "<h6>$1</h6>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^#####\s+(.+)$"#,
            with: "<h5>$1</h5>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^####\s+(.+)$"#,
            with: "<h4>$1</h4>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^###\s+(.+)$"#,
            with: "<h3>$1</h3>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^##\s+(.+)$"#,
            with: "<h2>$1</h2>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^#\s+(.+)$"#,
            with: "<h1>$1</h1>",
            options: .regularExpression
        )

        // Bold and italic
        html = html.replacingOccurrences(
            of: #"\*\*\*(.+?)\*\*\*"#,
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Inline code
        html = html.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Line breaks → paragraphs (simple: double newline = paragraph break)
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = "<p>" + html + "</p>"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: #333;
            max-width: 700px;
            margin: 0 auto;
            padding: 20px;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #ddd; background: #1e1e1e; }
            code { background: #2d2d2d; }
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.2em;
            margin-bottom: 0.6em;
        }
        h1 { font-size: 1.8em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.3em; }
        code {
            background: #f0f0f0;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: Menlo, monospace;
            font-size: 0.9em;
        }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    /// Escapes HTML special characters in the source markdown.
    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
#endif
