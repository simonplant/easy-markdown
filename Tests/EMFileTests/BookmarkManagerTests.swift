import Testing
import Foundation
@testable import EMFile
@testable import EMCore

@Suite("BookmarkManager")
struct BookmarkManagerTests {

    @Test("Stores and retrieves bookmark data")
    func storeAndRetrieve() {
        let defaults = UserDefaults(suiteName: "BookmarkManagerTests-\(UUID().uuidString)")!
        let manager = BookmarkManager(defaults: defaults, bookmarksKey: "test.bookmarks")

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let fakeBookmarkData = Data("bookmark-data".utf8)

        // Manually set bookmark data (we can't create real bookmarks in tests)
        defaults.set([url.absoluteString: fakeBookmarkData], forKey: "test.bookmarks")

        let retrieved = manager.bookmark(for: url)
        #expect(retrieved == fakeBookmarkData)
    }

    @Test("Returns nil for unknown URL")
    func unknownURL() {
        let defaults = UserDefaults(suiteName: "BookmarkManagerTests-\(UUID().uuidString)")!
        let manager = BookmarkManager(defaults: defaults, bookmarksKey: "test.bookmarks")

        let url = URL(fileURLWithPath: "/tmp/nonexistent.md")
        #expect(manager.bookmark(for: url) == nil)
    }

    @Test("Removes bookmark")
    func removeBookmark() {
        let defaults = UserDefaults(suiteName: "BookmarkManagerTests-\(UUID().uuidString)")!
        let manager = BookmarkManager(defaults: defaults, bookmarksKey: "test.bookmarks")

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let data = Data("bookmark-data".utf8)
        defaults.set([url.absoluteString: data], forKey: "test.bookmarks")

        #expect(manager.bookmark(for: url) != nil)

        manager.removeBookmark(for: url)
        #expect(manager.bookmark(for: url) == nil)
    }

    @Test("All bookmarks returns complete map")
    func allBookmarks() {
        let defaults = UserDefaults(suiteName: "BookmarkManagerTests-\(UUID().uuidString)")!
        let manager = BookmarkManager(defaults: defaults, bookmarksKey: "test.bookmarks")

        let url1 = URL(fileURLWithPath: "/tmp/a.md")
        let url2 = URL(fileURLWithPath: "/tmp/b.md")
        let data1 = Data("data1".utf8)
        let data2 = Data("data2".utf8)

        defaults.set([
            url1.absoluteString: data1,
            url2.absoluteString: data2,
        ], forKey: "test.bookmarks")

        let all = manager.allBookmarks()
        #expect(all.count == 2)
        #expect(all[url1.absoluteString] == data1)
        #expect(all[url2.absoluteString] == data2)
    }

    @Test("Empty bookmarks returns empty dictionary")
    func emptyBookmarks() {
        let defaults = UserDefaults(suiteName: "BookmarkManagerTests-\(UUID().uuidString)")!
        let manager = BookmarkManager(defaults: defaults, bookmarksKey: "test.bookmarks")

        #expect(manager.allBookmarks().isEmpty)
    }
}
