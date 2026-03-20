/// Grapheme-cluster-aware text utilities per FEAT-051.
///
/// Ensures correct handling of multi-codepoint characters (emoji with skin tones,
/// flags, ZWJ sequences) and CJK/RTL text across the editor. Swift's `Character`
/// type already represents extended grapheme clusters, but these utilities provide
/// a safe API for operations that cross between `String.Index` and `NSRange`
/// (UTF-16) boundaries.

import Foundation

/// Utilities for grapheme-cluster-safe text operations per FEAT-051.
public enum GraphemeClusterHelper {

    /// Snaps a UTF-16 offset to the nearest grapheme cluster boundary.
    ///
    /// If the offset falls in the middle of a multi-codepoint character
    /// (e.g., a flag emoji or ZWJ sequence), this returns the offset of the
    /// start of that grapheme cluster. This prevents splitting emoji or
    /// combining character sequences.
    ///
    /// - Parameters:
    ///   - utf16Offset: A UTF-16 offset into the string.
    ///   - text: The string to operate on.
    /// - Returns: The UTF-16 offset snapped to the nearest grapheme cluster start.
    public static func snapToGraphemeClusterBoundary(
        utf16Offset: Int,
        in text: String
    ) -> Int {
        guard !text.isEmpty else { return 0 }
        let clamped = max(0, min(utf16Offset, text.utf16.count))

        // If at start or end, already on a boundary
        guard clamped > 0, clamped < text.utf16.count else { return clamped }

        // Get the String.Index at this UTF-16 offset
        guard let idx = text.utf16.index(
            text.startIndex,
            offsetBy: clamped,
            limitedBy: text.endIndex
        ) else {
            return snapByScanning(utf16Offset: clamped, in: text)
        }

        // Find the composed character sequence (grapheme cluster) containing this index.
        // This handles surrogate pairs, combining marks, ZWJ sequences, etc.
        let clusterRange = text.rangeOfComposedCharacterSequence(at: idx)
        return text.utf16.distance(from: text.startIndex, to: clusterRange.lowerBound)
    }

    /// Scans the string to find the grapheme cluster boundary at or before the offset.
    private static func snapByScanning(utf16Offset: Int, in text: String) -> Int {
        var currentOffset = 0
        for index in text.indices {
            let nextIndex = text.index(after: index)
            let nextOffset = text.utf16.distance(from: text.startIndex, to: nextIndex)
            if nextOffset > utf16Offset {
                return currentOffset
            }
            currentOffset = nextOffset
        }
        return text.utf16.count
    }

    /// Returns the UTF-16 length of the grapheme cluster at the given offset.
    ///
    /// Useful for determining the correct cursor movement distance when
    /// stepping over multi-codepoint characters.
    ///
    /// - Parameters:
    ///   - utf16Offset: A UTF-16 offset at the start of a grapheme cluster.
    ///   - text: The string to operate on.
    /// - Returns: The UTF-16 width of the grapheme cluster, or 0 if at end of string.
    public static func graphemeClusterUTF16Width(
        at utf16Offset: Int,
        in text: String
    ) -> Int {
        guard utf16Offset >= 0, utf16Offset < text.utf16.count else { return 0 }

        guard let idx = text.utf16.index(
            text.startIndex,
            offsetBy: utf16Offset,
            limitedBy: text.endIndex
        ) else {
            return 0
        }

        // Find the Character (grapheme cluster) containing this index
        let charStart = text.rangeOfComposedCharacterSequence(at: idx)
        return text.utf16.distance(from: charStart.lowerBound, to: charStart.upperBound)
    }

    /// Checks whether a UTF-16 offset falls on a grapheme cluster boundary.
    ///
    /// - Parameters:
    ///   - utf16Offset: The offset to check.
    ///   - text: The string to check against.
    /// - Returns: `true` if the offset is at the start of a grapheme cluster (or at string boundaries).
    public static func isGraphemeClusterBoundary(
        utf16Offset: Int,
        in text: String
    ) -> Bool {
        guard !text.isEmpty else { return utf16Offset == 0 }
        guard utf16Offset > 0, utf16Offset < text.utf16.count else {
            return utf16Offset == 0 || utf16Offset == text.utf16.count
        }

        let snapped = snapToGraphemeClusterBoundary(utf16Offset: utf16Offset, in: text)
        return snapped == utf16Offset
    }

    /// Iterates grapheme clusters in the string, calling the closure with
    /// each cluster's UTF-16 range.
    ///
    /// This is useful for building offset tables that respect grapheme boundaries.
    ///
    /// - Parameters:
    ///   - text: The string to iterate.
    ///   - body: Closure called with (grapheme cluster as String, UTF-16 offset, UTF-16 length).
    public static func enumerateGraphemeClusters(
        in text: String,
        body: (String, Int, Int) -> Bool
    ) {
        var utf16Offset = 0
        for index in text.indices {
            let nextIndex = text.index(after: index)
            let cluster = String(text[index..<nextIndex])
            let width = text.utf16.distance(from: index, to: nextIndex)
            if !body(cluster, utf16Offset, width) {
                return
            }
            utf16Offset += width
        }
    }
}
