import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMCore

@MainActor
@Suite("InlineDiffRenderer")
struct InlineDiffRendererTests {

    private func makeTextStorage(text: String) -> NSMutableAttributedString {
        let font = PlatformFont.systemFont(ofSize: 16)
        return NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: PlatformColor.black]
        )
    }

    private var baseFont: PlatformFont {
        PlatformFont.systemFont(ofSize: 16)
    }

    // MARK: - Apply Diff

    @Test("applyDiff adds strikethrough to original range")
    func applyDiffStrikethrough() {
        let storage = makeTextStorage(text: "Hello world, this is a test.")
        let range = NSRange(location: 0, length: 11) // "Hello world"

        InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "Greetings",
            baseFont: baseFont
        )

        // Check strikethrough on original text
        var effectiveRange = NSRange()
        let strikethrough = storage.attribute(
            .strikethroughStyle,
            at: 0,
            effectiveRange: &effectiveRange
        ) as? Int

        #expect(strikethrough == NSUnderlineStyle.single.rawValue)
    }

    @Test("applyDiff inserts suggestion text after original")
    func applyDiffInsertsSuggestion() {
        let storage = makeTextStorage(text: "Hello world.")
        let range = NSRange(location: 0, length: 11) // "Hello world"

        InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "Greetings",
            baseFont: baseFont
        )

        // Text should now contain the suggestion
        let fullText = storage.string
        #expect(fullText.contains("Greetings"))
    }

    @Test("applyDiff marks ranges with diff marker attribute")
    func applyDiffMarkers() {
        let storage = makeTextStorage(text: "Hello world.")
        let range = NSRange(location: 0, length: 11)

        InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "Greetings",
            baseFont: baseFont
        )

        // Check deletion marker on original
        let deletionMarker = storage.attribute(
            InlineDiffRenderer.diffMarkerKey,
            at: 0,
            effectiveRange: nil
        ) as? String
        #expect(deletionMarker == InlineDiffRenderer.diffDeletion)

        // Check insertion marker on suggestion
        let insertionStart = range.location + range.length
        let insertionMarker = storage.attribute(
            InlineDiffRenderer.diffMarkerKey,
            at: insertionStart,
            effectiveRange: nil
        ) as? String
        #expect(insertionMarker == InlineDiffRenderer.diffInsertion)
    }

    @Test("applyDiff with empty improved text only applies deletion styling")
    func applyDiffEmptyImproved() {
        let storage = makeTextStorage(text: "Hello world.")
        let range = NSRange(location: 0, length: 11)

        let resultRange = InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "",
            baseFont: baseFont
        )

        // Should only have original length (no insertion)
        #expect(resultRange.length == range.length)
        #expect(storage.string == "Hello world.")
    }

    // MARK: - Remove Diff

    @Test("removeDiff cleans up all diff markers and inserted text")
    func removeDiffCleanup() {
        let originalText = "Hello world."
        let storage = makeTextStorage(text: originalText)
        let range = NSRange(location: 0, length: 11)

        InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "Greetings",
            baseFont: baseFont
        )

        // Verify suggestion was inserted
        #expect(storage.string.contains("Greetings"))

        InlineDiffRenderer.removeDiff(from: storage)

        // After removal, the original text should be restored
        #expect(storage.string == originalText)

        // Strikethrough should be removed
        let strikethrough = storage.attribute(
            .strikethroughStyle,
            at: 0,
            effectiveRange: nil
        ) as? Int
        #expect(strikethrough == nil)
    }

    // MARK: - Update Diff

    @Test("updateDiff replaces old suggestion with new one")
    func updateDiff() {
        let storage = makeTextStorage(text: "Hello world.")
        let range = NSRange(location: 0, length: 11)

        InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "Hi",
            baseFont: baseFont
        )

        #expect(storage.string.contains("Hi"))

        // Update with longer text (simulating streaming)
        InlineDiffRenderer.updateDiff(
            in: storage,
            originalRange: range,
            improvedText: "Hi there, everyone",
            baseFont: baseFont
        )

        #expect(storage.string.contains("Hi there, everyone"))
        // Old short suggestion should be replaced
        let fullText = storage.string
        let hiCount = fullText.components(separatedBy: "Hi").count - 1
        // "Hi" appears once in "Hi there, everyone"
        #expect(hiCount == 1)
    }

    @Test("updateDiff with empty text removes suggestion")
    func updateDiffEmpty() {
        let storage = makeTextStorage(text: "Hello world.")
        let range = NSRange(location: 0, length: 11)

        InlineDiffRenderer.applyDiff(
            to: storage,
            originalRange: range,
            originalText: "Hello world",
            improvedText: "Greetings",
            baseFont: baseFont
        )

        InlineDiffRenderer.updateDiff(
            in: storage,
            originalRange: range,
            improvedText: "",
            baseFont: baseFont
        )

        // Only original text should remain (with deletion styling)
        #expect(!storage.string.contains("Greetings"))
    }
}
