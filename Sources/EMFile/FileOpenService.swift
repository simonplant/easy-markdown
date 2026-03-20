import Foundation
import EMCore
import os

/// Result of opening a file, containing validated content and metadata.
public struct FileOpenResult: Sendable {
    /// The validated file content (UTF-8 text, line ending, size, URL).
    public let content: FileContent

    /// Security-scoped bookmark data for persistent access.
    public let bookmarkData: Data

    /// Whether the file exceeds the large file threshold (>1MB) per [D-FILE-4].
    public let isLargeFile: Bool
}

/// Orchestrates the file open flow per FEAT-001 and [A-024], [A-025].
///
/// Ties together scoped access, coordinated read, UTF-8 validation, and bookmark
/// persistence into a single high-level API. Callers get a validated `FileOpenResult`
/// or an `EMError`.
@MainActor
public final class FileOpenService {

    private let bookmarkManager: BookmarkManager
    private let scopedAccessManager: ScopedAccessManager
    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "file-open"
    )

    /// Creates a file open service.
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

    /// Opens a file from a URL (typically from UIDocumentPickerViewController).
    ///
    /// Flow:
    /// 1. Start security-scoped access
    /// 2. Read via NSFileCoordinator + validate UTF-8 per [D-FILE-2]
    /// 3. Save security-scoped bookmark for persistent access per [A-024]
    /// 4. Return result with large file flag per [D-FILE-4]
    ///
    /// - Parameter url: The security-scoped URL from the file picker or bookmark resolution.
    /// - Returns: A validated `FileOpenResult`.
    /// - Throws: `EMError.file(.notUTF8)` for non-UTF-8 files,
    ///           `EMError.file(.accessDenied)` for permission failures.
    public func open(url: URL) throws -> FileOpenResult {
        logger.info("Opening file: \(url.lastPathComponent, privacy: .public)")

        // 1. Start security-scoped access
        scopedAccessManager.startAccessing(url)

        // 2. Read and validate via coordinated access
        let content: FileContent
        do {
            content = try CoordinatedFileAccess.read(from: url)
        } catch {
            // If read fails, stop scoped access to avoid leaking
            scopedAccessManager.stopAccessing(url)
            throw error
        }

        // 3. Save bookmark for persistent access
        let bookmarkData: Data
        do {
            bookmarkData = try bookmarkManager.saveBookmark(for: url)
        } catch {
            // Bookmark failure is non-fatal — file is still open and readable.
            // Log and continue with empty bookmark data.
            logger.error("Failed to save bookmark, file is still accessible: \(error.localizedDescription, privacy: .public)")
            bookmarkData = Data()
        }

        // 4. Check large file threshold
        let isLarge = FileValidator.isLargeFile(sizeBytes: content.fileSize)
        if isLarge {
            logger.info("Large file warning: \(content.fileSize) bytes")
        }

        logger.info("File opened successfully: \(url.lastPathComponent, privacy: .public) (\(content.fileSize) bytes)")

        return FileOpenResult(
            content: content,
            bookmarkData: bookmarkData,
            isLargeFile: isLarge
        )
    }

    /// Opens a file from a previously saved bookmark (state restoration, recents).
    ///
    /// Resolves the bookmark to a URL, then delegates to `open(url:)`.
    ///
    /// - Parameter bookmarkData: The persisted bookmark data.
    /// - Returns: A validated `FileOpenResult`.
    /// - Throws: `EMError.file(.bookmarkStale)` if resolution fails,
    ///           plus any errors from `open(url:)`.
    public func open(fromBookmark bookmarkData: Data) throws -> FileOpenResult {
        let url = try bookmarkManager.resolveBookmark(bookmarkData)
        return try open(url: url)
    }

    /// Closes access to a file, releasing the security-scoped resource.
    ///
    /// Must be called when the editor closes a file to balance `startAccessing`.
    /// - Parameter url: The file URL to stop accessing.
    public func close(url: URL) {
        scopedAccessManager.stopAccessing(url)
        logger.info("Closed file: \(url.lastPathComponent, privacy: .public)")
    }
}
