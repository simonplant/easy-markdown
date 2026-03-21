import EMCore
import EMParser
import Foundation
import NaturalLanguage

/// Flags passive voice constructions per FEAT-022.
///
/// Detects common passive voice patterns (e.g., "was written", "is being done")
/// using NLTagger part-of-speech analysis. Passive voice makes prose less direct;
/// this rule suggests rewriting in active voice.
struct PassiveVoiceRule: DoctorRule {
    let ruleID = "passive-voice"

    /// Common "be" forms that precede past participles in passive constructions.
    private static let beForms: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being",
    ]

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let text = context.text
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var diagnostics: [Diagnostic] = []
        var previousTag: NLTag?
        var previousWord: String?
        var previousRange: Range<String.Index>?

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let word = String(text[tokenRange]).lowercased()

            if let prevTag = previousTag,
               let prevWord = previousWord,
               let prevRange = previousRange,
               Self.beForms.contains(prevWord),
               prevTag == .verb,
               tag == .verb {
                // "be-form + verb" pattern detected — likely passive voice
                let line = lineNumber(for: prevRange.lowerBound, in: text)
                let currentWord = String(text[tokenRange])
                diagnostics.append(Diagnostic(
                    ruleID: ruleID,
                    message: "Passive voice: \"\(prevWord) \(currentWord)\" — consider rewriting in active voice.",
                    severity: .warning,
                    line: line
                ))
            }

            previousTag = tag
            previousWord = word
            previousRange = tokenRange
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
