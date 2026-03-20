/// Floating action bar that appears above text selection per FEAT-054 and [A-023].
/// Contains formatting actions (Bold, Italic, Link) and AI actions (Improve, Summarize).
/// Lives in EMEditor (primary package per [A-050]).
///
/// Actions are dispatched via closures so EMApp (composition root) can wire them
/// to EMAI without violating dependency rules per [A-015].

import SwiftUI
import EMCore

/// Actions the floating action bar can dispatch.
/// Defined in EMEditor so the bar's API is self-contained.
public struct FloatingActionBarActions {
    /// Called when the user taps Improve.
    public var onImprove: () -> Void
    /// Called when the user taps Accept on an active diff.
    public var onAccept: () -> Void
    /// Called when the user taps Dismiss on an active diff.
    public var onDismiss: () -> Void

    public init(
        onImprove: @escaping () -> Void = {},
        onAccept: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.onImprove = onImprove
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }
}

/// Floating action bar shown above the text selection per [A-023].
/// Shows formatting + AI actions when text is selected.
/// Switches to accept/dismiss controls when an inline diff is active.
public struct FloatingActionBar: View {
    /// The current inline diff phase.
    public let diffPhase: InlineDiffPhase
    /// Actions dispatched by the bar.
    public let actions: FloatingActionBarActions
    /// Whether AI UI should be shown (false on unsupported devices per AC-3).
    public let showAIActions: Bool

    public init(
        diffPhase: InlineDiffPhase,
        actions: FloatingActionBarActions,
        showAIActions: Bool
    ) {
        self.diffPhase = diffPhase
        self.actions = actions
        self.showAIActions = showAIActions
    }

    public var body: some View {
        Group {
            if diffPhase == .streaming || diffPhase == .ready {
                diffControls
            } else {
                selectionControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        #if canImport(UIKit)
        .background(.ultraThinMaterial)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating action bar")
    }

    // MARK: - Selection Mode

    /// Standard selection controls: formatting + AI actions.
    private var selectionControls: some View {
        HStack(spacing: 12) {
            if showAIActions {
                Button(action: actions.onImprove) {
                    Label("Improve", systemImage: "wand.and.stars")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityLabel("Improve writing")
                .accessibilityHint("Uses AI to improve the selected text")

                Divider()
                    .frame(height: 20)
            }

            FormatActionButton(icon: "bold", label: "Bold")
            FormatActionButton(icon: "italic", label: "Italic")
            FormatActionButton(icon: "link", label: "Link")
        }
    }

    // MARK: - Diff Mode

    /// Accept/dismiss controls shown during an active inline diff.
    private var diffControls: some View {
        HStack(spacing: 12) {
            if diffPhase == .streaming {
                ProgressView()
                    #if canImport(UIKit)
                    .controlSize(.small)
                    #endif
                    .accessibilityLabel("AI is generating")

                Text("Improving...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if diffPhase == .ready {
                Button(action: actions.onAccept) {
                    Label("Accept", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityLabel("Accept suggestion")
                .accessibilityHint("Replaces original text with the AI suggestion")
            }

            Button(action: actions.onDismiss) {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("Dismiss suggestion")
            .accessibilityHint("Returns to the original text with no changes")
        }
    }
}

/// Stub formatting button — formatting integration ships with FEAT-003/FEAT-037.
private struct FormatActionButton: View {
    let icon: String
    let label: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
                .imageScale(.medium)
        }
        .accessibilityLabel(label)
    }
}
