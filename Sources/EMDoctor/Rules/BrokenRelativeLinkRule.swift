import EMCore
import EMParser
import Foundation

/// Detects broken relative links and images in the document.
///
/// Checks `[text](path)` and `![alt](path)` where the path is a relative
/// file reference. Skips URLs (http/https), anchors (#), and mailto links.
/// For unsaved documents (no fileURL), all relative links are skipped since
/// they cannot be resolved.
struct BrokenRelativeLinkRule: DoctorRule {
    let ruleID = "broken-relative-link"

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        guard let fileURL = context.fileURL else { return [] }
        let baseDirectory = fileURL.deletingLastPathComponent()

        var diagnostics: [Diagnostic] = []
        collectBrokenLinks(in: context.ast.root, baseDirectory: baseDirectory, into: &diagnostics)
        return diagnostics
    }

    private func collectBrokenLinks(
        in node: MarkdownNode,
        baseDirectory: URL,
        into diagnostics: inout [Diagnostic]
    ) {
        switch node.type {
        case .link(let destination):
            if let dest = destination, let line = node.range?.start.line {
                checkDestination(dest, line: line, kind: "Link", baseDirectory: baseDirectory, into: &diagnostics)
            }
        case .image(let source):
            if let src = source, let line = node.range?.start.line {
                checkDestination(src, line: line, kind: "Image", baseDirectory: baseDirectory, into: &diagnostics)
            }
        default:
            break
        }

        for child in node.children {
            collectBrokenLinks(in: child, baseDirectory: baseDirectory, into: &diagnostics)
        }
    }

    private func checkDestination(
        _ destination: String,
        line: Int,
        kind: String,
        baseDirectory: URL,
        into diagnostics: inout [Diagnostic]
    ) {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)

        // Skip non-file destinations
        if trimmed.isEmpty { return }
        if trimmed.hasPrefix("#") { return }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return }
        if trimmed.hasPrefix("mailto:") { return }
        if trimmed.hasPrefix("tel:") { return }
        if trimmed.hasPrefix("data:") { return }

        // Strip any anchor fragment from the path
        let pathPart: String
        if let hashIndex = trimmed.firstIndex(of: "#") {
            pathPart = String(trimmed[trimmed.startIndex..<hashIndex])
        } else {
            pathPart = trimmed
        }

        guard !pathPart.isEmpty else { return }

        // Resolve relative to the document's directory
        let resolvedURL = baseDirectory.appendingPathComponent(pathPart).standardized
        let filePath = resolvedURL.path

        if !FileManager.default.fileExists(atPath: filePath) {
            diagnostics.append(Diagnostic(
                ruleID: ruleID,
                message: "\(kind) target not found: \"\(trimmed)\".",
                severity: .warning,
                line: line
            ))
        }
    }
}
