import SwiftUI

/// Top toolbar for the editor view per FEAT-037 and FEAT-018.
/// Source toggle, share menu (PDF export, share markdown, print), and settings gear.
/// Trackpad hover states per FEAT-015 AC-4.
struct EditorToolbar: ToolbarContent {
    let isSourceView: Bool
    let onToggleSource: () -> Void
    let onExportPDF: () -> Void
    let onShareMarkdown: () -> Void
    let onPrint: () -> Void
    let onSettings: () -> Void

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
