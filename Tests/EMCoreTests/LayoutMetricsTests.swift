import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMCore

@Suite("LayoutMetrics")
struct LayoutMetricsTests {

    // MARK: - Line Height

    @Test("Line height multiplier produces 1.5-1.7x body font size")
    func lineHeightMultiplierRange() {
        let metrics = LayoutMetrics.iPhone
        // Multiplier should be in the 1.5-1.7 range per AC-4
        #expect(metrics.lineHeightMultiplier >= 1.5)
        #expect(metrics.lineHeightMultiplier <= 1.7)
    }

    @Test("iPad line height multiplier is in 1.5-1.7x range")
    func iPadLineHeightMultiplierRange() {
        let metrics = LayoutMetrics.iPad
        #expect(metrics.lineHeightMultiplier >= 1.5)
        #expect(metrics.lineHeightMultiplier <= 1.7)
    }

    @Test("Line spacing is positive for standard body font size")
    func lineSpacingPositive() {
        let metrics = LayoutMetrics.iPhone
        let bodySize: CGFloat = 17 // Standard iOS body font size
        let spacing = metrics.lineSpacing(forFontSize: bodySize)
        #expect(spacing > 0, "Line spacing should be positive for body text")
    }

    @Test("Line spacing produces correct total line height")
    func lineSpacingTotal() {
        let metrics = LayoutMetrics.iPhone
        let fontSize: CGFloat = 17
        let naturalLineHeight = fontSize * 1.2 // Approximate
        let spacing = metrics.lineSpacing(forFontSize: fontSize)
        let totalLineHeight = naturalLineHeight + spacing
        let desiredLineHeight = fontSize * metrics.lineHeightMultiplier
        // Total should approximate the desired line height
        #expect(abs(totalLineHeight - desiredLineHeight) < 0.01)
    }

    // MARK: - Paragraph Spacing

    @Test("Paragraph spacing is at least 0.5x line height per AC-4")
    func paragraphSpacingMinimum() {
        let metrics = LayoutMetrics.iPhone
        let bodySize: CGFloat = 17
        let lineHeight = bodySize * metrics.lineHeightMultiplier
        let paragraphSpacing = metrics.paragraphSpacing(forFontSize: bodySize)
        #expect(paragraphSpacing >= lineHeight * 0.5,
                "Paragraph spacing (\(paragraphSpacing)) must be >= 0.5x line height (\(lineHeight * 0.5))")
    }

    @Test("iPad paragraph spacing meets minimum requirement")
    func iPadParagraphSpacing() {
        let metrics = LayoutMetrics.iPad
        let bodySize: CGFloat = 17
        let lineHeight = bodySize * metrics.lineHeightMultiplier
        let paragraphSpacing = metrics.paragraphSpacing(forFontSize: bodySize)
        #expect(paragraphSpacing >= lineHeight * 0.5)
    }

    // MARK: - Margins

    @Test("iPhone has minimum 16pt horizontal margin per AC-5")
    func iPhoneMargins() {
        let metrics = LayoutMetrics.iPhone
        #expect(metrics.horizontalMargin >= 16,
                "iPhone horizontal margin must be >= 16pt")
    }

    @Test("iPad has minimum 32pt horizontal margin per AC-5")
    func iPadMargins() {
        let metrics = LayoutMetrics.iPad
        #expect(metrics.horizontalMargin >= 32,
                "iPad horizontal margin must be >= 32pt")
    }

    @Test("Mac has minimum 32pt horizontal margin")
    func macMargins() {
        let metrics = LayoutMetrics.mac
        #expect(metrics.horizontalMargin >= 32)
    }

    // MARK: - Content Width

    @Test("iPhone has no max content width constraint")
    func iPhoneNoMaxWidth() {
        let metrics = LayoutMetrics.iPhone
        #expect(metrics.maxContentWidth == nil,
                "iPhone should not constrain content width")
    }

    @Test("iPad constrains content width for readability per AC-3")
    func iPadMaxContentWidth() {
        let metrics = LayoutMetrics.iPad
        #expect(metrics.maxContentWidth != nil,
                "iPad should constrain content width")
        // At ~8.5pt per character for 17pt body, 65-80 chars ≈ 550-680pt
        // We allow up to 700pt for breathing room
        if let maxWidth = metrics.maxContentWidth {
            #expect(maxWidth >= 550, "Max width should allow at least 65 characters")
            #expect(maxWidth <= 750, "Max width should not exceed ~80 characters significantly")
        }
    }

    @Test("Mac constrains content width for readability")
    func macMaxContentWidth() {
        let metrics = LayoutMetrics.mac
        #expect(metrics.maxContentWidth != nil)
    }

    // MARK: - Size Class Resolution

    @Test("Compact size class returns iPhone-like metrics")
    func compactSizeClass() {
        let metrics = LayoutMetrics.forSizeClass(.compact)
        #expect(metrics.horizontalMargin == LayoutMetrics.iPhone.horizontalMargin)
        #expect(metrics.maxContentWidth == nil)
    }

    @Test("Regular size class returns iPad-like metrics")
    func regularSizeClass() {
        let metrics = LayoutMetrics.forSizeClass(.regular)
        #expect(metrics.horizontalMargin == LayoutMetrics.iPad.horizontalMargin)
        #expect(metrics.maxContentWidth != nil)
    }

    // MARK: - Platform Insets

    #if canImport(UIKit)
    @Test("UIEdgeInsets match horizontal and vertical margins")
    func uiEdgeInsets() {
        let metrics = LayoutMetrics.iPhone
        let insets = metrics.textContainerInsets
        #expect(insets.left == metrics.horizontalMargin)
        #expect(insets.right == metrics.horizontalMargin)
        #expect(insets.top == metrics.verticalMargin)
        #expect(insets.bottom == metrics.verticalMargin)
    }
    #endif

    #if canImport(AppKit)
    @Test("NSSize inset matches margins")
    func nsInset() {
        let metrics = LayoutMetrics.mac
        let inset = metrics.textContainerInset
        #expect(inset.width == metrics.horizontalMargin)
        #expect(inset.height == metrics.verticalMargin)
    }
    #endif

    // MARK: - Edge Cases

    @Test("Line spacing is zero for very small font sizes")
    func lineSpacingSmallFont() {
        let metrics = LayoutMetrics.iPhone
        // For a very small font, natural line height may exceed desired
        let spacing = metrics.lineSpacing(forFontSize: 1)
        #expect(spacing >= 0, "Line spacing should never be negative")
    }

    @Test("Paragraph spacing scales with font size")
    func paragraphSpacingScales() {
        let metrics = LayoutMetrics.iPhone
        let small = metrics.paragraphSpacing(forFontSize: 12)
        let large = metrics.paragraphSpacing(forFontSize: 24)
        #expect(large > small, "Larger font should produce larger paragraph spacing")
    }
}
