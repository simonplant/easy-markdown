#if canImport(UIKit)
import SwiftUI
import UIKit
import EMFile

/// SwiftUI wrapper for UIDocumentPickerViewController per FEAT-001.
///
/// Presents the system file picker filtered to markdown file types per [D-FILE-6].
/// Returns the selected URL to the caller via the `onPick` callback.
struct DocumentPickerView: UIViewControllerRepresentable {

    /// Called when the user picks a file. Receives the security-scoped URL.
    let onPick: (URL) -> Void

    /// Called when the user cancels the picker.
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: MarkdownExtensions.utTypes,
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#endif
