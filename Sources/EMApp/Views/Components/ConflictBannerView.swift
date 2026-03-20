import SwiftUI
import EMFile

/// Non-modal conflict notification banner per FEAT-045 and [A-027].
///
/// Shown when the open file is modified or deleted externally.
/// Offers Reload (accept external changes) or Keep Mine (overwrite on next save).
/// For deletion, offers Save Elsewhere.
struct ConflictBannerView: View {
    let conflictState: FileConflictState
    let onReload: () -> Void
    let onKeepMine: () -> Void
    let onSaveElsewhere: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if conflictState == .externallyModified {
                Button("Reload") {
                    onReload()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityHint("Discard your version and load the external changes")

                Button("Keep Mine") {
                    onKeepMine()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityHint("Keep your version; next save overwrites external changes")
            } else if conflictState == .externallyDeleted {
                Button("Save Elsewhere") {
                    onSaveElsewhere()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityHint("Save your document to a new location")

                Button("Dismiss") {
                    onKeepMine()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityHint("Dismiss this notification")
            }
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
        .accessibilityLabel(accessibilityMessage)
        .accessibilityAddTraits(.isStaticText)
    }

    private var message: String {
        switch conflictState {
        case .none:
            return ""
        case .externallyModified:
            return "This file was modified by another app. Reload external changes or keep your version?"
        case .externallyDeleted:
            return "This file was deleted while you were editing."
        }
    }

    private var iconName: String {
        switch conflictState {
        case .none:
            return "info.circle.fill"
        case .externallyModified:
            return "arrow.triangle.2.circlepath"
        case .externallyDeleted:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch conflictState {
        case .none:
            return .blue
        case .externallyModified:
            return .orange
        case .externallyDeleted:
            return .red
        }
    }

    private var accessibilityMessage: String {
        switch conflictState {
        case .none:
            return ""
        case .externallyModified:
            return "File conflict: This file was modified externally. Choose to reload or keep your version."
        case .externallyDeleted:
            return "File deleted: This file was deleted while you were editing. Save to a new location."
        }
    }
}
