import Testing
import Foundation
@testable import EMFile
@testable import EMCore

@Suite("FileValidator")
struct FileValidatorTests {

    let testURL = URL(fileURLWithPath: "/tmp/test.md")

    @Test("Validates valid UTF-8 data")
    func validUTF8() throws {
        let text = "# Hello\n\nThis is valid UTF-8 markdown."
        let data = text.data(using: .utf8)!
        let content = try FileValidator.validate(data: data, from: testURL)

        #expect(content.text == text)
        #expect(content.fileSize == data.count)
        #expect(content.url == testURL)
        #expect(content.lineEnding == .lf)
    }

    @Test("Rejects non-UTF-8 data")
    func invalidUTF8() {
        // Latin-1 encoded text with a byte (0xFF) that is invalid UTF-8
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0x00])

        #expect(throws: EMError.self) {
            try FileValidator.validate(data: data, from: testURL)
        }
    }

    @Test("Detects CRLF line endings in content")
    func detectsCRLF() throws {
        let text = "line one\r\nline two\r\n"
        let data = text.data(using: .utf8)!
        let content = try FileValidator.validate(data: data, from: testURL)

        #expect(content.lineEnding == .crlf)
    }

    @Test("Detects LF line endings in content")
    func detectsLF() throws {
        let text = "line one\nline two\n"
        let data = text.data(using: .utf8)!
        let content = try FileValidator.validate(data: data, from: testURL)

        #expect(content.lineEnding == .lf)
    }

    @Test("Reports correct file size")
    func reportsFileSize() throws {
        let text = "Hello, world!"
        let data = text.data(using: .utf8)!
        let content = try FileValidator.validate(data: data, from: testURL)

        #expect(content.fileSize == 13)
    }

    @Test("Large file detection threshold")
    func largeFileThreshold() {
        #expect(FileValidator.isLargeFile(sizeBytes: 999_999) == false)
        #expect(FileValidator.isLargeFile(sizeBytes: 1_000_000) == false)
        #expect(FileValidator.isLargeFile(sizeBytes: 1_000_001) == true)
    }

    @Test("Empty file is valid")
    func emptyFile() throws {
        let data = Data()
        let content = try FileValidator.validate(data: data, from: testURL)

        #expect(content.text == "")
        #expect(content.fileSize == 0)
        #expect(content.lineEnding == .lf)
    }
}
