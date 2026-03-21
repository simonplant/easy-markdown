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
@Suite("GhostTextRenderer")
struct GhostTextRendererTests {

    private let baseFont = PlatformFont.systemFont(ofSize: 16)

    private func makeStorage(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: [.font: PlatformFont.systemFont(ofSize: 16), .foregroundColor: PlatformColor.black]
        )
    }

    // MARK: - Insert

    @Test("insertGhostText adds ghost text at position")
    func insertAtPosition() {
        let storage = makeStorage("Hello world")
        let range = GhostTextRenderer.insertGhostText(
            in: storage,
            at: 11,
            ghostText: " and goodbye",
            baseFont: baseFont
        )

        #expect(range.location == 11)
        #expect(range.length == " and goodbye".utf16.count)
        #expect(storage.string == "Hello world and goodbye")
    }

    @Test("insertGhostText with empty text returns zero-length range")
    func insertEmpty() {
        let storage = makeStorage("Hello")
        let range = GhostTextRenderer.insertGhostText(
            in: storage,
            at: 5,
            ghostText: "",
            baseFont: baseFont
        )

        #expect(range.length == 0)
        #expect(storage.string == "Hello")
    }

    @Test("insertGhostText applies ghost marker attribute")
    func insertAppliesMarker() {
        let storage = makeStorage("Hello")
        GhostTextRenderer.insertGhostText(
            in: storage,
            at: 5,
            ghostText: " world",
            baseFont: baseFont
        )

        let ghostRange = NSRange(location: 5, length: 6)
        var foundMarker = false
        storage.enumerateAttribute(
            GhostTextRenderer.ghostTextMarkerKey,
            in: ghostRange,
            options: []
        ) { value, _, _ in
            if let marker = value as? String, marker == "ghostText" {
                foundMarker = true
            }
        }

        #expect(foundMarker)
    }

    // MARK: - Remove

    @Test("removeGhostText removes inserted ghost text")
    func removeGhostText() {
        let storage = makeStorage("Hello")
        GhostTextRenderer.insertGhostText(
            in: storage,
            at: 5,
            ghostText: " world",
            baseFont: baseFont
        )

        #expect(storage.string == "Hello world")

        GhostTextRenderer.removeGhostText(from: storage)

        #expect(storage.string == "Hello")
    }

    @Test("removeGhostText is a no-op when no ghost text exists")
    func removeWhenNone() {
        let storage = makeStorage("Hello world")

        GhostTextRenderer.removeGhostText(from: storage)

        #expect(storage.string == "Hello world")
    }

    // MARK: - Update

    @Test("updateGhostText replaces existing ghost text")
    func updateReplacesExisting() {
        let storage = makeStorage("Hello")
        GhostTextRenderer.insertGhostText(
            in: storage,
            at: 5,
            ghostText: " wor",
            baseFont: baseFont
        )

        #expect(storage.string == "Hello wor")

        GhostTextRenderer.updateGhostText(
            in: storage,
            at: 5,
            ghostText: " world!",
            baseFont: baseFont
        )

        #expect(storage.string == "Hello world!")
    }

    // MARK: - Has Ghost Text

    @Test("hasGhostText returns true when ghost text is present")
    func hasGhostTextTrue() {
        let storage = makeStorage("Hello")
        GhostTextRenderer.insertGhostText(
            in: storage,
            at: 5,
            ghostText: " world",
            baseFont: baseFont
        )

        #expect(GhostTextRenderer.hasGhostText(in: storage))
    }

    @Test("hasGhostText returns false when no ghost text")
    func hasGhostTextFalse() {
        let storage = makeStorage("Hello world")
        #expect(!GhostTextRenderer.hasGhostText(in: storage))
    }

    // MARK: - Ghost Text Content

    @Test("ghostTextContent returns the ghost text string")
    func ghostTextContent() {
        let storage = makeStorage("Hello")
        GhostTextRenderer.insertGhostText(
            in: storage,
            at: 5,
            ghostText: " world",
            baseFont: baseFont
        )

        let content = GhostTextRenderer.ghostTextContent(in: storage)
        #expect(content == " world")
    }

    @Test("ghostTextContent returns nil when no ghost text")
    func ghostTextContentNil() {
        let storage = makeStorage("Hello")
        let content = GhostTextRenderer.ghostTextContent(in: storage)
        #expect(content == nil)
    }
}
