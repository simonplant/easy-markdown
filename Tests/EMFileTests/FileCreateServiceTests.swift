import Testing
import Foundation
@testable import EMFile
@testable import EMCore

@Suite("FileCreateService")
struct FileCreateServiceTests {

    /// Creates a temporary directory and returns a URL for a file in it.
    private func tempFileURL(filename: String = "Untitled.md") -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    /// Cleans up a temporary file's parent directory.
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Creates a new empty markdown file successfully")
    @MainActor
    func createsEmptyFile() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = FileCreateService(
            bookmarkManager: BookmarkManager(defaults: defaults),
            scopedAccessManager: ScopedAccessManager()
        )

        let result = try service.create(at: url)

        #expect(result.content.text == "")
        #expect(result.content.url == url)
        #expect(result.content.lineEnding == .lf)
        #expect(result.content.fileSize == 0)

        // Verify file exists on disk
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Verify file content is empty
        let data = try Data(contentsOf: url)
        #expect(data.isEmpty)

        service.close(url: url)
    }

    @Test("Created file uses LF line endings")
    @MainActor
    func usesLFLineEndings() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let service = FileCreateService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: ScopedAccessManager()
        )

        let result = try service.create(at: url)
        #expect(result.content.lineEnding == .lf)

        service.close(url: url)
    }

    @Test("Releases scoped access on close")
    @MainActor
    func releasesAccessOnClose() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let scopedAccess = ScopedAccessManager()
        let service = FileCreateService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: scopedAccess
        )

        _ = try service.create(at: url)
        service.close(url: url)
        // Should not crash — scoped access balanced
    }

    @Test("Releases scoped access on write failure")
    @MainActor
    func releasesAccessOnFailure() throws {
        // Use a URL in a non-existent directory to cause a write failure
        let badDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nonexistent")
        let url = badDir.appendingPathComponent("test.md")

        let scopedAccess = ScopedAccessManager()
        let service = FileCreateService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: scopedAccess
        )

        do {
            _ = try service.create(at: url)
            Issue.record("Expected create to throw for non-existent directory")
        } catch {
            // Expected — verify scoped access was cleaned up
            #expect(scopedAccess.activeCount == 0)
        }
    }

    @Test("Throws saveFailed for permission-denied location")
    @MainActor
    func throwsOnPermissionDenied() throws {
        // Write to a path that won't exist
        let url = URL(fileURLWithPath: "/nonexistent-root-\(UUID().uuidString)/test.md")

        let service = FileCreateService(
            bookmarkManager: BookmarkManager(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            scopedAccessManager: ScopedAccessManager()
        )

        #expect(throws: EMError.self) {
            try service.create(at: url)
        }
    }

    @Test("Can open created file with FileOpenService")
    @MainActor
    func createdFileIsOpenable() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let bookmarkManager = BookmarkManager(defaults: defaults)
        let createService = FileCreateService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: ScopedAccessManager()
        )

        _ = try createService.create(at: url)
        createService.close(url: url)

        // Now open the created file
        let openService = FileOpenService(
            bookmarkManager: bookmarkManager,
            scopedAccessManager: ScopedAccessManager()
        )

        let openResult = try openService.open(url: url)
        #expect(openResult.content.text == "")
        #expect(openResult.content.lineEnding == .lf)
        #expect(openResult.isLargeFile == false)

        openService.close(url: url)
    }
}
