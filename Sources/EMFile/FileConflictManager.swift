import Foundation
import EMCore
import os

/// The current state of a file conflict.
public enum FileConflictState: Sendable, Equatable {
    /// No conflict — file is in sync.
    case none
    /// File was modified externally while open in the editor.
    case externallyModified
    /// File was deleted externally while open in the editor.
    case externallyDeleted
}

/// Coordinates file conflict detection between the editor and external changes per [A-027] and FEAT-045.
///
/// Wraps `ExternalChangeMonitor` and manages conflict state. When an external change
/// is detected, pauses auto-save and exposes the conflict state for the UI layer.
/// Provides `reload()` to accept external changes and `keepMine()` to dismiss the conflict.
@MainActor
@Observable
public final class FileConflictManager {

    /// The current conflict state. Observed by the UI to show/hide the conflict banner.
    public private(set) var conflictState: FileConflictState = .none

    /// Whether auto-save should be paused due to an active conflict.
    public var isAutoSavePaused: Bool {
        conflictState != .none
    }

    private let fileURL: URL
    private let monitor: ExternalChangeMonitor
    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "conflict"
    )

    /// Creates a conflict manager for the given file URL.
    ///
    /// - Parameter url: The file URL to monitor for external changes.
    public init(url: URL) {
        self.fileURL = url
        self.monitor = ExternalChangeMonitor(url: url)

        monitor.onExternalChange = { [weak self] in
            self?.handleExternalChange()
        }
        monitor.onExternalDeletion = { [weak self] in
            self?.handleExternalDeletion()
        }
    }

    /// Starts monitoring the file for external changes.
    public func startMonitoring() {
        monitor.startMonitoring()
    }

    /// Stops monitoring the file for external changes.
    public func stopMonitoring() {
        monitor.stopMonitoring()
    }

    /// Pauses change detection temporarily (e.g., during our own save).
    public func pauseDetection() {
        monitor.pause()
    }

    /// Resumes change detection after a pause.
    public func resumeDetection() {
        monitor.resume()
    }

    /// Reloads the file from disk, accepting external changes.
    ///
    /// Reads the file using coordinated access, clears the conflict state,
    /// and resumes monitoring. The caller should update the editor content
    /// with the returned `FileContent`.
    ///
    /// - Returns: The freshly read file content.
    /// - Throws: `EMError.file` variants if the file can't be read.
    public func reload() throws -> FileContent {
        logger.info("User chose reload for: \(self.fileURL.lastPathComponent)")
        let content = try CoordinatedFileAccess.read(from: fileURL, presenter: monitor)
        conflictState = .none
        return content
    }

    /// Keeps the editor's version, dismissing the conflict.
    ///
    /// The next save will overwrite external changes. Clears conflict state
    /// and resumes normal monitoring.
    public func keepMine() {
        logger.info("User chose keep mine for: \(self.fileURL.lastPathComponent)")
        conflictState = .none
    }

    // MARK: - Private

    private func handleExternalChange() {
        guard conflictState == .none else { return }
        logger.info("External modification detected: \(self.fileURL.lastPathComponent)")
        conflictState = .externallyModified
    }

    private func handleExternalDeletion() {
        logger.info("External deletion detected: \(self.fileURL.lastPathComponent)")
        conflictState = .externallyDeleted
    }
}
