import Testing
import Foundation
@testable import EMDoctor
@testable import EMParser
@testable import EMCore

@Suite("DoctorEngine")
struct DoctorEngineTests {

    private let parser = MarkdownParser()

    private func context(for text: String, fileURL: URL? = nil) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: fileURL)
    }

    // MARK: - Engine

    @Test("Engine runs all rules and returns sorted diagnostics")
    func engineRunsAllRules() {
        let text = """
        # Heading

        ### Skipped Level

        ### Skipped Level
        """
        let ctx = context(for: text)
        let engine = DoctorEngine()
        let diagnostics = engine.evaluate(ctx)

        // Should find heading hierarchy skip and duplicate heading
        #expect(diagnostics.count >= 2)
        // Should be sorted by line
        for i in 1..<diagnostics.count {
            #expect(diagnostics[i].line >= diagnostics[i - 1].line)
        }
    }

    @Test("Engine with no rules returns empty")
    func engineNoRules() {
        let ctx = context(for: "# Hello\n\nSome text")
        let engine = DoctorEngine(rules: [])
        let diagnostics = engine.evaluate(ctx)
        #expect(diagnostics.isEmpty)
    }

    @Test("Clean document produces no diagnostics")
    func cleanDocument() {
        let text = """
        # Title

        Some text here.

        ## Section

        More text.

        ### Subsection

        Content.
        """
        let ctx = context(for: text)
        let engine = DoctorEngine()
        let diagnostics = engine.evaluate(ctx)
        #expect(diagnostics.isEmpty)
    }

    @Test("AC-8: Evaluates a 3000-line document within 2 seconds")
    func performanceLargeDocument() {
        // Generate a 3000-line markdown document with varied structure
        var lines: [String] = []
        for i in 1...3000 {
            switch i % 30 {
            case 0:
                lines.append("## Section \(i / 30)")
            case 1:
                lines.append("")
            case 15:
                lines.append("### Subsection \(i)")
            case 16:
                lines.append("")
            default:
                lines.append("This is paragraph text on line \(i) with some content to make it realistic.")
            }
        }
        let text = lines.joined(separator: "\n")
        let ctx = context(for: text)
        let engine = DoctorEngine()

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = engine.evaluate(ctx)
        }

        #expect(elapsed < .seconds(2), "Doctor evaluation of 3000-line document took \(elapsed), exceeds 2s limit")
    }
}

@Suite("HeadingHierarchyRule")
struct HeadingHierarchyRuleTests {

    private let parser = MarkdownParser()
    private let rule = HeadingHierarchyRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags H1 to H3 skip")
    func flagsSkip() {
        let text = "# Title\n\n### Skipped"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "heading-hierarchy")
        #expect(diagnostics[0].message.contains("H3"))
        #expect(diagnostics[0].message.contains("H1"))
    }

    @Test("No flag for sequential headings")
    func noFlagSequential() {
        let text = "# Title\n\n## Section\n\n### Sub"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("No flag for going shallower")
    func noFlagShallower() {
        let text = "# Title\n\n## Section\n\n### Sub\n\n# Another Title"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Single heading produces no diagnostic")
    func singleHeading() {
        let text = "## Just One"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Multiple skips flagged independently")
    func multipleSkips() {
        let text = "# Title\n\n### Skip1\n\n###### Skip2"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 2)
    }
}

@Suite("DuplicateHeadingRule")
struct DuplicateHeadingRuleTests {

    private let parser = MarkdownParser()
    private let rule = DuplicateHeadingRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags duplicate headings at same level")
    func flagsDuplicate() {
        let text = "## Features\n\nSome text\n\n## Features"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "duplicate-heading")
        #expect(diagnostics[0].message.contains("Features"))
    }

    @Test("Same text at different levels is not duplicate")
    func differentLevelsNotDuplicate() {
        let text = "# Title\n\n## Title"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Case-insensitive duplicate detection")
    func caseInsensitive() {
        let text = "## Setup\n\nText\n\n## setup"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
    }

    @Test("No duplicates in unique headings")
    func noDuplicates() {
        let text = "# Title\n\n## First\n\n## Second\n\n## Third"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }
}

@Suite("BrokenRelativeLinkRule")
struct BrokenRelativeLinkRuleTests {

    private let parser = MarkdownParser()
    private let rule = BrokenRelativeLinkRule()

    private func context(for text: String, fileURL: URL? = nil) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: fileURL)
    }

    @Test("Skips evaluation for unsaved documents")
    func skipsUnsaved() {
        let text = "[link](./missing.md)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: nil))
        #expect(diagnostics.isEmpty)
    }

    @Test("Skips http/https URLs")
    func skipsHTTP() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[link](https://example.com)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.isEmpty)
    }

    @Test("Skips anchor links")
    func skipsAnchors() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[section](#heading)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.isEmpty)
    }

    @Test("Skips mailto links")
    func skipsMailto() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[email](mailto:test@example.com)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.isEmpty)
    }

    @Test("Flags broken relative link")
    func flagsBrokenLink() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[link](./definitely-nonexistent-file-abc123.md)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "broken-relative-link")
    }

    @Test("Flags broken image source")
    func flagsBrokenImage() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "![alt](./nonexistent-image-xyz789.png)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("Image"))
    }
}

@Suite("TrailingWhitespaceRule")
struct TrailingWhitespaceRuleTests {

    private let parser = MarkdownParser()
    private let rule = TrailingWhitespaceRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags trailing spaces")
    func flagsTrailingSpaces() {
        let text = "Hello   \nWorld"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "trailing-whitespace")
        #expect(diagnostics[0].fix != nil)
        #expect(diagnostics[0].fix?.replacement == "")
    }

    @Test("Flags trailing tabs")
    func flagsTrailingTabs() {
        let text = "Hello\t\nWorld"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
    }

    @Test("Skips two trailing spaces (hard line break)")
    func skipsHardBreak() {
        let text = "Hello  \nWorld"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("No trailing whitespace is clean")
    func cleanLines() {
        let text = "Hello\nWorld\nTest"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Multiple lines with trailing whitespace")
    func multipleLines() {
        let text = "Line 1   \nLine 2\nLine 3 "
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 2)
    }
}

@Suite("MissingBlankLineRule")
struct MissingBlankLineRuleTests {

    private let parser = MarkdownParser()
    private let rule = MissingBlankLineRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags heading followed directly by paragraph")
    func flagsHeadingParagraph() {
        let text = "# Title\nSome text"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count >= 1)
        #expect(diagnostics[0].ruleID == "missing-blank-line")
        #expect(diagnostics[0].fix != nil)
    }

    @Test("No flag when blank line exists")
    func noFlagWithBlankLine() {
        let text = "# Title\n\nSome text"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Fix inserts blank line")
    func fixInsertsBlankLine() {
        let text = "# Title\nSome text"
        let diagnostics = rule.evaluate(context(for: text))
        if let fix = diagnostics.first?.fix {
            #expect(fix.replacement == "\n")
            #expect(fix.label == "Insert blank line")
        }
    }
}

// MARK: - FEAT-022 Extended Doctor Rules

@Suite("LongSentenceRule")
struct LongSentenceRuleTests {

    private let parser = MarkdownParser()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("AC-1: Flags a 60-word sentence")
    func flags60WordSentence() {
        // Build a sentence with exactly 60 words
        let words = (1...60).map { "word\($0)" }
        let text = words.joined(separator: " ") + "."
        let rule = LongSentenceRule(threshold: 50)
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "long-sentence")
        #expect(diagnostics[0].message.contains("60"))
        #expect(diagnostics[0].message.contains("breaking it up"))
    }

    @Test("Does not flag a short sentence")
    func noFlagShort() {
        let text = "This is a short sentence."
        let rule = LongSentenceRule(threshold: 50)
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Does not flag exactly threshold words")
    func noFlagExactThreshold() {
        let words = (1...50).map { "word\($0)" }
        let text = words.joined(separator: " ") + "."
        let rule = LongSentenceRule(threshold: 50)
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Flags multiple long sentences independently")
    func flagsMultiple() {
        let longSentence = (1...55).map { "word\($0)" }.joined(separator: " ") + "."
        let text = longSentence + " " + longSentence
        let rule = LongSentenceRule(threshold: 50)
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 2)
    }

    @Test("No fix provided — informational only")
    func noFix() {
        let words = (1...55).map { "word\($0)" }
        let text = words.joined(separator: " ") + "."
        let rule = LongSentenceRule(threshold: 50)
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.first?.fix == nil)
    }

    @Test("Empty document produces no diagnostics")
    func emptyDocument() {
        let rule = LongSentenceRule()
        let diagnostics = rule.evaluate(context(for: ""))
        #expect(diagnostics.isEmpty)
    }
}

@Suite("PassiveVoiceRule")
struct PassiveVoiceRuleTests {

    private let parser = MarkdownParser()
    private let rule = PassiveVoiceRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags was + past participle")
    func flagsWasPastParticiple() {
        let text = "The report was written by the team."
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count >= 1)
        #expect(diagnostics[0].ruleID == "passive-voice")
        #expect(diagnostics[0].message.contains("passive voice") || diagnostics[0].message.contains("Passive voice"))
    }

    @Test("Does not flag active voice")
    func noFlagActive() {
        let text = "The team wrote the report."
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Empty document produces no diagnostics")
    func emptyDocument() {
        let diagnostics = rule.evaluate(context(for: ""))
        #expect(diagnostics.isEmpty)
    }
}

@Suite("RepeatedWordRule")
struct RepeatedWordRuleTests {

    private let parser = MarkdownParser()
    private let rule = RepeatedWordRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags repeated adjacent word")
    func flagsRepeated() {
        let text = "The the cat sat on the mat."
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "repeated-word")
        #expect(diagnostics[0].message.lowercased().contains("the"))
    }

    @Test("Provides fix to remove duplicate")
    func providesFix() {
        let text = "The the cat sat."
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.first?.fix != nil)
        #expect(diagnostics.first?.fix?.label == "Remove duplicate")
        #expect(diagnostics.first?.fix?.replacement == "")
    }

    @Test("Case-insensitive detection")
    func caseInsensitive() {
        let text = "The the cat."
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
    }

    @Test("No flag for different words")
    func noFlagDifferent() {
        let text = "The cat sat on the mat."
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("No flag for same word on different lines")
    func noFlagCrossLine() {
        let text = "word\nword"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Empty document produces no diagnostics")
    func emptyDocument() {
        let diagnostics = rule.evaluate(context(for: ""))
        #expect(diagnostics.isEmpty)
    }
}

@Suite("DoctorEngine Prose Mode")
struct DoctorEngineProseTests {

    private let parser = MarkdownParser()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Engine with prose suggestions includes prose rules")
    func proseEngineIncludesRules() {
        let engine = DoctorEngine(includingProseSuggestions: true)
        let ruleIDs = engine.rules.map { $0.ruleID }
        #expect(ruleIDs.contains("long-sentence"))
        #expect(ruleIDs.contains("passive-voice"))
        #expect(ruleIDs.contains("repeated-word"))
    }

    @Test("Engine without prose suggestions excludes prose rules")
    func structuralOnlyEngine() {
        let engine = DoctorEngine(includingProseSuggestions: false)
        let ruleIDs = engine.rules.map { $0.ruleID }
        #expect(!ruleIDs.contains("long-sentence"))
        #expect(!ruleIDs.contains("passive-voice"))
        #expect(!ruleIDs.contains("repeated-word"))
    }

    @Test("Default engine excludes prose rules")
    func defaultEngine() {
        let engine = DoctorEngine()
        let ruleIDs = engine.rules.map { $0.ruleID }
        #expect(!ruleIDs.contains("long-sentence"))
    }
}
