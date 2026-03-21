#if os(macOS)
import AppKit
import os

/// macOS Services menu integration per FEAT-021.
/// Registers as a service provider for opening markdown text from other apps.
/// Per AC-7: Right-click context menu matches system style and includes AI actions on selected text.
@MainActor
public final class MacOSServicesProvider: NSObject {
    private let logger = Logger(subsystem: "com.easymarkdown.emapp", category: "services")

    /// Callback invoked when a file URL is received from the Services menu.
    var onOpenFileURL: ((URL) -> Void)?

    /// Callback invoked when markdown text is received from the Services menu.
    var onOpenMarkdownText: ((String) -> Void)?

    /// Registers this provider with the NSApp services system.
    /// Call once at app startup.
    func registerServices() {
        NSApp.servicesProvider = self
        // Update the Services menu to reflect our capabilities.
        NSUpdateDynamicServices()
        logger.info("macOS Services provider registered")
    }

    /// Service handler: opens a markdown file URL received from another app.
    /// The service name "Open in easy-markdown" is declared in Info.plist NSServices.
    @objc func openMarkdownFile(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let items = pboard.pasteboardItems else { return }

        for item in items {
            // Try file URL first
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                onOpenFileURL?(url)
                return
            }

            // Try plain string as markdown text
            if let text = item.string(forType: .string), !text.isEmpty {
                onOpenMarkdownText?(text)
                return
            }
        }

        error.pointee = "No markdown content found on pasteboard." as NSString
    }
}
#endif
