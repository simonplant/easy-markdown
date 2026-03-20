/// Popover content for displaying AI-generated summaries per FEAT-055.
/// Shows the summary text with Insert, Copy, and Dismiss actions.
/// Streams progressively — text updates as tokens arrive.

import SwiftUI
import EMCore

/// Popover displaying an AI-generated summary with action buttons per FEAT-055.
/// Supports three actions: Insert at cursor (AC-2), Copy to clipboard (AC-3), Dismiss.
public struct SummaryPopoverContent: View {
    /// The current summary text (may still be streaming).
    public let summaryText: String
    /// Whether the summary is still being generated.
    public let isStreaming: Bool
    /// Called when the user taps Insert.
    public let onInsert: () -> Void
    /// Called when the user taps Copy.
    public let onCopy: () -> Void
    /// Called when the user taps Dismiss.
    public let onDismiss: () -> Void

    public init(
        summaryText: String,
        isStreaming: Bool,
        onInsert: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.summaryText = summaryText
        self.isStreaming = isStreaming
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Summary", systemImage: "text.badge.minus")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if isStreaming {
                    ProgressView()
                        #if canImport(UIKit)
                        .controlSize(.small)
                        #endif
                        .accessibilityLabel("Generating summary")
                }
            }

            Divider()

            // Summary text — streams progressively
            ScrollView {
                Text(summaryText.isEmpty ? " " : summaryText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(summaryText.isEmpty ? "Generating summary" : summaryText)
            }
            .frame(maxHeight: 200)

            Divider()

            // Action buttons per AC-2, AC-3
            HStack(spacing: 12) {
                Button(action: onInsert) {
                    Label("Insert", systemImage: "text.insert")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isStreaming || summaryText.isEmpty)
                .accessibilityLabel("Insert summary at cursor")
                .accessibilityHint("Inserts the summary into your document at the current cursor position")
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif

                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isStreaming || summaryText.isEmpty)
                .accessibilityLabel("Copy summary to clipboard")
                .accessibilityHint("Copies the summary text to your clipboard")
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif

                Spacer()

                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Dismiss summary")
                .accessibilityHint("Closes the summary without any action")
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI Summary")
    }
}
