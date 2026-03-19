import SwiftUI
import EMCore

/// Non-modal error banner displayed at the top of the screen per [A-035].
/// Shows human-readable error messages with recovery actions.
struct ErrorBannerView: View {
    let error: PresentableError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(error.recoveryActions.enumerated()), id: \.offset) { _, action in
                Button(action.label) {
                    Task {
                        await action.perform()
                    }
                    onDismiss()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityHint("Attempts to recover from the error")
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Dismiss this notification")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(iconColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.message)")
        .accessibilityAddTraits(.isStaticText)
    }

    private var iconName: String {
        switch error.severity {
        case .recoverable:
            "exclamationmark.triangle.fill"
        case .informational:
            "info.circle.fill"
        case .dataLossRisk:
            "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch error.severity {
        case .recoverable:
            .orange
        case .informational:
            .blue
        case .dataLossRisk:
            .red
        }
    }
}
