import Testing
import Foundation
@testable import EMParser

@Suite("Parser Performance")
struct PerformanceTests {

    @Test("10,000-line document parses in under 100ms")
    func largeDocumentPerformance() {
        // Build a realistic 10,000-line markdown document
        var lines: [String] = []
        lines.append("# Large Document\n")
        lines.append("")

        for section in 0..<100 {
            lines.append("## Section \(section)\n")
            lines.append("")
            // Paragraphs with inline formatting
            for para in 0..<30 {
                lines.append(
                    "This is paragraph \(para) with **bold**, *italic*, "
                    + "and `code` in section \(section). "
                    + "It has [a link](https://example.com/\(section)/\(para)).\n"
                )
                lines.append("")
            }
            // A code block
            lines.append("```swift")
            lines.append("func section\(section)() {")
            lines.append("    print(\"hello\")")
            lines.append("}")
            lines.append("```\n")
            lines.append("")
            // A list
            lines.append("- Item A in section \(section)")
            lines.append("- Item B in section \(section)")
            lines.append("- Item C in section \(section)\n")
            lines.append("")
        }

        let source = lines.joined(separator: "\n")
        let lineCount = source.components(separatedBy: "\n").count
        #expect(lineCount >= 10_000, "Test document should have at least 10,000 lines, got \(lineCount)")

        let parser = MarkdownParser()

        // Warm up
        _ = parser.parse(source)

        // Timed run
        let start = ContinuousClock.now
        let result = parser.parse(source)
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15

        #expect(ms < 100, "Parse took \(ms)ms, expected <100ms")
        #expect(result.ast.root.type == .document)
        #expect(result.ast.blocks.count > 0)
    }
}
