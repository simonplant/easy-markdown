/// Line ending style detected in a file per [D-FILE-3].
/// Preserved on save — never converted silently.
public enum LineEnding: String, Sendable {
    /// Unix-style line feed (default for new files).
    case lf = "\n"
    /// Windows-style carriage return + line feed.
    case crlf = "\r\n"

    /// Detects the dominant line ending in a string.
    /// Returns `.lf` if no line endings are present (default for new files).
    public static func detect(in text: String) -> LineEnding {
        var lfCount = 0
        var crlfCount = 0
        var previousWasCR = false

        for char in text {
            if char == "\r" {
                previousWasCR = true
            } else if char == "\n" {
                if previousWasCR {
                    crlfCount += 1
                } else {
                    lfCount += 1
                }
                previousWasCR = false
            } else {
                previousWasCR = false
            }
        }

        return crlfCount > lfCount ? .crlf : .lf
    }

    /// Normalizes text to use this line ending style.
    /// Converts all line endings to the target style.
    public func apply(to text: String) -> String {
        // First normalize everything to LF, then convert to target
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        switch self {
        case .lf:
            return normalized
        case .crlf:
            return normalized.replacingOccurrences(of: "\n", with: "\r\n")
        }
    }
}
