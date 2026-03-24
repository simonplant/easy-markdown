#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// SwiftUI wrapper for UIDocumentPickerViewController to choose
/// an image save location per FEAT-020 (F-015) AC-1/AC-3.
///
/// Presents the system save dialog so the user can choose where to save
/// a dropped or pasted image. The system picker handles overwrite/rename
/// prompts natively.
struct ImageSavePickerView: UIViewControllerRepresentable {

    /// Suggested filename for the image (e.g., "photo.png" or "image-20260323-120000.png").
    let suggestedFilename: String

    /// Called when the user picks a save location. Receives the security-scoped URL.
    let onSave: (URL) -> Void

    /// Called when the user cancels the picker.
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Create a temporary file to seed the save picker with the suggested name.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedFilename)
        try? Data().write(to: tempURL)

        let picker = UIDocumentPickerViewController(
            forExporting: [tempURL],
            asCopy: false
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSave: (URL) -> Void
        let onCancel: () -> Void

        init(onSave: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSave = onSave
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSave(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#endif
