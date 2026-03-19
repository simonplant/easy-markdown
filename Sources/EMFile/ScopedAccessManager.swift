import Foundation
import EMCore
import os

/// Manages balanced start/stop of security-scoped resource access per [A-024].
///
/// Ensures that `startAccessingSecurityScopedResource()` and
/// `stopAccessingSecurityScopedResource()` are always balanced.
/// Tracks active access to prevent leaks.
public final class ScopedAccessManager: @unchecked Sendable {

    private let lock = NSLock()
    private var activeURLs: Set<URL> = []
    private let logger = Logger(
        subsystem: "com.easymarkdown.emfile",
        category: "scoped-access"
    )

    public init() {}

    /// Begins security-scoped access to the URL.
    ///
    /// - Returns: `true` if access was granted, `false` if the URL is not security-scoped
    ///   or access was denied.
    @discardableResult
    public func startAccessing(_ url: URL) -> Bool {
        let granted = url.startAccessingSecurityScopedResource()
        if granted {
            lock.lock()
            activeURLs.insert(url)
            lock.unlock()
            logger.debug("Started accessing: \(url.lastPathComponent)")
        } else {
            logger.info("Access not granted for: \(url.lastPathComponent)")
        }
        return granted
    }

    /// Stops security-scoped access to the URL.
    ///
    /// Safe to call even if the URL was never started — no-ops gracefully.
    public func stopAccessing(_ url: URL) {
        lock.lock()
        let wasActive = activeURLs.remove(url) != nil
        lock.unlock()

        if wasActive {
            url.stopAccessingSecurityScopedResource()
            logger.debug("Stopped accessing: \(url.lastPathComponent)")
        }
    }

    /// Stops all active security-scoped accesses.
    /// Call this during app termination to clean up.
    public func stopAll() {
        lock.lock()
        let urls = activeURLs
        activeURLs.removeAll()
        lock.unlock()

        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
        if !urls.isEmpty {
            logger.debug("Stopped accessing \(urls.count) URLs")
        }
    }

    /// The number of currently active security-scoped accesses.
    public var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeURLs.count
    }
}
