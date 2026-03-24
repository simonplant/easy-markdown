/// Floating action bar that appears above text selection per FEAT-054 and [A-023].
/// Contains formatting actions (Bold, Italic, Link) and AI actions (Improve, Summarize).
/// Pro AI actions (Translate, Tone) appear with Pro badge for subscribers.
/// Lives in EMEditor (primary package per [A-050]).
///
/// Actions are dispatched via closures so EMApp (composition root) can wire them
/// to EMAI without violating dependency rules per [A-015].

import SwiftUI
import EMCore

/// Actions the floating action bar can dispatch.
/// Defined in EMEditor so the bar's API is self-contained.
public struct FloatingActionBarActions {
    // MARK: - AI actions
    /// Called when the user taps Improve.
    public var onImprove: () -> Void
    /// Called when the user taps Summarize.
    public var onSummarize: () -> Void
    /// Called when the user taps Translate (Pro).
    public var onTranslate: () -> Void
    /// Called when the user taps Adjust Tone (Pro).
    public var onTone: () -> Void
    /// Called when a non-subscriber taps a Pro action per AC-4.
    public var onProUpgrade: () -> Void

    // MARK: - Diff controls
    /// Called when the user taps Accept on an active diff.
    public var onAccept: () -> Void
    /// Called when the user taps Dismiss on an active diff.
    public var onDismiss: () -> Void

    // MARK: - Formatting actions
    /// Called when the user taps Bold.
    public var onBold: () -> Void
    /// Called when the user taps Italic.
    public var onItalic: () -> Void
    /// Called when the user taps Link.
    public var onLink: () -> Void

    public init(
        onImprove: @escaping () -> Void = {},
        onSummarize: @escaping () -> Void = {},
        onTranslate: @escaping () -> Void = {},
        onTone: @escaping () -> Void = {},
        onProUpgrade: @escaping () -> Void = {},
        onAccept: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onBold: @escaping () -> Void = {},
        onItalic: @escaping () -> Void = {},
        onLink: @escaping () -> Void = {}
    ) {
        self.onImprove = onImprove
        self.onSummarize = onSummarize
        self.onTranslate = onTranslate
        self.onTone = onTone
        self.onProUpgrade = onProUpgrade
        self.onAccept = onAccept
        self.onDismiss = onDismiss
        self.onBold = onBold
        self.onItalic = onItalic
        self.onLink = onLink
    }
}

/// Floating action bar shown above the text selection per [A-023].
/// Shows formatting + AI actions when text is selected.
/// Switches to accept/dismiss controls when an inline diff is active.
/// Adapts to available width — compact layout uses icon-only for format buttons.
public struct FloatingActionBar: View {
    /// The current inline diff phase.
    public let diffPhase: InlineDiffPhase
    /// Actions dispatched by the bar.
    public let actions: FloatingActionBarActions
    /// Whether AI UI should be shown (false on unsupported devices per [D-AI-5]).
    public let showAIActions: Bool
    /// Whether the user is a Pro subscriber. Controls badge display per AC-3.
    public let isProSubscriber: Bool
    /// Whether to use compact layout (icon-only format buttons).
    public let isCompact: Bool
    /// Binding that triggers focus on the AI section when set to true (Cmd+J per AC-6).
    @Binding public var focusAISection: Bool

    @AccessibilityFocusState private var isAIFocused: Bool

    public init(
        diffPhase: InlineDiffPhase,
        actions: FloatingActionBarActions,
        showAIActions: Bool,
        isProSubscriber: Bool = false,
        isCompact: Bool = false,
        focusAISection: Binding<Bool> = .constant(false)
    ) {
        self.diffPhase = diffPhase
        self.actions = actions
        self.showAIActions = showAIActions
        self.isProSubscriber = isProSubscriber
        self.isCompact = isCompact
        self._focusAISection = focusAISection
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating action bar")
        .onChange(of: focusAISection) { _, shouldFocus in
            if shouldFocus {
                isAIFocused = true
                focusAISection = false
            }
        }
        .onAppear {
            if focusAISection {
                isAIFocused = true
                focusAISection = false
            }
        }
    }

    // MARK: - Selection Mode

    /// Standard selection controls: formatting + AI actions.
    private var selectionControls: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            // Formatting actions
            FormatActionButton(icon: "bold", label: "Bold", action: actions.onBold)
            FormatActionButton(icon: "italic", label: "Italic", action: actions.onItalic)
            FormatActionButton(icon: "link", label: "Link", action: actions.onLink)

            if showAIActions {
                Divider()
                    .frame(height: 20)
                    .accessibilityHidden(true)

                // Core AI actions (local)
                AIActionButton(
                    title: "Improve",
                    icon: "wand.and.stars",
                    isCompact: isCompact,
                    action: actions.onImprove
                )
                .accessibilityLabel("Improve writing")
                .accessibilityHint("Uses AI to improve the selected text")
                .accessibilityFocused($isAIFocused)

                AIActionButton(
                    title: "Summarize",
                    icon: "text.badge.minus",
                    isCompact: isCompact,
                    action: actions.onSummarize
                )
                .accessibilityLabel("Summarize")
                .accessibilityHint("Uses AI to summarize the selected text")

                // Pro AI actions per AC-3
                ProAIActionButton(
                    title: "Translate",
                    icon: "globe",
                    isProSubscriber: isProSubscriber,
                    isCompact: isCompact,
                    action: isProSubscriber ? actions.onTranslate : actions.onProUpgrade
                )
                .accessibilityLabel(isProSubscriber ? "Translate" : "Translate, Pro feature")
                .accessibilityHint(
                    isProSubscriber
                        ? "Uses AI to translate the selected text"
                        : "Requires Pro subscription. Double tap to learn more."
                )

                ProAIActionButton(
                    title: "Tone",
                    icon: "slider.horizontal.3",
                    isProSubscriber: isProSubscriber,
                    isCompact: isCompact,
                    action: isProSubscriber ? actions.onTone : actions.onProUpgrade
                )
                .accessibilityLabel(isProSubscriber ? "Adjust Tone" : "Adjust Tone, Pro feature")
                .accessibilityHint(
                    isProSubscriber
                        ? "Uses AI to adjust the tone of the selected text"
                        : "Requires Pro subscription. Double tap to learn more."
                )
            }
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

                Text("Processing...")
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
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
            }

            Button(action: actions.onDismiss) {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("Dismiss suggestion")
            .accessibilityHint("Returns to the original text with no changes")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        }
    }
}

// MARK: - Subviews

/// Formatting button — dispatches via closure for Bold, Italic, Link.
private struct FormatActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .imageScale(.medium)
        }
        .accessibilityLabel(label)
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}

/// Core AI action button with icon and optional title.
private struct AIActionButton: View {
    let title: String
    let icon: String
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isCompact {
                Image(systemName: icon)
                    .imageScale(.medium)
            } else {
                Label(title, systemImage: icon)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
        }
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}

/// Pro AI action button with subtle Pro badge per AC-3.
/// Shows badge overlay for subscribers; non-subscribers get the same button
/// but the action dispatches to onProUpgrade per AC-4.
private struct ProAIActionButton: View {
    let title: String
    let icon: String
    let isProSubscriber: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isCompact {
                proIcon
            } else {
                Label {
                    proLabel
                } icon: {
                    proIcon
                }
                .font(.subheadline.weight(.medium))
            }
        }
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var proIcon: some View {
        Image(systemName: icon)
            .imageScale(.medium)
            .overlay(alignment: .topTrailing) {
                proBadge
            }
    }

    private var proLabel: some View {
        HStack(spacing: 2) {
            Text(title)
            if !isCompact {
                proBadgeText
            }
        }
    }

    /// Subtle Pro badge — small "PRO" text in a rounded capsule per AC-3.
    @ViewBuilder
    private var proBadge: some View {
        if isProSubscriber {
            Text("PRO")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(.blue, in: Capsule())
                .offset(x: 4, y: -4)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var proBadgeText: some View {
        if isProSubscriber {
            Text("PRO")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
        }
    }
}
