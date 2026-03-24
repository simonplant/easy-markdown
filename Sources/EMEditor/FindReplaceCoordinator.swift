/// Owns find/replace match highlighting per FEAT-075.
/// Extracted from TextViewCoordinator to isolate find/replace concerns.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// Custom attribute key for find match highlighting per FEAT-017.
private let findHighlightKey = NSAttributedString.Key("com.easymarkdown.findHighlight")

// MARK: - FindReplaceCoordinator

@MainActor
final class FindReplaceCoordinator {

    // MARK: - iOS

    #if canImport(UIKit)

    /// Applies find match highlighting to the text storage per FEAT-017.
    /// All matches get a subtle background. The current match gets a stronger highlight.
    func applyFindHighlights(_ matches: [FindMatch], currentIndex: Int?, in textView: UITextView) {
        let storage = textView.textStorage
        let fullText = textView.text ?? ""
        let fullNSRange = NSRange(location: 0, length: (fullText as NSString).length)

        // Clear previous highlights
        storage.beginEditing()
        storage.removeAttribute(findHighlightKey, range: fullNSRange)
        storage.removeAttribute(.backgroundColor, range: fullNSRange)

        // Apply highlights for all matches
        for (i, match) in matches.enumerated() {
            let nsRange = NSRange(match.range, in: fullText)
            let color: PlatformColor
            if i == currentIndex {
                color = PlatformColor.systemYellow.withAlphaComponent(0.5)
            } else {
                color = PlatformColor.systemYellow.withAlphaComponent(0.2)
            }
            storage.addAttribute(.backgroundColor, value: color, range: nsRange)
            storage.addAttribute(findHighlightKey, value: true, range: nsRange)
        }
        storage.endEditing()

        // Scroll to current match
        if let idx = currentIndex, idx < matches.count {
            let nsRange = NSRange(matches[idx].range, in: fullText)
            textView.scrollRangeToVisible(nsRange)
        }
    }

    // MARK: - macOS

    #elseif canImport(AppKit)

    /// Applies find match highlighting to the text storage per FEAT-017.
    /// All matches get a subtle background. The current match gets a stronger highlight.
    func applyFindHighlights(_ matches: [FindMatch], currentIndex: Int?, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullText = textView.string
        let fullNSRange = NSRange(location: 0, length: (fullText as NSString).length)

        // Clear previous highlights
        storage.beginEditing()
        storage.removeAttribute(findHighlightKey, range: fullNSRange)
        storage.removeAttribute(.backgroundColor, range: fullNSRange)

        // Apply highlights for all matches
        for (i, match) in matches.enumerated() {
            let nsRange = NSRange(match.range, in: fullText)
            let color: PlatformColor
            if i == currentIndex {
                color = PlatformColor.systemYellow.withAlphaComponent(0.5)
            } else {
                color = PlatformColor.systemYellow.withAlphaComponent(0.2)
            }
            storage.addAttribute(.backgroundColor, value: color, range: nsRange)
            storage.addAttribute(findHighlightKey, value: true, range: nsRange)
        }
        storage.endEditing()

        // Scroll to current match
        if let idx = currentIndex, idx < matches.count {
            let nsRange = NSRange(matches[idx].range, in: fullText)
            textView.scrollRangeToVisible(nsRange)
        }
    }

    #endif
}
