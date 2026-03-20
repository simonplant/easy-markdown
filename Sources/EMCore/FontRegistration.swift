/// Font registration for custom bundled typefaces per [A-052].
///
/// Registers Source Serif 4 (body/headings) and JetBrains Mono (code) from the
/// EMCore resource bundle at app launch via Core Text. Fonts are registered
/// process-wide so all modules can reference them by PostScript name.
///
/// Fallback chain: custom font → system font for scripts not covered by the
/// custom typeface (CJK, Arabic, Devanagari are handled automatically via
/// the system's font cascading mechanism).

#if canImport(CoreText)
import CoreText
#endif
import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "com.easymarkdown.emcore", category: "fonts")

/// Manages registration and access to custom bundled fonts.
///
/// Call `FontRegistration.registerFonts()` once at app launch before
/// creating any `TypeScale` instances. Registration is idempotent —
/// subsequent calls are no-ops.
public enum FontRegistration {

    /// Whether fonts have been registered this process.
    private static var isRegistered = false

    /// Font file names bundled in EMCore/Resources/Fonts.
    private static let fontFileNames: [String] = [
        // Source Serif 4 — body text (text optical size)
        "SourceSerif4-Regular.ttf",
        "SourceSerif4-It.ttf",
        "SourceSerif4-Bold.ttf",
        "SourceSerif4-BoldIt.ttf",
        "SourceSerif4-Semibold.ttf",
        "SourceSerif4-SemiboldIt.ttf",
        // Source Serif 4 — headings (display optical size)
        "SourceSerif4Display-Bold.ttf",
        "SourceSerif4Display-Semibold.ttf",
        // JetBrains Mono — code
        "JetBrainsMono-Regular.ttf",
        "JetBrainsMono-Bold.ttf",
        "JetBrainsMono-Italic.ttf",
    ]

    /// Registers all bundled custom fonts with Core Text.
    ///
    /// Must be called once at app launch (e.g., in `App.init()` or
    /// `application(_:didFinishLaunchingWithOptions:)`).
    /// Idempotent — safe to call multiple times.
    public static func registerFonts() {
        guard !isRegistered else { return }
        isRegistered = true

        let bundle = Bundle.module

        for fileName in fontFileNames {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension

            guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fonts") else {
                logger.warning("Font file not found in bundle: \(fileName)")
                continue
            }

            var error: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if success {
                logger.debug("Registered font: \(fileName)")
            } else {
                // kCTFontManagerErrorAlreadyRegistered is not a real failure
                let nsError = error?.takeRetainedValue() as Error?
                if let nsError = nsError as NSError?,
                   nsError.code == CTFontManagerError.alreadyRegistered.rawValue {
                    logger.debug("Font already registered: \(fileName)")
                } else {
                    logger.error("Failed to register font \(fileName): \(String(describing: nsError))")
                }
            }
        }
    }

    // MARK: - Font Access

    /// PostScript names for the bundled fonts.
    public enum FontName {
        // Source Serif 4 — body text
        public static let serifRegular = "SourceSerif4-Regular"
        public static let serifItalic = "SourceSerif4-It"
        public static let serifBold = "SourceSerif4-Bold"
        public static let serifBoldItalic = "SourceSerif4-BoldIt"
        public static let serifSemibold = "SourceSerif4-Semibold"
        public static let serifSemiboldItalic = "SourceSerif4-SemiboldIt"
        // Source Serif 4 — display (headings)
        public static let serifDisplayBold = "SourceSerif4Display-Bold"
        public static let serifDisplaySemibold = "SourceSerif4Display-Semibold"
        // JetBrains Mono — code
        public static let monoRegular = "JetBrainsMono-Regular"
        public static let monoBold = "JetBrainsMono-Bold"
        public static let monoItalic = "JetBrainsMono-Italic"
    }

    /// Creates a platform font from a registered custom font name.
    ///
    /// Returns the custom font if available, or falls back to the appropriate
    /// system font. The returned font is NOT yet scaled for Dynamic Type —
    /// callers must wrap with `UIFontMetrics` on iOS.
    ///
    /// - Parameters:
    ///   - name: PostScript name of the registered font (use `FontName` constants).
    ///   - size: Desired point size.
    /// - Returns: The custom font, or a system fallback.
    public static func font(named name: String, size: CGFloat) -> PlatformFont {
        #if canImport(UIKit)
        if let font = UIFont(name: name, size: size) {
            return font
        }
        logger.warning("Custom font '\(name)' not available, using system fallback")
        return UIFont.systemFont(ofSize: size)
        #elseif canImport(AppKit)
        if let font = NSFont(name: name, size: size) {
            return font
        }
        logger.warning("Custom font '\(name)' not available, using system fallback")
        return NSFont.systemFont(ofSize: size)
        #endif
    }
}
