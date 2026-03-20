import SwiftUI
import EMSettings

/// Settings screen presented as a sheet per [A-058].
/// Sections: Appearance, Editor, AI, About.
/// Opinionated defaults — settings exist to turn things OFF.
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private var settingsForm: some View {
        @Bindable var settings = settings
        return Form {
            appearanceSection(settings: $settings)
            editorSection(settings: $settings)
            aiSection(settings: $settings)
            aboutSection
        }
    }

    // MARK: - Appearance

    private func appearanceSection(settings: Bindable<SettingsManager>) -> some View {
        Section("Appearance") {
            Picker("Theme", selection: settings.preferredColorScheme) {
                Text("System").tag(ColorSchemePreference.system)
                Text("Light").tag(ColorSchemePreference.light)
                Text("Dark").tag(ColorSchemePreference.dark)
            }
            .accessibilityHint("Choose light, dark, or system color scheme")

            Picker("Font", selection: settings.fontName) {
                Text("System").tag(FontName.system)
                Text("Monospaced").tag(FontName.monospaced)
            }
            .accessibilityHint("Choose the editor font")

            HStack {
                Text("Font Size")
                Spacer()
                Text("\(Int(self.settings.fontSize)) pt")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(Int(self.settings.fontSize)) points")

            Slider(
                value: settings.fontSize,
                in: 12...32,
                step: 1
            )
            .accessibilityLabel("Font Size")
            .accessibilityValue("\(Int(self.settings.fontSize)) points")
        }
    }

    // MARK: - Editor

    private func editorSection(settings: Bindable<SettingsManager>) -> some View {
        Section("Editor") {
            Toggle("Spell Check", isOn: settings.isSpellCheckEnabled)
                .accessibilityHint("Enable or disable spell checking in the editor")

            Toggle("Auto-Format", isOn: settings.isAutoFormatEnabled)
                .accessibilityHint("Enable or disable all automatic formatting")

            if self.settings.isAutoFormatEnabled {
                Toggle("List Continuation", isOn: settings.isAutoFormatListContinuation)
                    .accessibilityHint("Auto-continue lists when pressing Enter")
                    .padding(.leading, 16)

                Toggle("List Renumbering", isOn: settings.isAutoFormatListRenumber)
                    .accessibilityHint("Auto-renumber ordered lists")
                    .padding(.leading, 16)

                Toggle("Table Alignment", isOn: settings.isAutoFormatTableAlignment)
                    .accessibilityHint("Auto-align table columns")
                    .padding(.leading, 16)

                Toggle("Heading Spacing", isOn: settings.isAutoFormatHeadingSpacing)
                    .accessibilityHint("Normalize spacing around headings")
                    .padding(.leading, 16)

                Toggle("Blank Line Separation", isOn: settings.isAutoFormatBlankLineSeparation)
                    .accessibilityHint("Auto-insert blank lines between block elements")
                    .padding(.leading, 16)

                Toggle("Trailing Newline on Save", isOn: settings.isAutoFormatEnsureTrailingNewline)
                    .accessibilityHint("Ensure file ends with exactly one newline on save")
                    .padding(.leading, 16)
            }

            Picker("Trailing Whitespace", selection: settings.trailingWhitespaceBehavior) {
                Text("Strip").tag(TrailingWhitespaceBehavior.strip)
                Text("Keep").tag(TrailingWhitespaceBehavior.keep)
            }
            .accessibilityHint("Choose how trailing whitespace is handled on save")
        }
    }

    // MARK: - AI

    private func aiSection(settings: Bindable<SettingsManager>) -> some View {
        Section("AI") {
            Toggle("Ghost Text", isOn: settings.isGhostTextEnabled)
                .accessibilityHint("Show inline AI completions while typing")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Version \(appVersion)")

            Link("Support", destination: supportURL)
                .accessibilityHint("Opens the support page in your browser")

            NavigationLink("Licenses") {
                LicensesView()
            }
            .accessibilityHint("View open source licenses")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var supportURL: URL {
        // Placeholder URL — replaced with real support link before App Store submission.
        URL(string: "https://easymarkdown.app/support")!
    }
}

/// Displays open source license attributions.
struct LicensesView: View {
    var body: some View {
        List {
            licenseRow(
                name: "swift-markdown",
                license: "Apache License 2.0",
                owner: "Apple Inc."
            )
        }
        .navigationTitle("Licenses")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func licenseRow(name: String, license: String, owner: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.body.weight(.medium))
            Text("\(license) \u{2014} \(owner)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
    }
}
