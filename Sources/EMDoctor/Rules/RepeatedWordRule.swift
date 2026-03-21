import EMCore
import EMParser
import Foundation
import NaturalLanguage

/// Flags repeated adjacent words per FEAT-022.
///
/// Detects consecutive duplicate words (e.g., "the the", "is is") which are
/// almost always typos. Uses NLTokenizer for language-aware word boundaries.
/// Case-insensitive comparison.
struct RepeatedWordRule: DoctorRule {
    let ruleID = "repeated-word"

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let text = context.text
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var diagnostics: [Diagnostic] = []
        var previousWord: String?
        var previousRange: Range<String.Index>?

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange])
            let lowered = word.lowercased()

            // Only flag if they are on the same line (cross-line repetition is normal)
            if let prevWord = previousWord,
               let prevRange = previousRange,
               prevWord == lowered,
               !spansNewline(from: prevRange.upperBound, to: tokenRange.lowerBound, in: text) {
                let line = lineNumber(for: tokenRange.lowerBound, in: text)
                // Include preceding whitespace in the fix range so removal
                // doesn't leave a double space (e.g., "the the" → "the").
                let fixStart = prevRange.upperBound
                let utf8Offset = text.utf8.distance(from: text.startIndex, to: fixStart)
                let utf8Length = text.utf8.distance(from: fixStart, to: tokenRange.upperBound)

                diagnostics.append(Diagnostic(
                    ruleID: ruleID,
                    message: "Repeated word: \"\(word)\".",
                    severity: .warning,
                    line: line,
                    fix: DiagnosticFix(
                        label: "Remove duplicate",
                        range: DiagnosticTextRange(
                            startOffset: utf8Offset,
                            length: utf8Length
                        ),
                        replacement: ""
                    )
                ))
            }

            previousWord = lowered
            previousRange = tokenRange
            return true
        }

        return diagnostics
    }

    /// Checks if the text between two indices contains a newline.
    private func spansNewline(from: String.Index, to: String.Index, in text: String) -> Bool {
        guard from < to else { return false }
        return text[from..<to].contains("\n")
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
