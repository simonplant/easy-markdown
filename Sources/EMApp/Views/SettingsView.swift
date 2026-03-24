import SwiftUI
import EMSettings
import EMCore

/// Settings screen presented as a sheet per [A-058].
/// Sections: Appearance, Editor, AI, About.
/// Opinionated defaults — settings exist to turn things OFF.
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
            writingSection(settings: $settings)
            aiSection(settings: $settings)
            exportSection(settings: $settings)
            aboutSection
        }
    }

    // MARK: - Appearance per FEAT-019

    private func appearanceSection(settings: Bindable<SettingsManager>) -> some View {
        Section("Appearance") {
            // Color scheme (System/Light/Dark)
            Picker("Color Scheme", selection: settings.preferredColorScheme) {
                Text("System").tag(ColorSchemePreference.system)
                Text("Light").tag(ColorSchemePreference.light)
                Text("Dark").tag(ColorSchemePreference.dark)
            }
            .accessibilityHint("Choose light, dark, or system color scheme")

            // Theme picker with inline preview per FEAT-019 AC4
            NavigationLink {
                ThemePickerView()
            } label: {
                HStack {
                    Text("Theme")
                    Spacer()
                    Text(Theme.builtIn(id: self.settings.themeID).name)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("Choose a color theme for the editor")

            // Font picker per FEAT-019
            Picker("Font", selection: settings.fontName) {
                ForEach(FontName.allChoices, id: \.self) { choice in
                    Text(FontName.displayName(choice)).tag(choice)
                }
            }
            .accessibilityHint("Choose the editor font")

            // Font size
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

    // MARK: - Writing per FEAT-022

    private func writingSection(settings: Bindable<SettingsManager>) -> some View {
        Section("Writing") {
            Toggle("Prose Suggestions", isOn: settings.isProseSuggestionsEnabled)
                .accessibilityHint("Flag long sentences, passive voice, and repeated words")

            HStack {
                Text("Word Count Goal")
                Spacer()
                TextField(
                    "0",
                    value: settings.writingGoalWordCount,
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .accessibilityLabel("Target word count")
                .accessibilityHint("Set a word count goal. Enter 0 for no goal.")
            }
        }
    }

    // MARK: - AI

    private func aiSection(settings: Bindable<SettingsManager>) -> some View {
        Section("AI") {
            Toggle("Ghost Text", isOn: settings.isGhostTextEnabled)
                .accessibilityHint("Show inline AI completions while typing")
        }
    }

    // MARK: - Export

    private func exportSection(settings: Bindable<SettingsManager>) -> some View {
        Section("Export") {
            Toggle("PDF Watermark", isOn: settings.isPDFExportWatermarkEnabled)
                .accessibilityHint("Include a Made with easy-markdown watermark in exported PDFs")
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

/// Theme picker with live preview per FEAT-019 AC4.
/// Shows a preview of editor content in each theme before the user commits.
struct ThemePickerView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    /// Sample markdown content for theme preview.
    private let previewText = "# Heading\nBody text with **bold** and *italic*.\n`inline code` and [links](url)."

    var body: some View {
        List {
            ForEach(Theme.allBuiltIn) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.themeID = theme.id
                    }
                } label: {
                    themeRow(theme: theme)
                }
                .listRowBackground(
                    settings.themeID == theme.id
                        ? Color.accentColor.opacity(0.1)
                        : Color.clear
                )
                .accessibilityLabel("\(theme.name) theme")
                .accessibilityAddTraits(settings.themeID == theme.id ? .isSelected : [])
            }
        }
        .navigationTitle("Theme")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func themeRow(theme: Theme) -> some View {
        let isDark = colorScheme == .dark
        let colors = theme.colors(isDark: isDark)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(theme.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if settings.themeID == theme.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accent)
                        .accessibilityHidden(true)
                }
            }

            // Preview card showing theme colors per AC4
            themePreviewCard(colors: colors)
        }
        .padding(.vertical, 4)
    }

    /// Renders a mini preview card showing the theme's colors on sample content.
    private func themePreviewCard(colors: ThemeColors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Heading preview
            Text("Heading")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(colors.heading))

            // Body text preview
            Text("Body text with emphasis and links.")
                .font(.system(size: 12))
                .foregroundColor(Color(colors.foreground))

            // Code preview
            Text("let code = true")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(colors.codeForeground))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(colors.codeBackground), in: RoundedRectangle(cornerRadius: 3))

            // Color swatches for accent colors
            HStack(spacing: 4) {
                colorSwatch(colors.link)
                colorSwatch(colors.syntaxKeyword)
                colorSwatch(colors.syntaxString)
                colorSwatch(colors.syntaxFunction)
                colorSwatch(colors.blockquoteBorder)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(colors.background), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(colors.divider), lineWidth: 1)
        )
    }

    private func colorSwatch(_ color: PlatformColor) -> some View {
        Circle()
            .fill(Color(color))
            .frame(width: 14, height: 14)
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
