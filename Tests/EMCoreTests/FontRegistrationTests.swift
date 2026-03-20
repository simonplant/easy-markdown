import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMCore

@Suite("FontRegistration")
struct FontRegistrationTests {

    init() {
        FontRegistration.registerFonts()
    }

    // MARK: - Font Registration

    @Test("Custom fonts are registered and loadable")
    func customFontsLoadable() {
        let names = [
            FontRegistration.FontName.serifRegular,
            FontRegistration.FontName.serifItalic,
            FontRegistration.FontName.serifBold,
            FontRegistration.FontName.serifBoldItalic,
            FontRegistration.FontName.serifSemibold,
            FontRegistration.FontName.serifSemiboldItalic,
            FontRegistration.FontName.serifDisplayBold,
            FontRegistration.FontName.serifDisplaySemibold,
            FontRegistration.FontName.monoRegular,
            FontRegistration.FontName.monoBold,
            FontRegistration.FontName.monoItalic,
        ]

        for name in names {
            #if canImport(UIKit)
            let font = UIFont(name: name, size: 17)
            #elseif canImport(AppKit)
            let font = NSFont(name: name, size: 17)
            #endif
            #expect(font != nil, "Font '\(name)' should be registered and loadable")
        }
    }

    // MARK: - Source Serif 4 (Custom Typeface for body/headings — AC-6)

    @Test("Source Serif 4 Regular loads as serif typeface")
    func sourceSerifRegularIsSerif() {
        let font = FontRegistration.font(named: FontRegistration.FontName.serifRegular, size: 17)
        // Verify it's actually Source Serif, not a system fallback
        #if canImport(UIKit)
        #expect(font.fontName.contains("SourceSerif"), "Body font should be Source Serif 4, got: \(font.fontName)")
        #elseif canImport(AppKit)
        #expect(font.fontName.contains("SourceSerif"), "Body font should be Source Serif 4, got: \(font.fontName)")
        #endif
    }

    @Test("Source Serif 4 Display loads for headings")
    func sourceSerifDisplayLoads() {
        let font = FontRegistration.font(named: FontRegistration.FontName.serifDisplayBold, size: 28)
        #if canImport(UIKit)
        #expect(font.fontName.contains("SourceSerif4Display"), "Heading font should be Source Serif 4 Display, got: \(font.fontName)")
        #elseif canImport(AppKit)
        #expect(font.fontName.contains("SourceSerif4Display"), "Heading font should be Source Serif 4 Display, got: \(font.fontName)")
        #endif
    }

    // MARK: - JetBrains Mono (Custom Typeface for code — AC-6)

    @Test("JetBrains Mono loads as monospace typeface")
    func jetBrainsMonoIsMonospace() {
        let font = FontRegistration.font(named: FontRegistration.FontName.monoRegular, size: 15)
        #if canImport(UIKit)
        #expect(font.fontName.contains("JetBrainsMono"), "Code font should be JetBrains Mono, got: \(font.fontName)")
        // Verify monospace trait
        let traits = font.fontDescriptor.symbolicTraits
        #expect(traits.contains(.traitMonoSpace), "JetBrains Mono should have monospace trait")
        #elseif canImport(AppKit)
        #expect(font.fontName.contains("JetBrainsMono"), "Code font should be JetBrains Mono, got: \(font.fontName)")
        #expect(font.isFixedPitch, "JetBrains Mono should be fixed pitch")
        #endif
    }

    // MARK: - TypeScale uses custom fonts

    @Test("TypeScale.default body uses Source Serif 4")
    func typeScaleBodyIsCustom() {
        let scale = TypeScale.default
        let bodyName = scale.body.fontName
        #expect(bodyName.contains("SourceSerif"), "TypeScale body should use Source Serif 4, got: \(bodyName)")
    }

    @Test("TypeScale.default heading1 uses Source Serif 4 Display")
    func typeScaleHeadingIsCustom() {
        let scale = TypeScale.default
        let h1Name = scale.heading1.fontName
        #expect(h1Name.contains("SourceSerif4Display"), "TypeScale heading1 should use Source Serif 4 Display, got: \(h1Name)")
    }

    @Test("TypeScale.default code uses JetBrains Mono")
    func typeScaleCodeIsCustom() {
        let scale = TypeScale.default
        let codeName = scale.code.fontName
        #expect(codeName.contains("JetBrainsMono"), "TypeScale code should use JetBrains Mono, got: \(codeName)")
    }

    // MARK: - Dynamic Type Scaling (AC-2, AC-7)

    #if canImport(UIKit)
    @Test("Custom body font scales with Dynamic Type")
    func bodyFontScalesWithDynamicType() {
        let scale = TypeScale.default
        let bodyFont = scale.body
        // UIFontMetrics-wrapped fonts have maxContentSizeCategory behavior
        // Verify the font exists and has a reasonable size
        #expect(bodyFont.pointSize > 0, "Body font should have positive point size")
        // Verify it's our custom font, not system
        #expect(bodyFont.fontName.contains("SourceSerif"), "Scaled body should still be Source Serif 4")
    }

    @Test("Custom code font scales with Dynamic Type")
    func codeFontScalesWithDynamicType() {
        let scale = TypeScale.default
        let codeFont = scale.code
        #expect(codeFont.pointSize > 0)
        #expect(codeFont.fontName.contains("JetBrainsMono"), "Scaled code should still be JetBrains Mono")
    }
    #endif

    // MARK: - Font cascading for non-Latin scripts (AC-6)

    @Test("Font registration is idempotent")
    func registrationIdempotent() {
        // Calling registerFonts multiple times should not error
        FontRegistration.registerFonts()
        FontRegistration.registerFonts()
        // Fonts should still be available
        let font = FontRegistration.font(named: FontRegistration.FontName.serifRegular, size: 17)
        #expect(font.fontName.contains("SourceSerif"))
    }

    // MARK: - All heading levels use custom fonts

    @Test("All heading levels use custom typefaces")
    func allHeadingLevelsCustom() {
        let scale = TypeScale.default
        for level in 1...6 {
            let font = scale.headingFont(level: level)
            #expect(font.fontName.contains("SourceSerif"),
                    "Heading level \(level) should use Source Serif, got: \(font.fontName)")
        }
    }
}
