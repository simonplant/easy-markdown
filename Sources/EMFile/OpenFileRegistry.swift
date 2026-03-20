import Foundation
import os

/// Tracks currently open file URLs across all editor scenes per [A-028].
///
/// Used to detect when a user attempts to open a file that is already open
/// in another editor window (AC-6: show that window instead of duplicating).
/// Thread-safe via NSLock for cross-scene access.
public final class OpenFileRegistry: @unchecked Sendable {

    private let lock = NSLock()
    private var openURLs: Set<URL> = []
    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "open-registry"
    )

    public init() {}

    /// Registers a URL as currently open in an editor scene.
    public func register(_ url: URL) {
        lock.lock()
        openURLs.insert(url.standardizedFileURL)
        lock.unlock()
        logger.debug("Registered open file: \(url.lastPathComponent)")
    }

    /// Unregisters a URL when its editor scene closes.
    public func unregister(_ url: URL) {
        lock.lock()
        openURLs.remove(url.standardizedFileURL)
        lock.unlock()
        logger.debug("Unregistered open file: \(url.lastPathComponent)")
    }

    /// Whether the given URL is currently open in any editor scene.
    public func isOpen(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return openURLs.contains(url.standardizedFileURL)
    }

    /// The number of currently open files.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return openURLs.count
    }
}
