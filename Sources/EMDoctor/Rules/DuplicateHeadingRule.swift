import EMCore
import EMParser

/// Detects duplicate headings at the same level.
///
/// Duplicate headings can cause confusion in document navigation and
/// table-of-contents generation. This rule flags headings with identical
/// text content at the same level.
struct DuplicateHeadingRule: DoctorRule {
    let ruleID = "duplicate-heading"

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let headings = collectHeadings(in: context.ast.root)

        // Group by (level, normalized text)
        var seen: [String: Int] = [:]  // key → first occurrence line
        var diagnostics: [Diagnostic] = []

        for heading in headings {
            let key = "\(heading.level):\(heading.text.lowercased().trimmingCharacters(in: .whitespaces))"
            if let firstLine = seen[key] {
                diagnostics.append(Diagnostic(
                    ruleID: ruleID,
                    message: "Duplicate heading: \"\(heading.text)\" (same as line \(firstLine)).",
                    severity: .warning,
                    line: heading.line
                ))
            } else {
                seen[key] = heading.line
            }
        }

        return diagnostics
    }

    private struct HeadingInfo {
        let level: Int
        let text: String
        let line: Int
    }

    private func collectHeadings(in node: MarkdownNode) -> [HeadingInfo] {
        var result: [HeadingInfo] = []
        collectHeadingsRecursive(in: node, into: &result)
        return result
    }

    private func collectHeadingsRecursive(in node: MarkdownNode, into result: inout [HeadingInfo]) {
        if case .heading(let level) = node.type, let range = node.range {
            let text = extractText(from: node)
            result.append(HeadingInfo(level: level, text: text, line: range.start.line))
        }
        for child in node.children {
            collectHeadingsRecursive(in: child, into: &result)
        }
    }

    /// Extracts the plain text content of a node by concatenating all text children.
    private func extractText(from node: MarkdownNode) -> String {
        if let text = node.literalText {
            return text
        }
        return node.children.map { extractText(from: $0) }.joined()
    }
}
