import Foundation
import Observation
import EMCore
import EMFile
import EMSettings
import os
#if canImport(UIKit)
import UIKit
#endif

/// Coordinates the file creation flow across EMFile services and EMApp UI per FEAT-002.
///
/// Ties together FileCreateService, OpenFileRegistry, RecentsManager, ErrorPresenter,
/// and SettingsManager. Handles the complete lifecycle from save picker result to
/// editor navigation, including:
/// - Atomic write with LF line endings (AC-2)
/// - Write failure error presentation with no corrupt file left behind (AC-5)
/// - VoiceOver announcements
/// - Bookmark persistence for recents
@MainActor
@Observable
public final class FileCreateCoordinator {

    /// The content of the most recently created file, set after a successful create.
    public private(set) var createdFileContent: FileContent?

    /// The URL of the most recently created file.
    public private(set) var createdFileURL: URL?

    private let fileCreateService: FileCreateService
    private let openFileRegistry: OpenFileRegistry
    private let recentsManager: RecentsManager
    private let errorPresenter: ErrorPresenter
    private let settings: SettingsManager
    private let logger = Logger(subsystem: "com.easymarkdown.emapp", category: "file-create")

    public init(
        fileCreateService: FileCreateService,
        openFileRegistry: OpenFileRegistry,
        recentsManager: RecentsManager,
        errorPresenter: ErrorPresenter,
        settings: SettingsManager
    ) {
        self.fileCreateService = fileCreateService
        self.openFileRegistry = openFileRegistry
        self.recentsManager = recentsManager
        self.errorPresenter = errorPresenter
        self.settings = settings
    }

    /// Result of attempting to create a file.
    public enum CreateAttempt {
        /// File created successfully; navigate to editor.
        case created
        /// Creation failed; error has been presented to the user.
        case failed
    }

    /// Creates a new file at the URL chosen by the user in the save picker.
    ///
    /// Handles error presentation, VoiceOver announcements, recents recording,
    /// and registry tracking.
    ///
    /// - Parameter url: The URL chosen in the save picker.
    /// - Returns: The result of the create attempt.
    @discardableResult
    public func createFile(at url: URL) -> CreateAttempt {
        do {
            let result = try fileCreateService.create(at: url)

            createdFileContent = result.content
            createdFileURL = url

            openFileRegistry.register(url)
            recentsManager.recordFileOpen(url: url)
            settings.recordDocumentOpened()

            announceFileCreated(filename: url.lastPathComponent)

            logger.info("File create complete: \(url.lastPathComponent, privacy: .public)")
            return .created
        } catch let error as EMError {
            errorPresenter.present(error)
            logger.error("File create failed: \(error.errorDescription ?? "unknown", privacy: .public)")
            return .failed
        } catch {
            errorPresenter.present(.unexpected(underlying: error))
            logger.error("File create failed unexpectedly: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Clears the created file state. Called when the file is subsequently managed
    /// by the FileOpenCoordinator (e.g., after navigation to editor).
    public func clearCreatedFile() {
        createdFileContent = nil
        createdFileURL = nil
    }

    // MARK: - Private

    /// Posts a VoiceOver announcement when a file is created.
    private func announceFileCreated(filename: String) {
        #if canImport(UIKit)
        UIAccessibility.post(
            notification: .announcement,
            argument: "Created \(filename)"
        )
        #endif
    }
}
