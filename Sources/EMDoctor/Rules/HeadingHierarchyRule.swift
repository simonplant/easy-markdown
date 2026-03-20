import EMCore
import EMParser

/// Detects heading level skips (e.g., H1 → H3 without H2).
///
/// A well-structured document should not skip heading levels. This rule
/// walks all headings in document order and flags any that jump more than
/// one level deeper than the previous heading.
struct HeadingHierarchyRule: DoctorRule {
    let ruleID = "heading-hierarchy"

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let headings = collectHeadings(in: context.ast.root)
        guard headings.count > 1 else { return [] }

        var diagnostics: [Diagnostic] = []
        var previousLevel = headings[0].level

        for i in 1..<headings.count {
            let current = headings[i]
            // Only flag when going deeper and skipping levels.
            // Going shallower (e.g., H3 → H1) is valid structure.
            if current.level > previousLevel + 1 {
                let line = current.line
                let expected = previousLevel + 1
                diagnostics.append(Diagnostic(
                    ruleID: ruleID,
                    message: "Heading level skipped: H\(current.level) after H\(previousLevel). Expected H\(expected) or less.",
                    severity: .warning,
                    line: line
                ))
            }
            previousLevel = current.level
        }

        return diagnostics
    }

    private struct HeadingInfo {
        let level: Int
        let line: Int
    }

    private func collectHeadings(in node: MarkdownNode) -> [HeadingInfo] {
        var result: [HeadingInfo] = []
        collectHeadingsRecursive(in: node, into: &result)
        return result
    }

    private func collectHeadingsRecursive(in node: MarkdownNode, into result: inout [HeadingInfo]) {
        if case .heading(let level) = node.type, let range = node.range {
            result.append(HeadingInfo(level: level, line: range.start.line))
        }
        for child in node.children {
            collectHeadingsRecursive(in: child, into: &result)
        }
    }
}
