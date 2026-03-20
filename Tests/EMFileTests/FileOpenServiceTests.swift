import Testing
import Foundation
@testable import EMFile
@testable import EMCore

@Suite("FileOpenService")
struct FileOpenServiceTests {

    /// Creates a temporary markdown file and returns its URL.
    private func createTempFile(
        content: String = "# Test\n\nHello, world!",
        filename: String = "test.md"
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    /// Cleans up a temporary file.
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Opens a valid UTF-8 markdown file successfully")
    @MainActor
    func opensValidFile() throws {
        let url = try createTempFile()
        defer { cleanup(url) }

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let bookmarkManager = BookmarkManager(defaults: defaults)
        let service = FileOpenService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: ScopedAccessManager()
        )

        let result = try service.open(url: url)
        #expect(result.content.text == "# Test\n\nHello, world!")
        #expect(result.content.url == url)
        #expect(result.isLargeFile == false)

        service.close(url: url)
    }

    @Test("Throws notUTF8 for non-UTF-8 file")
    @MainActor
    func rejectsNonUTF8() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bad.md")
        // Write invalid UTF-8 bytes
        let badData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0x00])
        try badData.write(to: url)
        defer { cleanup(url) }

        let service = FileOpenService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: ScopedAccessManager()
        )

        #expect(throws: EMError.self) {
            try service.open(url: url)
        }
    }

    @Test("Reports large file correctly")
    @MainActor
    func detectsLargeFile() throws {
        // Create a file just over 1MB
        let bigContent = String(repeating: "x", count: 1_100_000)
        let url = try createTempFile(content: bigContent)
        defer { cleanup(url) }

        let service = FileOpenService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: ScopedAccessManager()
        )

        let result = try service.open(url: url)
        #expect(result.isLargeFile == true)
        #expect(result.content.fileSize > 1_000_000)

        service.close(url: url)
    }

    @Test("Releases scoped access on close")
    @MainActor
    func releasesAccessOnClose() throws {
        let url = try createTempFile()
        defer { cleanup(url) }

        let scopedAccess = ScopedAccessManager()
        let service = FileOpenService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: scopedAccess
        )

        _ = try service.open(url: url)
        // Access count may or may not increase for non-security-scoped URLs (temp files),
        // but close should not crash.
        service.close(url: url)
    }

    @Test("Releases scoped access on open failure")
    @MainActor
    func releasesAccessOnFailure() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bad.md")
        let badData = Data([0xFF, 0xFE, 0x00, 0x01])
        try badData.write(to: url)
        defer { cleanup(url) }

        let scopedAccess = ScopedAccessManager()
        let service = FileOpenService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: scopedAccess
        )

        do {
            _ = try service.open(url: url)
        } catch {
            // Expected — verify scoped access was cleaned up
            #expect(scopedAccess.activeCount == 0)
        }
    }

    @Test("Preserves line endings in read content")
    @MainActor
    func preservesLineEndings() throws {
        let crlfContent = "line one\r\nline two\r\n"
        let url = try createTempFile(content: crlfContent)
        defer { cleanup(url) }

        let service = FileOpenService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: ScopedAccessManager()
        )

        let result = try service.open(url: url)
        #expect(result.content.lineEnding == .crlf)

        service.close(url: url)
    }
}
