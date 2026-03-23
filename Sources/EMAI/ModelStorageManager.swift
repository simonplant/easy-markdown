import Foundation
import os
import EMCore

/// Manages on-device model file storage, including space checks and cleanup per [A-031].
/// Designed as a contained, removable component — may become unnecessary if Apple ships platform AI.
public final class ModelStorageManager: Sendable {
    /// Directory where model files are stored within the app container.
    private let modelDirectory: URL

    /// Minimum free disk space required before starting a model download (500MB buffer).
    public static let minimumFreeSpaceBytes: Int64 = 500 * 1024 * 1024

    /// Expected model size for storage estimation (2GB quantized model).
    public static let expectedModelSizeBytes: Int64 = 2 * 1024 * 1024 * 1024

    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "storage")

    public init(modelDirectory: URL? = nil) {
        if let modelDirectory {
            self.modelDirectory = modelDirectory
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                logger.error("Application Support directory unavailable — falling back to temporary directory")
                self.modelDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Models", isDirectory: true)
                return
            }
            self.modelDirectory = appSupport.appendingPathComponent("Models", isDirectory: true)
        }
    }

    /// The file URL where the model is stored.
    public var modelFileURL: URL {
        modelDirectory.appendingPathComponent("model.mlpackage")
    }

    /// The file URL for the in-progress download. Its existence indicates an interrupted download.
    public var tempDownloadURL: URL {
        modelDirectory.appendingPathComponent("model.mlpackage.downloading")
    }

    /// Whether a downloaded model file exists on disk.
    public var isModelPresent: Bool {
        FileManager.default.fileExists(atPath: modelFileURL.path)
    }

    /// Whether a partial download exists (interrupted download that can be resumed).
    public var hasPartialDownload: Bool {
        FileManager.default.fileExists(atPath: tempDownloadURL.path)
    }

    /// The size in bytes of the partial download, or 0 if none.
    public var partialDownloadSize: Int64 {
        guard hasPartialDownload else { return 0 }
        let attributes = try? FileManager.default.attributesOfItem(atPath: tempDownloadURL.path)
        return attributes?[.size] as? Int64 ?? 0
    }

    /// The size in bytes of the downloaded model, or nil if not present.
    public var modelSizeOnDisk: Int64? {
        guard isModelPresent else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: modelFileURL.path)
        return attributes?[.size] as? Int64
    }

    /// Checks whether there is sufficient disk space for the model download.
    public func hasStorageSpace() -> StorageCheckResult {
        do {
            let checkURL: URL
            if FileManager.default.fileExists(atPath: modelDirectory.path) {
                checkURL = modelDirectory
            } else {
                checkURL = modelDirectory.deletingLastPathComponent()
            }
            let resourceValues = try checkURL
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
            let needed = Self.expectedModelSizeBytes + Self.minimumFreeSpaceBytes

            if available >= needed {
                return .sufficient(availableBytes: available)
            } else {
                return .insufficient(
                    availableBytes: available,
                    neededBytes: needed
                )
            }
        } catch {
            logger.error("Failed to check storage: \(error.localizedDescription)")
            return .checkFailed(underlying: error)
        }
    }

    /// Ensures the model directory exists.
    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Deletes the downloaded model and any partial download.
    public func deleteModel() throws {
        if FileManager.default.fileExists(atPath: modelFileURL.path) {
            try FileManager.default.removeItem(at: modelFileURL)
            logger.info("Model file deleted")
        }
        deletePartialDownload()
    }

    /// Deletes the partial download file.
    public func deletePartialDownload() {
        try? FileManager.default.removeItem(at: tempDownloadURL)
    }

    /// Moves the completed download to the final model location atomically.
    public func finalizeDownload() throws {
        if FileManager.default.fileExists(atPath: modelFileURL.path) {
            try FileManager.default.removeItem(at: modelFileURL)
        }
        try FileManager.default.moveItem(at: tempDownloadURL, to: modelFileURL)
        logger.info("Model download finalized")
    }
}

/// Result of a storage space check before model download.
public enum StorageCheckResult: Sendable {
    /// Enough space available.
    case sufficient(availableBytes: Int64)
    /// Not enough space — show message and option to skip/delete model.
    case insufficient(availableBytes: Int64, neededBytes: Int64)
    /// Could not determine storage — treat as insufficient.
    case checkFailed(underlying: Error)

    /// Whether the check indicates sufficient space.
    public var hasSufficientSpace: Bool {
        if case .sufficient = self { return true }
        return false
    }

    /// A user-facing message for insufficient storage per AC-7.
    public var userMessage: String? {
        switch self {
        case .sufficient:
            return nil
        case .insufficient(let available, let needed):
            let availableMB = available / (1024 * 1024)
            let neededMB = needed / (1024 * 1024)
            return "Not enough storage for the AI model. \(availableMB) MB available, \(neededMB) MB needed. Free up space or skip the download."
        case .checkFailed:
            return "Couldn't check available storage. Free up space and try again."
        }
    }
}
