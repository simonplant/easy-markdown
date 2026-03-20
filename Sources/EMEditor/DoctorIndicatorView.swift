/// Doctor indicator overlay and popover per FEAT-005.
///
/// Shows a subtle indicator bar at the bottom of the editor when diagnostics
/// are present. Tapping opens a popover listing issues with Fix/Dismiss actions.
/// Uses shape+color (not color alone) for accessibility per [D-A11Y-3].

import SwiftUI
import EMCore

/// Indicator bar shown when the Document Doctor has found issues.
/// Appears at the bottom of the editor, non-blocking per FEAT-005 AC-4.
public struct DoctorIndicatorBar: View {
    public let diagnostics: [Diagnostic]
    public let onTap: () -> Void

    public init(diagnostics: [Diagnostic], onTap: @escaping () -> Void) {
        self.diagnostics = diagnostics
        self.onTap = onTap
    }

    public var body: some View {
        if !diagnostics.isEmpty {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    // Shape + color indicator per [D-A11Y-3]
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(diagnostics.count) issue\(diagnostics.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Document Doctor: \(diagnostics.count) issue\(diagnostics.count == 1 ? "" : "s") found")
            .accessibilityHint("Tap to review issues")
        }
    }
}

/// Popover listing all current diagnostics with Fix and Dismiss actions.
public struct DoctorPopoverContent: View {
    public let diagnostics: [Diagnostic]
    public let onFix: (Diagnostic) -> Void
    public let onDismiss: (Diagnostic) -> Void

    public init(
        diagnostics: [Diagnostic],
        onFix: @escaping (Diagnostic) -> Void,
        onDismiss: @escaping (Diagnostic) -> Void
    ) {
        self.diagnostics = diagnostics
        self.onFix = onFix
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(diagnostics) { diagnostic in
                    DoctorIssueRow(
                        diagnostic: diagnostic,
                        onFix: { onFix(diagnostic) },
                        onDismiss: { onDismiss(diagnostic) }
                    )
                }
            }
            .padding()
        }
        .frame(minWidth: 280, maxWidth: 360, maxHeight: 320)
    }
}

/// A single diagnostic row with message, fix, and dismiss controls.
struct DoctorIssueRow: View {
    let diagnostic: Diagnostic
    let onFix: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Shape+color severity indicator per [D-A11Y-3]
                severityIcon
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Line \(diagnostic.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(diagnostic.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                if diagnostic.fix != nil {
                    Button("Fix", action: onFix)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Fix: \(diagnostic.fix?.label ?? "Apply fix")")
                }
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Dismiss this issue")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Line \(diagnostic.line): \(diagnostic.message)")
        .accessibilityHint(diagnostic.fix != nil ? "Actions available: Fix or Dismiss" : "Action available: Dismiss")
    }

    @ViewBuilder
    private var severityIcon: some View {
        switch diagnostic.severity {
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
