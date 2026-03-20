import SwiftUI

/// Top toolbar for the editor view per FEAT-037.
/// Source toggle and settings gear in the navigation bar.
struct EditorToolbar: ToolbarContent {
    let isSourceView: Bool
    let onToggleSource: () -> Void
    let onSettings: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onToggleSource) {
                Image(systemName: isSourceView ? "eye" : "chevron.left.forwardslash.chevron.right")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .accessibilityLabel(isSourceView ? "Switch to rich text view" : "Switch to source view")
            .accessibilityHint("Toggles between formatted and raw markdown views")

            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }
}
