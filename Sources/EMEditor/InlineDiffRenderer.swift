/// Renders inline diff preview in the text view per FEAT-011.
/// Shows original text with strikethrough and suggestion in green per AC-5.
/// Updates progressively as tokens stream in per AC-8.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// Renders inline diff attributes onto a text storage for AI improve preview.
/// The diff is displayed inline: original with strikethrough (red), then
/// the improved text in green. Both are clearly distinguishable per AC-5.
public struct InlineDiffRenderer {

    // MARK: - Diff Colors

    /// Color for the original text (strikethrough).
    private static var deletionColor: PlatformColor {
        PlatformColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1.0)
    }

    /// Color for the suggested replacement text.
    private static var insertionColor: PlatformColor {
        PlatformColor(red: 0.15, green: 0.65, blue: 0.25, alpha: 1.0)
    }

    /// Background highlight for the suggestion text.
    private static var insertionBackground: PlatformColor {
        PlatformColor(red: 0.15, green: 0.65, blue: 0.25, alpha: 0.1)
    }

    /// Background highlight for the original (deleted) text.
    private static var deletionBackground: PlatformColor {
        PlatformColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 0.1)
    }

    // MARK: - Custom attribute keys

    /// Marks a range as part of the AI diff preview (for cleanup).
    static let diffMarkerKey = NSAttributedString.Key("em.aiDiffMarker")
    /// Value indicating deletion (original text).
    static let diffDeletion = "deletion"
    /// Value indicating insertion (suggested text).
    static let diffInsertion = "insertion"

    // MARK: - Rendering

    /// Applies inline diff styling to the text storage.
    /// Replaces the original selection range with styled original + suggestion.
    ///
    /// The rendered diff looks like:
    /// ~~original text~~ improved text
    ///
    /// - Parameters:
    ///   - textStorage: The text storage to modify.
    ///   - originalRange: The NSRange of the original selected text.
    ///   - originalText: The original text content.
    ///   - improvedText: The improved text from AI (may be partial during streaming).
    ///   - baseFont: The base font for the text.
    /// - Returns: The NSRange covering the entire diff region (original + suggestion).
    @discardableResult
    public static func applyDiff(
        to textStorage: NSMutableAttributedString,
        originalRange: NSRange,
        originalText: String,
        improvedText: String,
        baseFont: PlatformFont
    ) -> NSRange {
        // First, remove any existing diff markers in the text storage
        removeDiff(from: textStorage)

        // Apply strikethrough + red to the original text
        let deletionAttrs: [NSAttributedString.Key: Any] = [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: deletionColor,
            .foregroundColor: deletionColor,
            .backgroundColor: deletionBackground,
            diffMarkerKey: diffDeletion,
        ]
        textStorage.addAttributes(deletionAttrs, range: originalRange)

        // Insert the improved text right after the original
        let insertionPoint = originalRange.location + originalRange.length

        guard !improvedText.isEmpty else {
            return originalRange
        }

        // Build the insertion string with attributes
        let separator = " "
        let insertionString = separator + improvedText
        let insertionAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: insertionColor,
            .backgroundColor: insertionBackground,
            .font: baseFont,
            diffMarkerKey: diffInsertion,
        ]

        let attributedInsertion = NSAttributedString(
            string: insertionString,
            attributes: insertionAttrs
        )

        textStorage.insert(attributedInsertion, at: insertionPoint)

        // Return the range covering both original + insertion
        let totalLength = originalRange.length + insertionString.utf16.count
        return NSRange(location: originalRange.location, length: totalLength)
    }

    /// Removes all diff markers and inserted suggestion text from the text storage.
    /// Restores the text storage to its pre-diff state.
    public static func removeDiff(from textStorage: NSMutableAttributedString) {
        // Remove inserted suggestion text (marked as insertion)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var insertionRanges: [NSRange] = []

        textStorage.enumerateAttribute(
            diffMarkerKey,
            in: fullRange,
            options: .reverse
        ) { value, range, _ in
            if let marker = value as? String, marker == diffInsertion {
                insertionRanges.append(range)
            }
        }

        // Remove insertion ranges in reverse order to preserve indices
        for range in insertionRanges {
            textStorage.deleteCharacters(in: range)
        }

        // Remove deletion styling from original text
        let updatedRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(
            diffMarkerKey,
            in: updatedRange,
            options: []
        ) { value, range, _ in
            if let marker = value as? String, marker == diffDeletion {
                textStorage.removeAttribute(.strikethroughStyle, range: range)
                textStorage.removeAttribute(.strikethroughColor, range: range)
                textStorage.removeAttribute(.backgroundColor, range: range)
                textStorage.removeAttribute(diffMarkerKey, range: range)
                // Note: foreground color will be restored by the next render pass
            }
        }
    }

    /// Updates the suggestion text in an active diff (for streaming updates).
    /// Removes the old insertion and re-inserts with the updated text.
    ///
    /// - Parameters:
    ///   - textStorage: The text storage to modify.
    ///   - originalRange: The NSRange of the original text (with deletion styling).
    ///   - improvedText: The updated improved text (accumulated tokens so far).
    ///   - baseFont: The base font for the text.
    /// - Returns: The NSRange covering the entire diff region.
    @discardableResult
    public static func updateDiff(
        in textStorage: NSMutableAttributedString,
        originalRange: NSRange,
        improvedText: String,
        baseFont: PlatformFont
    ) -> NSRange {
        // Remove existing insertion text
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var insertionRanges: [NSRange] = []

        textStorage.enumerateAttribute(
            diffMarkerKey,
            in: fullRange,
            options: .reverse
        ) { value, range, _ in
            if let marker = value as? String, marker == diffInsertion {
                insertionRanges.append(range)
            }
        }

        for range in insertionRanges {
            textStorage.deleteCharacters(in: range)
        }

        // Re-insert updated suggestion text
        let insertionPoint = originalRange.location + originalRange.length

        guard !improvedText.isEmpty else {
            return originalRange
        }

        let separator = " "
        let insertionString = separator + improvedText
        let insertionAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: insertionColor,
            .backgroundColor: insertionBackground,
            .font: baseFont,
            diffMarkerKey: diffInsertion,
        ]

        let attributedInsertion = NSAttributedString(
            string: insertionString,
            attributes: insertionAttrs
        )

        textStorage.insert(attributedInsertion, at: insertionPoint)

        let totalLength = originalRange.length + insertionString.utf16.count
        return NSRange(location: originalRange.location, length: totalLength)
    }
}
