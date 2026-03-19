import Foundation
import EMCore
import os

/// Provides coordinated file reads and writes via NSFileCoordinator per [A-025].
///
/// All file I/O passes through this type to prevent data corruption when
/// iCloud, Dropbox, or other processes access the same file.
public enum CoordinatedFileAccess {

    private static let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "file-coordination"
    )

    /// Reads a file using NSFileCoordinator, validates UTF-8, and detects line endings.
    ///
    /// - Parameter url: The file URL to read.
    /// - Parameter presenter: An optional NSFilePresenter for coordination.
    /// - Returns: Validated file content with metadata.
    /// - Throws: `EMError.file` variants for access, encoding, or missing file errors.
    public static func read(
        from url: URL,
        presenter: NSFilePresenter? = nil
    ) throws -> FileContent {
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        var coordinationError: NSError?
        var result: Result<FileContent, Error>?

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { readURL in
            do {
                let data = try Data(contentsOf: readURL)
                let content = try FileValidator.validate(data: data, from: url)
                result = .success(content)
            } catch {
                result = .failure(error)
            }
        }

        if let coordinationError {
            logger.error("Coordination failed for read: \(coordinationError.localizedDescription)")
            throw EMError.file(.accessDenied(url: url))
        }

        guard let result else {
            throw EMError.file(.accessDenied(url: url))
        }

        return try result.get()
    }

    /// Writes text to a file using NSFileCoordinator with atomic write per [A-025], [A-026].
    ///
    /// Preserves the specified line ending style — text is converted to the
    /// target line ending before writing.
    ///
    /// - Parameters:
    ///   - text: The text content to write.
    ///   - url: The target file URL.
    ///   - lineEnding: The line ending style to use for the written file.
    ///   - presenter: An optional NSFilePresenter for coordination.
    /// - Throws: `EMError.file(.saveFailed)` if the write fails.
    public static func write(
        text: String,
        to url: URL,
        lineEnding: LineEnding = .lf,
        presenter: NSFilePresenter? = nil
    ) throws {
        let outputText = lineEnding.apply(to: text)
        guard let data = outputText.data(using: .utf8) else {
            throw EMError.file(.saveFailed(url: url, underlying: NSError(
                domain: "EMFile",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode text as UTF-8"]
            )))
        }

        let coordinator = NSFileCoordinator(filePresenter: presenter)
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            logger.error("Coordination failed for write: \(coordinationError.localizedDescription)")
            throw EMError.file(.saveFailed(url: url, underlying: coordinationError))
        }

        if let writeError {
            throw EMError.file(.saveFailed(url: url, underlying: writeError))
        }
    }
}
