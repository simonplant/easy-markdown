#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import EMFile

/// Enables drag-and-drop file opening on the macOS window per FEAT-021.
/// Accepts markdown files dropped onto the app window.
struct MacOSDragDropModifier: ViewModifier {
    let onFileDropped: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
                return true
            }
    }

    /// Handles dropped file URL providers.
    /// Filters to markdown files only per MarkdownExtensions.utTypes.
    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            // Only accept markdown files
            let ext = url.pathExtension.lowercased()
            guard MarkdownExtensions.fileExtensions.contains(ext) else { return }

            Task { @MainActor in
                onFileDropped(url)
            }
        }
    }
}

extension View {
    /// Enables drag-and-drop file opening per FEAT-021.
    func macOSDragDrop(onFileDropped: @escaping (URL) -> Void) -> some View {
        modifier(MacOSDragDropModifier(onFileDropped: onFileDropped))
    }
}
#endif
