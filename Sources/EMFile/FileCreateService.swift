import Foundation
import EMCore
import os

/// Result of creating a file, containing the written content and metadata.
public struct FileCreateResult: Sendable {
    /// The file content that was written (empty text, LF line endings).
    public let content: FileContent

    /// Security-scoped bookmark data for persistent access.
    public let bookmarkData: Data
}

/// Orchestrates the file creation flow per FEAT-002 and [A-024], [A-025].
///
/// Creates a new empty .md file at a user-chosen location via the system save picker.
/// Uses atomic writes to ensure no corrupt or empty file is left behind on failure.
/// All new files use LF line endings per spec.
@MainActor
public final class FileCreateService {

    private let bookmarkManager: BookmarkManager
    private let scopedAccessManager: ScopedAccessManager
    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "file-create"
    )

    /// Creates a file create service.
    /// - Parameters:
    ///   - bookmarkManager: Manages security-scoped bookmark persistence.
    ///   - scopedAccessManager: Manages balanced start/stop of scoped access.
    public init(
        bookmarkManager: BookmarkManager = BookmarkManager(),
        scopedAccessManager: ScopedAccessManager = ScopedAccessManager()
    ) {
        self.bookmarkManager = bookmarkManager
        self.scopedAccessManager = scopedAccessManager
    }

    /// Creates a new empty markdown file at the given URL.
    ///
    /// Flow:
    /// 1. Start security-scoped access
    /// 2. Write empty content with LF line endings via NSFileCoordinator per [A-025]
    /// 3. Save security-scoped bookmark for persistent access per [A-024]
    /// 4. Return result with file content ready for editing
    ///
    /// The write is atomic — if it fails (disk full, permissions), no corrupt or
    /// empty file is left behind per AC-5.
    ///
    /// - Parameter url: The URL chosen by the user in the save picker.
    /// - Returns: A `FileCreateResult` with the created file's content and bookmark.
    /// - Throws: `EMError.file(.saveFailed)` if the write fails,
    ///           `EMError.file(.accessDenied)` if permissions are denied.
    public func create(at url: URL) throws -> FileCreateResult {
        logger.info("Creating file: \(url.lastPathComponent, privacy: .public)")

        // 1. Start security-scoped access
        scopedAccessManager.startAccessing(url)

        // 2. Write empty content with LF line endings
        do {
            try CoordinatedFileAccess.write(
                text: "",
                to: url,
                lineEnding: .lf
            )
        } catch {
            // Write failed — stop scoped access to avoid leaking
            scopedAccessManager.stopAccessing(url)
            throw error
        }

        // 3. Save bookmark for persistent access
        let bookmarkData: Data
        do {
            bookmarkData = try bookmarkManager.saveBookmark(for: url)
        } catch {
            // Bookmark failure is non-fatal — file is created and accessible.
            logger.error("Failed to save bookmark, file is still accessible: \(error.localizedDescription, privacy: .public)")
            bookmarkData = Data()
        }

        let content = FileContent(
            text: "",
            lineEnding: .lf,
            fileSize: 0,
            url: url
        )

        logger.info("File created successfully: \(url.lastPathComponent, privacy: .public)")

        return FileCreateResult(
            content: content,
            bookmarkData: bookmarkData
        )
    }

    /// Releases security-scoped access for a created file.
    ///
    /// Must be called when the editor closes the file to balance `startAccessing`.
    /// - Parameter url: The file URL to stop accessing.
    public func close(url: URL) {
        scopedAccessManager.stopAccessing(url)
        logger.info("Closed created file: \(url.lastPathComponent, privacy: .public)")
    }
}
