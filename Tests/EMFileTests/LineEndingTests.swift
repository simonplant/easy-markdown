import Testing
import Foundation
import EMCore

@Suite("LineEnding")
struct LineEndingTests {

    @Test("Detects LF line endings")
    func detectLF() {
        let text = "line one\nline two\nline three\n"
        #expect(LineEnding.detect(in: text) == .lf)
    }

    @Test("Detects CRLF line endings")
    func detectCRLF() {
        let text = "line one\r\nline two\r\nline three\r\n"
        #expect(LineEnding.detect(in: text) == .crlf)
    }

    @Test("Defaults to LF when no line endings present")
    func detectNoLineEndings() {
        let text = "single line with no endings"
        #expect(LineEnding.detect(in: text) == .lf)
    }

    @Test("Mixed line endings resolved by majority")
    func detectMixed() {
        // 2 CRLF vs 1 LF → CRLF wins
        let text = "line one\r\nline two\r\nline three\n"
        #expect(LineEnding.detect(in: text) == .crlf)
    }

    @Test("Apply LF preserves LF text unchanged")
    func applyLFtoLF() {
        let text = "one\ntwo\nthree\n"
        #expect(LineEnding.lf.apply(to: text) == text)
    }

    @Test("Apply CRLF converts LF to CRLF")
    func applyLFtoCRLF() {
        let text = "one\ntwo\nthree\n"
        let expected = "one\r\ntwo\r\nthree\r\n"
        #expect(LineEnding.crlf.apply(to: text) == expected)
    }

    @Test("Apply LF converts CRLF to LF")
    func applyCRLFtoLF() {
        let text = "one\r\ntwo\r\nthree\r\n"
        let expected = "one\ntwo\nthree\n"
        #expect(LineEnding.lf.apply(to: text) == expected)
    }

    @Test("Apply CRLF preserves CRLF text unchanged")
    func applyCRLFtoCRLF() {
        let text = "one\r\ntwo\r\nthree\r\n"
        #expect(LineEnding.crlf.apply(to: text) == text)
    }

    @Test("Apply normalizes mixed endings")
    func applyNormalizesMixed() {
        let text = "one\r\ntwo\nthree\r\n"
        let expectedLF = "one\ntwo\nthree\n"
        let expectedCRLF = "one\r\ntwo\r\nthree\r\n"
        #expect(LineEnding.lf.apply(to: text) == expectedLF)
        #expect(LineEnding.crlf.apply(to: text) == expectedCRLF)
    }

    @Test("Empty string detection returns LF")
    func detectEmpty() {
        #expect(LineEnding.detect(in: "") == .lf)
    }
}
