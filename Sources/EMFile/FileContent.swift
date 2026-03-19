import Foundation
import EMCore

/// Result of reading a file from disk.
/// Contains the validated text content along with detected metadata.
public struct FileContent: Sendable {
    /// The raw text content (guaranteed valid UTF-8).
    public let text: String
    /// The detected line ending style.
    public let lineEnding: LineEnding
    /// The file size in bytes.
    public let fileSize: Int
    /// The source URL.
    public let url: URL
}
