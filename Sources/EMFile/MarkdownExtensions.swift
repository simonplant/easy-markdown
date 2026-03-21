import Foundation
import UniformTypeIdentifiers

/// Markdown file extension constants per [D-FILE-6].
///
/// These are the file extensions recognized as markdown files by the file picker
/// and file validation. The list matches the spec: .md, .markdown, .mdown, .mkd, .mkdn, .mdx.
public enum MarkdownExtensions {

    /// All recognized markdown file extensions (without leading dot).
    public static let all: [String] = [
        "md",
        "markdown",
        "mdown",
        "mkd",
        "mkdn",
        "mdx",
    ]

    /// Alias for `all`, used in drag-and-drop contexts for clarity.
    public static let fileExtensions: [String] = all

    /// UTTypes for all recognized markdown extensions, for use with UIDocumentPickerViewController.
    public static let utTypes: [UTType] = all.compactMap { ext in
        UTType(filenameExtension: ext)
    }

    /// Whether the given file URL has a recognized markdown extension.
    public static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return all.contains(ext)
    }
}
