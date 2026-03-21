import EMCore
import EMParser
import Foundation
import NaturalLanguage

/// Flags sentences exceeding a word count threshold per FEAT-022.
///
/// Long sentences reduce readability. This rule uses `NLTokenizer` for
/// language-aware sentence and word segmentation, then flags any sentence
/// with more than `threshold` words (default: 50). Informational only —
/// the user navigates to the flagged line and edits manually.
struct LongSentenceRule: DoctorRule {
    let ruleID = "long-sentence"

    /// Word count threshold above which a sentence is flagged.
    let threshold: Int

    init(threshold: Int = 50) {
        self.threshold = threshold
    }

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let text = context.text
        guard !text.isEmpty else { return [] }

        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text

        let wordTokenizer = NLTokenizer(unit: .word)

        var diagnostics: [Diagnostic] = []

        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { sentenceRange, _ in
            // Count words in this sentence
            let sentenceStr = String(text[sentenceRange])
            wordTokenizer.string = sentenceStr
            var wordCount = 0
            wordTokenizer.enumerateTokens(in: sentenceStr.startIndex..<sentenceStr.endIndex) { _, _ in
                wordCount += 1
                return true
            }

            if wordCount > threshold {
                let line = lineNumber(for: sentenceRange.lowerBound, in: text)

                diagnostics.append(Diagnostic(
                    ruleID: ruleID,
                    message: "Sentence has \(wordCount) words — consider breaking it up for readability.",
                    severity: .warning,
                    line: line
                ))
            }
            return true
        }

        return diagnostics
    }

    /// Returns the 1-based line number for a string index.
    private func lineNumber(for index: String.Index, in text: String) -> Int {
        var line = 1
        var pos = text.startIndex
        while pos < index {
            if text[pos] == "\n" {
                line += 1
            }
            pos = text.index(after: pos)
        }
        return line
    }
}
