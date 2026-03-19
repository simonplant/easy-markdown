import Foundation
import EMCore
import os

/// Monitors a file for external changes via NSFilePresenter per [A-027].
///
/// When another process (iCloud sync, Dropbox, Git, etc.) modifies the
/// monitored file, the `onExternalChange` callback fires. The editor
/// should then offer the user a choice: reload or keep their version.
@MainActor
public final class ExternalChangeMonitor: NSObject, @unchecked Sendable {

    /// Callback invoked on the main actor when the monitored file changes externally.
    public var onExternalChange: (@MainActor () -> Void)?

    /// Callback invoked on the main actor when the monitored file is deleted externally.
    public var onExternalDeletion: (@MainActor () -> Void)?

    /// Whether monitoring is currently paused (e.g., during our own save).
    public private(set) var isPaused: Bool = false

    private let monitoredURL: URL
    private let operationQueue: OperationQueue
    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "external-change"
    )
    private var isRegistered = false

    /// Creates a monitor for the given file URL.
    public init(url: URL) {
        self.monitoredURL = url
        self.operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .utility
        super.init()
    }

    /// Starts monitoring the file for external changes.
    /// Must be balanced with a call to `stopMonitoring()`.
    public func startMonitoring() {
        guard !isRegistered else { return }
        NSFileCoordinator.addFilePresenter(self)
        isRegistered = true
        logger.debug("Started monitoring: \(self.monitoredURL.lastPathComponent)")
    }

    /// Stops monitoring the file.
    public func stopMonitoring() {
        guard isRegistered else { return }
        NSFileCoordinator.removeFilePresenter(self)
        isRegistered = false
        logger.debug("Stopped monitoring: \(self.monitoredURL.lastPathComponent)")
    }

    /// Temporarily pauses change notifications (e.g., while saving).
    public func pause() {
        isPaused = true
    }

    /// Resumes change notifications after a pause.
    public func resume() {
        isPaused = false
    }

    deinit {
        if isRegistered {
            NSFileCoordinator.removeFilePresenter(self)
        }
    }
}

// MARK: - NSFilePresenter

extension ExternalChangeMonitor: NSFilePresenter {

    nonisolated public var presentedItemURL: URL? {
        monitoredURL
    }

    nonisolated public var presentedItemOperationQueue: OperationQueue {
        operationQueue
    }

    nonisolated public func presentedItemDidChange() {
        Task { @MainActor [weak self] in
            guard let self, !self.isPaused else { return }
            self.logger.info("External change detected: \(self.monitoredURL.lastPathComponent)")
            self.onExternalChange?()
        }
    }

    nonisolated public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(nil)
                return
            }
            self.logger.info("External deletion detected: \(self.monitoredURL.lastPathComponent)")
            self.onExternalDeletion?()
            completionHandler(nil)
        }
    }
}
