import Foundation
import Observation
import os
import EMCore

/// Manages the AI model download lifecycle per [A-031] and [D-AI-9].
/// Background download, resumable, Wi-Fi default with cellular opt-in.
/// Designed as a contained, removable component — may become unnecessary if Apple ships platform AI.
@MainActor
@Observable
public final class ModelDownloadManager {
    /// Current download progress (0.0–1.0).
    public private(set) var progress: Double = 0.0

    /// Total bytes expected for the download.
    public private(set) var totalBytes: Int64 = 0

    /// Bytes downloaded so far.
    public private(set) var bytesDownloaded: Int64 = 0

    /// Current state of the download.
    public private(set) var state: DownloadState = .idle

    /// Whether the user has opted in to cellular downloads.
    public var allowsCellularDownload: Bool = false

    /// Error message if download failed.
    public private(set) var lastError: String?

    private let storage: ModelStorageManager
    private let networkMonitor: NetworkMonitor
    private let modelURL: URL
    private var downloadTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "download")

    /// Creates a download manager.
    /// - Parameters:
    ///   - modelURL: The remote URL to download the model from.
    ///   - storage: Storage manager for model file operations.
    ///   - networkMonitor: Network state monitor.
    public init(
        modelURL: URL,
        storage: ModelStorageManager,
        networkMonitor: NetworkMonitor
    ) {
        self.modelURL = modelURL
        self.storage = storage
        self.networkMonitor = networkMonitor

        // Restore state from storage
        if storage.isModelPresent {
            state = .completed
        } else if storage.hasPartialDownload {
            state = .paused
            bytesDownloaded = storage.partialDownloadSize
        }
    }

    /// Starts or resumes the model download.
    /// Non-blocking — the editor remains usable during download per AC-1.
    public func startDownload() {
        guard state != .downloading, state != .completed else { return }

        // Check cellular policy per AC-3
        if networkMonitor.isCellular && !allowsCellularDownload {
            state = .waitingForWiFi
            lastError = "Waiting for Wi-Fi. Enable cellular download in settings to continue."
            return
        }

        guard networkMonitor.isConnected else {
            state = .failed
            lastError = "No network connection. Connect to Wi-Fi and try again."
            return
        }

        // Check storage before starting per AC-7
        let storageCheck = storage.hasStorageSpace()
        guard storageCheck.hasSufficientSpace else {
            state = .insufficientStorage
            lastError = storageCheck.userMessage
            return
        }

        lastError = nil
        state = .downloading

        downloadTask = Task { [modelURL, storage, networkMonitor, weak self] in
            await self?.performDownload(
                url: modelURL,
                storage: storage,
                networkMonitor: networkMonitor
            )
        }
    }

    /// Pauses the current download. The partial file remains on disk for resuming.
    public func pauseDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if state == .downloading {
            state = .paused
        }
    }

    /// Cancels the download and removes any partial data.
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        storage.deletePartialDownload()
        state = .idle
        progress = 0.0
        bytesDownloaded = 0
        totalBytes = 0
        lastError = nil
    }

    /// Deletes the downloaded model per AC-7 (option to delete model).
    public func deleteModel() throws {
        pauseDownload()
        try storage.deleteModel()
        state = .idle
        progress = 0.0
        bytesDownloaded = 0
        totalBytes = 0
    }

    // MARK: - Private

    private func performDownload(
        url: URL,
        storage: ModelStorageManager,
        networkMonitor: NetworkMonitor
    ) async {
        do {
            try storage.ensureDirectoryExists()

            let configuration = URLSessionConfiguration.default
            configuration.allowsCellularAccess = allowsCellularDownload
            configuration.timeoutIntervalForResource = 3600 // 1 hour for large model
            let session = URLSession(configuration: configuration)

            var request = URLRequest(url: url)

            // Resume from partial download if available per AC-2
            let existingBytes = storage.partialDownloadSize
            if existingBytes > 0 {
                logger.info("Resuming download from byte \(existingBytes)")
                request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
                self.bytesDownloaded = existingBytes
            } else {
                // Start fresh — create empty temp file
                FileManager.default.createFile(
                    atPath: storage.tempDownloadURL.path,
                    contents: nil
                )
                self.bytesDownloaded = 0
            }

            let (asyncBytes, response) = try await session.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...399).contains(httpResponse.statusCode) {
                throw EMError.ai(.modelDownloadFailed(
                    underlying: URLError(.badServerResponse)
                ))
            }

            let expectedLength = response.expectedContentLength
            if expectedLength > 0 {
                self.totalBytes = expectedLength + self.bytesDownloaded
            }

            // Open file handle for appending
            let fileHandle = try FileHandle(forWritingTo: storage.tempDownloadURL)
            fileHandle.seekToEndOfFile()

            var buffer = Data()
            let bufferSize = 256 * 1024 // 256KB flush threshold

            for try await byte in asyncBytes {
                try Task.checkCancellation()

                buffer.append(byte)
                if buffer.count >= bufferSize {
                    fileHandle.write(buffer)
                    self.bytesDownloaded += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    if self.totalBytes > 0 {
                        self.progress = Double(self.bytesDownloaded) / Double(self.totalBytes)
                    }

                    // Check cellular policy during download per AC-3
                    if networkMonitor.isCellular && !self.allowsCellularDownload {
                        try fileHandle.close()
                        self.state = .waitingForWiFi
                        self.lastError = "Download paused — switched to cellular. Enable cellular download to continue."
                        return
                    }
                }
            }

            // Write remaining buffer
            if !buffer.isEmpty {
                fileHandle.write(buffer)
                self.bytesDownloaded += Int64(buffer.count)
            }
            try fileHandle.close()

            // Move to final location atomically
            try storage.finalizeDownload()

            self.progress = 1.0
            self.state = .completed
            logger.info("Model download completed successfully")

        } catch is CancellationError {
            // Partial file remains on disk for resume per AC-2
            logger.info("Download paused, partial file preserved for resume")
            self.state = .paused
        } catch {
            logger.error("Download failed: \(error.localizedDescription)")
            // Partial file remains on disk for retry per AC-2
            self.state = .failed
            self.lastError = EMError.ai(.modelDownloadFailed(underlying: error)).errorDescription
        }
    }
}

/// Download state machine for the model download lifecycle.
public enum DownloadState: Sendable, Equatable {
    /// No download has been started.
    case idle
    /// Download is actively in progress.
    case downloading
    /// Download is paused (user-initiated or app backgrounded).
    case paused
    /// Download is waiting for Wi-Fi (cellular not opted in) per AC-3.
    case waitingForWiFi
    /// Download failed — can retry.
    case failed
    /// Device storage is insufficient per AC-7.
    case insufficientStorage
    /// Download is complete and model is ready.
    case completed
}
