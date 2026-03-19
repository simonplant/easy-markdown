import Foundation
import EMCore

/// Validates file data before loading into the editor per [D-FILE-2], [D-FILE-3], [D-FILE-4].
public enum FileValidator {

    /// Threshold in bytes above which a file size warning is emitted per [D-FILE-4].
    public static let largeSizeThreshold = 1_000_000 // 1 MB

    /// Validates raw file data and produces a `FileContent` value.
    ///
    /// - Throws: `EMError.file(.notUTF8)` if the data is not valid UTF-8.
    /// - Returns: Validated content with detected line ending and size.
    public static func validate(data: Data, from url: URL) throws -> FileContent {
        guard let text = String(data: data, encoding: .utf8) else {
            throw EMError.file(.notUTF8(url: url))
        }

        let lineEnding = LineEnding.detect(in: text)

        return FileContent(
            text: text,
            lineEnding: lineEnding,
            fileSize: data.count,
            url: url
        )
    }

    /// Whether the file size exceeds the large file threshold per [D-FILE-4].
    public static func isLargeFile(sizeBytes: Int) -> Bool {
        sizeBytes > largeSizeThreshold
    }
}
