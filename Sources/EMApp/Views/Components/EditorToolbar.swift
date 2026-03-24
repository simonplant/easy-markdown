import SwiftUI

/// Top toolbar for the editor view per FEAT-037 and FEAT-018.
/// Source toggle, voice mic (FEAT-068), share menu (PDF export, share markdown, print), and settings gear.
/// Trackpad hover states per FEAT-015 AC-4.
struct EditorToolbar: ToolbarContent {
    let isSourceView: Bool
    let onToggleSource: () -> Void
    let onExportPDF: () -> Void
    let onShareMarkdown: () -> Void
    let onPrint: () -> Void
    let onSettings: () -> Void
    /// Whether to show the voice mic button per FEAT-068.
    var showVoiceMic: Bool = false
    /// Whether voice is currently listening.
    var isVoiceListening: Bool = false
    /// Whether voice is available on this device.
    var isVoiceAvailable: Bool = false
    /// Called when the mic button is tapped per FEAT-068 AC-1.
    var onVoiceToggle: (() -> Void)? = nil

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onToggleSource) {
                Image(systemName: isSourceView ? "eye" : "chevron.left.forwardslash.chevron.right")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .accessibilityLabel(isSourceView ? "Switch to rich text view" : "Switch to source view")
            .accessibilityHint("Toggles between formatted and raw markdown views")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif

            // Voice mic button per FEAT-068 AC-1
            if showVoiceMic {
                Button(action: { onVoiceToggle?() }) {
                    Image(systemName: isVoiceListening ? "mic.fill" : "mic")
                        .foregroundStyle(isVoiceListening ? .red : .primary)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(!isVoiceAvailable)
                .accessibilityLabel(
                    isVoiceListening
                        ? "Stop voice command"
                        : "Voice command"
                )
                .accessibilityHint(
                    isVoiceListening
                        ? "Tap to stop recording and process your voice command"
                        : "Tap to speak an editing command. Say what you want to change, like 'make this shorter' or 'add a conclusion'. Voice editing mode — separate from VoiceOver navigation."
                )
                .accessibilityAddTraits(isVoiceListening ? .isSelected : [])
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
            }

            Menu {
                Button(action: onExportPDF) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(action: onShareMarkdown) {
                    Label("Share Markdown", systemImage: "paperplane")
                }

                Divider()

                Button(action: onPrint) {
                    Label("Print", systemImage: "printer")
                }
                .keyboardShortcut("p", modifiers: .command)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            .accessibilityHint("Share, export, or print the document")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif

            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        }
    }
}
