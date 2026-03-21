#if os(macOS)
import SwiftUI

/// Standard macOS menu bar commands per FEAT-021 and Apple HIG.
/// Provides File, Edit, View, Format, Window, Help menus with full keyboard shortcut coverage.
/// Per AC-5: Menu bar has standard File/Edit/View/Format/Window/Help menus.
/// SwiftUI automatically provides Edit (Undo/Redo/Cut/Copy/Paste) and Window menus.
struct MacOSMenuCommands: Commands {
    /// Binding to trigger file open from menu.
    let onOpenFile: () -> Void
    /// Binding to trigger new file from menu.
    let onNewFile: () -> Void
    /// Binding to trigger close file from menu.
    let onCloseFile: () -> Void
    /// Binding to toggle source/rich view.
    let onToggleSourceView: () -> Void
    /// Binding to open find and replace.
    let onFindReplace: () -> Void
    /// Binding to open settings (Cmd+comma) per AC-6.
    let onSettings: () -> Void

    var body: some Commands {
        // Replace the default New/Open with our own File menu items.
        CommandGroup(replacing: .newItem) {
            Button("New") {
                onNewFile()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open…") {
                onOpenFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Close") {
                onCloseFile()
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        // View menu: toggle source/rich view
        CommandGroup(after: .toolbar) {
            Section {
                Button("Toggle Source View") {
                    onToggleSourceView()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        // Find menu items under Edit
        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                onFindReplace()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find and Replace…") {
                onFindReplace()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
        }

        // Format menu with text formatting shortcuts per AC-5.
        // Bold/Italic/Link are standard Mac text formatting shortcuts.
        // These are dispatched via NotificationCenter to the active editor
        // since markdown bold/italic are syntax operations (wrap with ** / *),
        // not NSFontManager operations.
        CommandMenu("Format") {
            Button("Bold") {
                NotificationCenter.default.post(
                    name: Notification.Name("com.easymarkdown.menu.bold"),
                    object: nil
                )
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                NotificationCenter.default.post(
                    name: Notification.Name("com.easymarkdown.menu.italic"),
                    object: nil
                )
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Insert Link") {
                // Dispatched via notification to the active editor
                NotificationCenter.default.post(
                    name: Notification.Name("com.easymarkdown.menu.insertLink"),
                    object: nil
                )
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        // Settings via Cmd+comma per AC-6
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                onSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Help menu — standard, SwiftUI provides the Window menu automatically
        CommandGroup(replacing: .help) {
            Link("easy-markdown Help", destination: URL(string: "https://easymarkdown.app/help")!)
        }
    }
}
#endif
