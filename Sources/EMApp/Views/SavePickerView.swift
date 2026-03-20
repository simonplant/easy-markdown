#if canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI wrapper for UIDocumentPickerViewController in move/export mode per FEAT-002.
///
/// Presents the system save dialog so the user can choose where to create a new file.
/// Default filename is "Untitled.md" per AC-3. The system picker natively handles
/// overwrite/rename prompts when a file with the same name exists (AC-6).
struct SavePickerView: UIViewControllerRepresentable {

    /// Called when the user picks a save location. Receives the security-scoped URL.
    let onSave: (URL) -> Void

    /// Called when the user cancels the picker.
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Create a temporary empty file to seed the save picker with the default name.
        // UIDocumentPickerViewController in .moveToService mode requires an existing file URL.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Untitled.md")
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
