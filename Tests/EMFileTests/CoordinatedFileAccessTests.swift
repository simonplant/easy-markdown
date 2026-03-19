import Testing
import Foundation
@testable import EMFile
@testable import EMCore

@Suite("CoordinatedFileAccess")
struct CoordinatedFileAccessTests {

    private func tempURL(_ name: String = "test.md") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
    }

    private func createTempFile(content: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.data(using: .utf8)!.write(to: url)
    }

    @Test("Reads valid UTF-8 file")
    func readValidFile() throws {
        let url = tempURL()
        let text = "# Test\n\nHello, world!\n"
        try createTempFile(content: text, at: url)

        let content = try CoordinatedFileAccess.read(from: url)
        #expect(content.text == text)
        #expect(content.lineEnding == .lf)
        #expect(content.fileSize > 0)
    }

    @Test("Read throws for missing file")
    func readMissingFile() {
        let url = tempURL("nonexistent.md")

        #expect(throws: EMError.self) {
            try CoordinatedFileAccess.read(from: url)
        }
    }

    @Test("Writes and reads back content")
    func writeAndReadBack() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let text = "# Written\n\nContent here.\n"
        try CoordinatedFileAccess.write(text: text, to: url)

        let content = try CoordinatedFileAccess.read(from: url)
        #expect(content.text == text)
    }

    @Test("Preserves CRLF line endings on write")
    func preservesCRLF() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let text = "line one\nline two\nline three\n"
        try CoordinatedFileAccess.write(text: text, to: url, lineEnding: .crlf)

        let data = try Data(contentsOf: url)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "line one\r\nline two\r\nline three\r\n")
    }

    @Test("Preserves LF line endings on write")
    func preservesLF() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let text = "line one\r\nline two\r\n"
        try CoordinatedFileAccess.write(text: text, to: url, lineEnding: .lf)

        let data = try Data(contentsOf: url)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "line one\nline two\n")
    }

    @Test("Round-trip preserves CRLF file")
    func roundTripCRLF() throws {
        let url = tempURL()
        let original = "first\r\nsecond\r\nthird\r\n"
        try createTempFile(content: original, at: url)

        let content = try CoordinatedFileAccess.read(from: url)
        #expect(content.lineEnding == .crlf)

        // Edit the text (internally using LF as the editor would)
        let edited = "first\nsecond\nthird\nfourth\n"
        try CoordinatedFileAccess.write(text: edited, to: url, lineEnding: content.lineEnding)

        // Read back — should be CRLF
        let reread = try CoordinatedFileAccess.read(from: url)
        #expect(reread.lineEnding == .crlf)
        #expect(reread.text == "first\r\nsecond\r\nthird\r\nfourth\r\n")
    }
}
