import Foundation
import EMCore

/// Manages security-scoped URL bookmarks for persistent file access per [A-024].
///
/// Persists bookmark data in UserDefaults so files remain accessible across app
/// launches without requiring the user to re-pick them from the file picker.
public final class BookmarkManager: @unchecked Sendable {

    private let defaults: UserDefaults
    private let bookmarksKey: String

    /// Creates a bookmark manager.
    /// - Parameters:
    ///   - defaults: The UserDefaults store for bookmark persistence.
    ///   - bookmarksKey: The key under which bookmarks are stored.
    public init(
        defaults: UserDefaults = .standard,
        bookmarksKey: String = "com.easymarkdown.bookmarks"
    ) {
        self.defaults = defaults
        self.bookmarksKey = bookmarksKey
    }

    // MARK: - Bookmark Persistence

    /// Creates and persists a security-scoped bookmark for the given URL.
    ///
    /// Call this after the user picks a file to ensure it can be reopened later.
    /// - Throws: `EMError.file(.accessDenied)` if the bookmark cannot be created.
    public func saveBookmark(for url: URL) throws -> Data {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadAllBookmarks()
            bookmarks[url.absoluteString] = bookmarkData
            defaults.set(bookmarks, forKey: bookmarksKey)
            return bookmarkData
        } catch {
            throw EMError.file(.accessDenied(url: url))
        }
    }

    /// Resolves a persisted bookmark back into a URL.
    ///
    /// If the bookmark is stale (file moved/renamed), returns `.bookmarkStale`.
    /// The caller must call `url.startAccessingSecurityScopedResource()` on the
    /// returned URL before reading the file.
    /// - Throws: `EMError.file(.bookmarkStale)` if resolution fails.
    public func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Attempt to refresh the bookmark; if refresh fails, surface the stale condition
                do {
                    _ = try saveBookmark(for: url)
                } catch {
                    throw EMError.file(.bookmarkStale(url: url))
                }
            }
            return url
        } catch let error as EMError {
            throw error
        } catch {
            throw EMError.file(.bookmarkStale(url: URL(fileURLWithPath: "unknown")))
        }
    }

    /// Retrieves the persisted bookmark data for a URL, if available.
    public func bookmark(for url: URL) -> Data? {
        let bookmarks = loadAllBookmarks()
        return bookmarks[url.absoluteString]
    }

    /// Removes the persisted bookmark for a URL.
    public func removeBookmark(for url: URL) {
        var bookmarks = loadAllBookmarks()
        bookmarks.removeValue(forKey: url.absoluteString)
        defaults.set(bookmarks, forKey: bookmarksKey)
    }

    /// Returns all persisted bookmark entries (URL string → bookmark data).
    public func allBookmarks() -> [String: Data] {
        loadAllBookmarks()
    }

    // MARK: - Private

    private func loadAllBookmarks() -> [String: Data] {
        defaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
}
