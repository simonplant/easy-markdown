import Foundation
import EMCore
import os

#if canImport(UIKit)
import UIKit
#endif

/// Manages automatic saving of document content per [A-026] and FEAT-008.
///
/// Save triggers:
/// - 1 second after last keystroke (debounced via `contentDidChange()`)
/// - On app background (`sceneDidEnterBackground`)
/// - On file close (explicit `saveNow()`)
///
/// Uses `CoordinatedFileAccess` for atomic writes and integrates with
/// `FileConflictManager` to pause saves during external change conflicts.
/// Save failures are reported via the `onSaveError` callback as non-modal
/// errors with retry.
@MainActor
@Observable
public final class AutoSaveManager {

    // MARK: - Public State

    /// Date of the last successful save. Nil if no save has occurred.
    public private(set) var lastSaveDate: Date?

    /// Whether a save is currently in progress.
    public private(set) var isSaving: Bool = false

    /// Whether changes were saved while the app was in the background.
    /// The UI layer should trigger a subtle haptic when this becomes true
    /// and the app returns to the foreground, then reset it via `clearBackgroundSaveFlag()`.
    public private(set) var savedWhileInBackground: Bool = false

    // MARK: - Callbacks

    /// Provides the current text content for saving. Set by the coordinator layer.
    public var contentProvider: (@MainActor () -> String)?

    /// Called when a save fails. The coordinator layer wires this to `ErrorPresenter`.
    public var onSaveError: (@MainActor (EMError) -> Void)?

    /// Called after a successful save. The coordinator layer can use this to update
    /// the document's dirty state.
    public var onSaveSuccess: (@MainActor () -> Void)?

    // MARK: - Private

    private let fileURL: URL
    private let lineEnding: LineEnding
    private let conflictManager: FileConflictManager
    private var debounceTask: Task<Void, Never>?
    private var lastSavedContent: String?
    private var isInBackground: Bool = false

    #if canImport(UIKit)
    private var backgroundObserver: (any NSObjectProtocol)?
    private var foregroundObserver: (any NSObjectProtocol)?
    #endif

    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "auto-save"
    )

    /// Debounce interval in nanoseconds (1 second).
    private let debounceNanoseconds: UInt64

    // MARK: - Init

    /// Creates an auto-save manager for the given file.
    ///
    /// - Parameters:
    ///   - url: The file URL to save to.
    ///   - lineEnding: The line ending style to preserve on save.
    ///   - conflictManager: The conflict manager for this file.
    ///   - initialContent: The initial file content (used to detect changes).
    ///   - debounceNanoseconds: Debounce interval in nanoseconds. Defaults to 1 second.
    public init(
        url: URL,
        lineEnding: LineEnding,
        conflictManager: FileConflictManager,
        initialContent: String,
        debounceNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.fileURL = url
        self.lineEnding = lineEnding
        self.conflictManager = conflictManager
        self.lastSavedContent = initialContent
        self.debounceNanoseconds = debounceNanoseconds
        observeAppLifecycle()
    }

    // MARK: - Public API

    /// Notifies the manager that content has changed, starting the debounce timer.
    ///
    /// Call this on every keystroke. The save will fire 1 second after the last call.
    public func contentDidChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.performSave()
        }
    }

    /// Saves immediately without debouncing. Use for file close and explicit save.
    ///
    /// Cancels any pending debounced save before executing.
    public func saveNow() async {
        debounceTask?.cancel()
        debounceTask = nil
        await performSave()
    }

    /// Clears the background save flag after the UI has triggered the haptic.
    public func clearBackgroundSaveFlag() {
        savedWhileInBackground = false
    }

    /// Stops the auto-save manager and cancels pending saves.
    ///
    /// Call this when the file is closed. Does not perform a final save —
    /// call `saveNow()` before `stop()` if a final save is needed.
    public func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        removeLifecycleObservers()
    }

    // MARK: - Save Logic

    private func performSave() async {
        guard !conflictManager.isAutoSavePaused else {
            logger.debug("Auto-save skipped: conflict active")
            return
        }

        guard let content = contentProvider?() else {
            logger.debug("Auto-save skipped: no content provider")
            return
        }

        guard content != lastSavedContent else {
            logger.debug("Auto-save skipped: no changes")
            return
        }

        isSaving = true
        defer { isSaving = false }

        // Pause external change detection during our write
        conflictManager.pauseDetection()
        defer { conflictManager.resumeDetection() }

        do {
            try CoordinatedFileAccess.write(
                text: content,
                to: fileURL,
                lineEnding: lineEnding
            )
            lastSavedContent = content
            lastSaveDate = Date()
            if isInBackground {
                savedWhileInBackground = true
            }
            onSaveSuccess?()
            logger.info("Auto-saved: \(self.fileURL.lastPathComponent, privacy: .public)")
        } catch let error as EMError {
            logger.error("Auto-save failed: \(error.localizedDescription)")
            onSaveError?(error)
        } catch {
            let emError = EMError.file(.saveFailed(url: fileURL, underlying: error))
            logger.error("Auto-save failed: \(error.localizedDescription)")
            onSaveError?(emError)
        }
    }

    // MARK: - App Lifecycle

    private func observeAppLifecycle() {
        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidEnterBackground()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWillEnterForeground()
            }
        }
        #endif
    }

    private func handleDidEnterBackground() {
        isInBackground = true
        debounceTask?.cancel()
        debounceTask = nil
        Task { [weak self] in
            await self?.performSave()
        }
    }

    private func handleWillEnterForeground() {
        isInBackground = false
    }

    private func removeLifecycleObservers() {
        #if canImport(UIKit)
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        backgroundObserver = nil
        foregroundObserver = nil
        #endif
    }
}
