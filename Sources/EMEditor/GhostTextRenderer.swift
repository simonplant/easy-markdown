/// Renders ghost text (AI continuation suggestion) inline at the cursor per FEAT-056.
/// Ghost text appears dimmed at the cursor position. Tab accepts, typing dismisses.
/// Must not trigger auto-formatting rules per AC-6.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// Renders and removes ghost text in the text storage per FEAT-056.
public struct GhostTextRenderer {

    // MARK: - Ghost Text Styling

    /// Dimmed color for the ghost text suggestion.
    private static var ghostColor: PlatformColor {
        PlatformColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.6)
    }

    // MARK: - Custom attribute key

    /// Marks a range as ghost text (for cleanup and identification).
    public static let ghostTextMarkerKey = NSAttributedString.Key("em.ghostTextMarker")
    /// Value indicating this range is ghost text.
    static let ghostTextValue = "ghostText"

    // MARK: - Rendering

    /// Inserts ghost text at the given position in the text storage.
    ///
    /// - Parameters:
    ///   - textStorage: The text storage to modify.
    ///   - position: The character index where ghost text should appear.
    ///   - ghostText: The AI-generated continuation text.
    ///   - baseFont: The base font for the text.
    /// - Returns: The NSRange of the inserted ghost text.
    @discardableResult
    public static func insertGhostText(
        in textStorage: NSMutableAttributedString,
        at position: Int,
        ghostText: String,
        baseFont: PlatformFont
    ) -> NSRange {
        guard !ghostText.isEmpty else {
            return NSRange(location: position, length: 0)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: ghostColor,
            .font: baseFont,
            ghostTextMarkerKey: ghostTextValue,
        ]

        let attributedGhost = NSAttributedString(
            string: ghostText,
            attributes: attrs
        )

        textStorage.insert(attributedGhost, at: position)

        return NSRange(location: position, length: ghostText.utf16.count)
    }

    /// Updates ghost text content at the cursor position.
    /// Removes existing ghost text and inserts the updated version.
    ///
    /// - Parameters:
    ///   - textStorage: The text storage to modify.
    ///   - position: The character index where ghost text should appear.
    ///   - ghostText: The updated ghost text (accumulated tokens so far).
    ///   - baseFont: The base font for the text.
    /// - Returns: The NSRange of the updated ghost text.
    @discardableResult
    public static func updateGhostText(
        in textStorage: NSMutableAttributedString,
        at position: Int,
        ghostText: String,
        baseFont: PlatformFont
    ) -> NSRange {
        removeGhostText(from: textStorage)
        return insertGhostText(in: textStorage, at: position, ghostText: ghostText, baseFont: baseFont)
    }

    /// Removes all ghost text from the text storage.
    /// Returns the text to its pre-ghost state.
    public static func removeGhostText(from textStorage: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var ghostRanges: [NSRange] = []

        textStorage.enumerateAttribute(
            ghostTextMarkerKey,
            in: fullRange,
            options: .reverse
        ) { value, range, _ in
            if let marker = value as? String, marker == ghostTextValue {
                ghostRanges.append(range)
            }
        }

        // Remove in reverse order to preserve indices
        for range in ghostRanges {
            textStorage.deleteCharacters(in: range)
        }
    }

    /// Checks whether the text storage currently contains ghost text.
    public static func hasGhostText(in textStorage: NSMutableAttributedString) -> Bool {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var found = false

        textStorage.enumerateAttribute(
            ghostTextMarkerKey,
            in: fullRange,
            options: []
        ) { value, _, stop in
            if let marker = value as? String, marker == ghostTextValue {
                found = true
                stop.pointee = true
            }
        }

        return found
    }

    /// Returns the ghost text content if present, nil otherwise.
    public static func ghostTextContent(in textStorage: NSMutableAttributedString) -> String? {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var content: String?

        textStorage.enumerateAttribute(
            ghostTextMarkerKey,
            in: fullRange,
            options: []
        ) { value, range, stop in
            if let marker = value as? String, marker == ghostTextValue {
                content = textStorage.attributedSubstring(from: range).string
                stop.pointee = true
            }
        }

        return content
    }
}
