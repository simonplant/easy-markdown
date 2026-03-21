import SwiftUI

/// Top toolbar for the editor view per FEAT-037.
/// Source toggle and settings gear in the navigation bar.
/// Trackpad hover states per FEAT-015 AC-4.
struct EditorToolbar: ToolbarContent {
    let isSourceView: Bool
    let onToggleSource: () -> Void
    let onExportPDF: () -> Void
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

            Button(action: onExportPDF) {
                Image(systemName: "arrow.up.doc")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .accessibilityLabel("Export PDF")
            .accessibilityHint("Export the document as a PDF file")
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
