/// Saves image data to a user-chosen location per FEAT-020 (F-015).
///
/// Uses NSFileCoordinator for atomic writes per [A-025].
/// Runs on a background thread to avoid freezing the editor (AC-4).

import Foundation
import EMCore
import os

private let logger = Logger(subsystem: "com.easymarkdown.emfile", category: "image-save")

/// Service for saving dropped/pasted image data to disk.
public enum ImageSaveService {

    /// Saves image data to the specified URL using coordinated file access.
    ///
    /// - Parameters:
    ///   - data: Raw image data (PNG, JPEG, etc.).
    ///   - url: The destination file URL chosen by the user.
    /// - Throws: `EMError.file(.saveFailed)` if the write fails.
    public static func save(data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
                logger.info("Saved image (\(data.count) bytes) to \(writeURL.lastPathComponent)")
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            logger.error("Coordination failed for image save: \(coordinationError.localizedDescription)")
            throw EMError.file(.saveFailed(url: url, underlying: coordinationError))
        }

        if let writeError {
            logger.error("Image write failed: \(writeError.localizedDescription)")
            throw EMError.file(.saveFailed(url: url, underlying: writeError))
        }
    }

    /// Computes the relative path from a document URL to a saved image URL.
    ///
    /// Returns a path suitable for markdown image syntax: `![](relative/path.png)`.
    /// If no document URL is available, returns the image filename only.
    ///
    /// - Parameters:
    ///   - imageURL: The absolute URL of the saved image.
    ///   - documentURL: The URL of the current document (may be nil for unsaved docs).
    /// - Returns: A relative path string for use in markdown.
    public static func relativePath(from documentURL: URL?, to imageURL: URL) -> String {
        guard let documentURL else {
            return imageURL.lastPathComponent
        }

        let docDir = documentURL.deletingLastPathComponent().standardized.path
        let imagePath = imageURL.standardized.path

        // If the image is in the same directory or a subdirectory of the document
        if imagePath.hasPrefix(docDir) {
            var relative = String(imagePath.dropFirst(docDir.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }

        // Build relative path by walking up from the document directory
        let docComponents = docDir.split(separator: "/")
        let imageComponents = imagePath.split(separator: "/")

        // Find common prefix length
        var commonLength = 0
        for i in 0..<min(docComponents.count, imageComponents.count) {
            if docComponents[i] == imageComponents[i] {
                commonLength = i + 1
            } else {
                break
            }
        }

        // Build "../" for each level above common prefix
        let upCount = docComponents.count - commonLength
        let ups = Array(repeating: "..", count: upCount)
        let remainingPath = imageComponents[commonLength...]

        let components = ups + remainingPath.map(String.init)
        return components.joined(separator: "/")
    }

    /// Suggests a filename for a pasted image (no original name available).
    ///
    /// Format: `image-YYYYMMDD-HHmmss.png`
    public static func suggestedFilename(extension ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "image-\(formatter.string(from: Date())).\(ext)"
    }
}
