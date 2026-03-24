import Testing
import Foundation
@testable import EMFile
@testable import EMCore

@Suite("ImageSaveService")
struct ImageSaveServiceTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func createDir(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Save

    @Test("Saves image data to disk")
    func saveImageData() throws {
        let dir = tempDir()
        try createDir(dir)
        let url = dir.appendingPathComponent("test.png")
        let data = Data(repeating: 0xFF, count: 100)

        try ImageSaveService.save(data: data, to: url)

        let saved = try Data(contentsOf: url)
        #expect(saved == data)
    }

    @Test("Save creates file atomically")
    func saveAtomic() throws {
        let dir = tempDir()
        try createDir(dir)
        let url = dir.appendingPathComponent("atomic.png")
        let data = Data(repeating: 0xAB, count: 1024)

        try ImageSaveService.save(data: data, to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let readBack = try Data(contentsOf: url)
        #expect(readBack.count == 1024)
    }

    @Test("Save to invalid path throws")
    func saveInvalidPath() {
        let url = URL(fileURLWithPath: "/nonexistent/deep/path/image.png")
        let data = Data(repeating: 0, count: 10)

        #expect(throws: EMError.self) {
            try ImageSaveService.save(data: data, to: url)
        }
    }

    // MARK: - Relative Path

    @Test("Relative path for image in same directory")
    func relativePathSameDir() {
        let docURL = URL(fileURLWithPath: "/Users/test/docs/readme.md")
        let imageURL = URL(fileURLWithPath: "/Users/test/docs/photo.png")

        let result = ImageSaveService.relativePath(from: docURL, to: imageURL)
        #expect(result == "photo.png")
    }

    @Test("Relative path for image in subdirectory")
    func relativePathSubdir() {
        let docURL = URL(fileURLWithPath: "/Users/test/docs/readme.md")
        let imageURL = URL(fileURLWithPath: "/Users/test/docs/images/photo.png")

        let result = ImageSaveService.relativePath(from: docURL, to: imageURL)
        #expect(result == "images/photo.png")
    }

    @Test("Relative path for image in parent directory")
    func relativePathParentDir() {
        let docURL = URL(fileURLWithPath: "/Users/test/docs/sub/readme.md")
        let imageURL = URL(fileURLWithPath: "/Users/test/docs/photo.png")

        let result = ImageSaveService.relativePath(from: docURL, to: imageURL)
        #expect(result == "../photo.png")
    }

    @Test("Relative path for image in sibling directory")
    func relativePathSiblingDir() {
        let docURL = URL(fileURLWithPath: "/Users/test/docs/readme.md")
        let imageURL = URL(fileURLWithPath: "/Users/test/images/photo.png")

        let result = ImageSaveService.relativePath(from: docURL, to: imageURL)
        #expect(result == "../images/photo.png")
    }

    @Test("Relative path with nil document URL returns filename")
    func relativePathNilDoc() {
        let imageURL = URL(fileURLWithPath: "/Users/test/images/photo.png")

        let result = ImageSaveService.relativePath(from: nil, to: imageURL)
        #expect(result == "photo.png")
    }

    // MARK: - Suggested Filename

    @Test("Suggested filename has expected format")
    func suggestedFilename() {
        let name = ImageSaveService.suggestedFilename(extension: "png")
        #expect(name.hasPrefix("image-"))
        #expect(name.hasSuffix(".png"))
        #expect(name.count > 15) // "image-" + date + ".png"
    }

    @Test("Suggested filename respects extension")
    func suggestedFilenameExtension() {
        let jpg = ImageSaveService.suggestedFilename(extension: "jpg")
        #expect(jpg.hasSuffix(".jpg"))

        let gif = ImageSaveService.suggestedFilename(extension: "gif")
        #expect(gif.hasSuffix(".gif"))
    }
}
