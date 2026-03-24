import Foundation
import Observation
import UniformTypeIdentifiers
import EMCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Owns PDF export, markdown share, and print state per FEAT-074.
///
/// Extracted from EditorShellView so export/share presentation state
/// lives in a testable coordinator rather than as view @State properties.
@MainActor
@Observable
final class ExportCoordinator {

    // MARK: - PDF Export State per FEAT-061

    /// Whether the PDF share sheet is presented (iOS).
    var showingPDFShareSheet = false
    /// The temporary URL of the exported PDF.
    var exportedPDFURL: URL?

    // MARK: - Markdown Share State per FEAT-018

    /// Whether the markdown share sheet is presented (iOS).
    var showingMarkdownShareSheet = false

    // MARK: - Export Actions

    /// Exports the current document as a PDF with optional watermark per FEAT-061.
    func exportPDF(
        text: String,
        documentURL: URL?,
        includeWatermark: Bool,
        errorPresenter: ErrorPresenter
    ) {
        let pdfData = PDFExporter.exportPDF(
            text: text,
            documentURL: documentURL,
            includeWatermark: includeWatermark
        )

        let fileName = documentURL?
            .deletingPathExtension().lastPathComponent ?? "Untitled"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).pdf")

        do {
            try pdfData.write(to: tempURL)
            exportedPDFURL = tempURL

            #if os(macOS)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.pdf]
            savePanel.nameFieldStringValue = "\(fileName).pdf"
            savePanel.begin { response in
                guard response == .OK, let url = savePanel.url else { return }
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: tempURL, to: url)
                } catch {
                    // Best-effort save — NSSavePanel already confirmed the location
                }
            }
            #else
            showingPDFShareSheet = true
            #endif
        } catch {
            errorPresenter.present(.unexpected(underlying: error))
        }
    }

    /// Shares the .md file via the system share sheet per FEAT-018.
    func shareMarkdownFile(text: String, fileURL: URL?) {
        #if os(iOS)
        showingMarkdownShareSheet = true
        #else
        guard let url = markdownShareURL(text: text, fileURL: fileURL) else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
        }
        #endif
    }

    /// Returns a URL to share the markdown file.
    func markdownShareURL(text: String, fileURL: URL?) -> URL? {
        if let fileURL {
            return fileURL
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Untitled.md")
        guard let data = text.data(using: .utf8) else { return nil }
        try? data.write(to: tempURL)
        return tempURL
    }

    /// Prints the rendered document per FEAT-018.
    func printDocument(text: String, documentURL: URL?) {
        #if os(iOS)
        let printController = UIPrintInteractionController.shared
        printController.printInfo = UIPrintInfo(dictionary: nil)
        printController.printInfo?.jobName = documentURL?
            .deletingPathExtension().lastPathComponent ?? "Untitled"
        printController.printInfo?.outputType = .general

        let pdfData = PDFExporter.exportPDF(
            text: text,
            documentURL: documentURL,
            includeWatermark: false
        )
        printController.printingItem = pdfData
        printController.present(animated: true)
        #else
        let richText = PDFExporter.renderAttributedString(
            text: text,
            documentURL: documentURL
        )
        let printView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: 468, // US Letter content width (612 - 72*2)
            height: 648  // US Letter content height (792 - 72*2)
        ))
        printView.textStorage?.setAttributedString(richText)
        printView.isEditable = false

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.jobDisposition = .spool

        let printOp = NSPrintOperation(view: printView, printInfo: printInfo)
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.run()
        #endif
    }
}
