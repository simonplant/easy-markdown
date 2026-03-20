import EMCore
import EMParser
import Foundation

/// Detects lines with trailing whitespace.
///
/// Trailing whitespace is invisible and can cause unexpected behavior in
/// some markdown renderers. This rule scans the raw text line-by-line.
///
/// Exception: Two trailing spaces before a line break are intentional
/// (CommonMark hard line break) and are not flagged.
struct TrailingWhitespaceRule: DoctorRule {
    let ruleID = "trailing-whitespace"

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let text = context.text
        var diagnostics: [Diagnostic] = []
        var lineNumber = 1
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]

            if hasTrailingWhitespace(line) {
                let trimmed = line.reversed().drop(while: { $0 == " " || $0 == "\t" })
                let trailingCount = line.count - trimmed.count

                // Two trailing spaces = intentional hard line break (CommonMark)
                let isHardBreak = trailingCount == 2 && !line.allSatisfy({ $0 == " " || $0 == "\t" })
                if !isHardBreak {
                    let startOffset = text.utf8.distance(from: text.startIndex, to: lineStart)
                        + text[lineStart..<lineEnd].utf8.count - trailingCount
                    diagnostics.append(Diagnostic(
                        ruleID: ruleID,
                        message: "Trailing whitespace (\(trailingCount) character\(trailingCount == 1 ? "" : "s")).",
                        severity: .warning,
                        line: lineNumber,
                        fix: DiagnosticFix(
                            label: "Remove whitespace",
                            range: DiagnosticTextRange(
                                startOffset: startOffset,
                                length: trailingCount
                            ),
                            replacement: ""
                        )
                    ))
                }
            }

            lineNumber += 1
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }

        return diagnostics
    }

    private func hasTrailingWhitespace(_ line: Substring) -> Bool {
        guard let last = line.last else { return false }
        return last == " " || last == "\t"
    }
}
