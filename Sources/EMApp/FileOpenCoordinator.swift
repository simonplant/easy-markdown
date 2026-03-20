import Foundation
import Observation
import EMCore
import EMFile
import EMSettings
import os
#if canImport(UIKit)
import UIKit
#endif

/// Coordinates the file open flow across EMFile services and EMApp UI per FEAT-001.
///
/// Ties together FileOpenService, OpenFileRegistry, RecentsManager, ErrorPresenter,
/// and SettingsManager. Handles the complete lifecycle from file picker result to
/// editor navigation, including:
/// - UTF-8 validation errors (AC-2)
/// - Large file warnings (AC-3)
/// - VoiceOver announcements (AC-4)
/// - Bookmark persistence (AC-5)
/// - Duplicate file detection (AC-6)
@MainActor
@Observable
public final class FileOpenCoordinator {

    /// The currently open file content, set after a successful open.
    public private(set) var currentFileContent: FileContent?

    /// The URL of the currently open file.
    public private(set) var currentFileURL: URL?

    private let fileOpenService: FileOpenService
    private let openFileRegistry: OpenFileRegistry
    private let recentsManager: RecentsManager
    private let errorPresenter: ErrorPresenter
    private let settings: SettingsManager
    private let logger = Logger(subsystem: "com.easymarkdown.emapp", category: "file-open")

    public init(
        fileOpenService: FileOpenService,
        openFileRegistry: OpenFileRegistry,
        recentsManager: RecentsManager,
        errorPresenter: ErrorPresenter,
        settings: SettingsManager
    ) {
        self.fileOpenService = fileOpenService
        self.openFileRegistry = openFileRegistry
        self.recentsManager = recentsManager
        self.errorPresenter = errorPresenter
        self.settings = settings
    }

    /// Result of attempting to open a file.
    public enum OpenAttempt {
        /// File opened successfully; navigate to editor.
        case opened
        /// File is already open in another window (AC-6).
        case alreadyOpen
        /// Open failed; error has been presented to the user.
        case failed
    }

    /// Opens a file from a URL (from file picker or bookmark resolution).
    ///
    /// Handles all error presentation, large file warnings, VoiceOver announcements,
    /// recents recording, and duplicate detection.
    ///
    /// - Parameter url: The file URL to open.
    /// - Returns: The result of the open attempt.
    @discardableResult
    public func openFile(url: URL) -> OpenAttempt {
        // AC-6: Check if file is already open in another window
        if openFileRegistry.isOpen(url) {
            logger.info("File already open, activating existing window: \(url.lastPathComponent, privacy: .public)")
            return .alreadyOpen
        }

        // Close any previously open file first
        closeCurrentFile()

        do {
            let result = try fileOpenService.open(url: url)
            return applyOpenResult(result)
        } catch let error as EMError {
            // AC-2: Non-UTF-8 file shows error without crashing
            errorPresenter.present(error)
            logger.error("File open failed: \(error.errorDescription ?? "unknown", privacy: .public)")
            return .failed
        } catch {
            errorPresenter.present(.unexpected(underlying: error))
            logger.error("File open failed unexpectedly: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Opens a file from a saved bookmark (state restoration, recents).
    ///
    /// Uses `FileOpenService.open(fromBookmark:)` to resolve the bookmark and read
    /// the file, then applies the standard success handling.
    ///
    /// - Parameter bookmarkData: The persisted bookmark data.
    /// - Returns: The result of the open attempt.
    @discardableResult
    public func openFile(fromBookmark bookmarkData: Data) -> OpenAttempt {
        closeCurrentFile()

        do {
            let result = try fileOpenService.open(fromBookmark: bookmarkData)
            return applyOpenResult(result)
        } catch {
            let emError = (error as? EMError) ?? .unexpected(underlying: error)
            errorPresenter.present(emError)
            return .failed
        }
    }

    /// Closes the currently open file, releasing resources.
    public func closeCurrentFile() {
        guard let url = currentFileURL else { return }
        fileOpenService.close(url: url)
        openFileRegistry.unregister(url)
        currentFileContent = nil
        currentFileURL = nil
        logger.info("Closed file: \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Private

    /// Shared success path for both open-by-URL and open-by-bookmark.
    private func applyOpenResult(_ result: FileOpenResult) -> OpenAttempt {
        let url = result.content.url

        currentFileContent = result.content
        currentFileURL = url

        openFileRegistry.register(url)
        recentsManager.recordFileOpen(url: url)
        settings.recordDocumentOpened()

        // AC-3: Show dismissable warning for large files
        if result.isLargeFile {
            let warning = PresentableError(
                message: "This file is over 1 MB. Editing may be slower than usual.",
                severity: .informational
            )
            errorPresenter.present(warning)
        }

        // AC-4: VoiceOver announcement
        announceFileOpened(filename: url.lastPathComponent)

        logger.info("File open complete: \(url.lastPathComponent, privacy: .public)")
        return .opened
    }

    /// Posts a VoiceOver announcement when a file is opened per AC-4.
    private func announceFileOpened(filename: String) {
        #if canImport(UIKit)
        UIAccessibility.post(
            notification: .announcement,
            argument: "Opened \(filename)"
        )
        #endif
    }
}
