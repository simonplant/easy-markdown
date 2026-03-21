import SwiftUI
import EMEditor

/// Find and replace bar per FEAT-017.
/// Invoked via Cmd+F. Supports plain text and regex search,
/// case-sensitive toggle, match highlighting, replace one / replace all.
struct FindReplaceBar: View {
    @Bindable var state: FindReplaceState
    /// Called when user taps Replace for the current match.
    var onReplace: () -> Void
    /// Called when user taps Replace All.
    var onReplaceAll: () -> Void
    /// Called when the find bar is dismissed.
    var onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Search row
            HStack(spacing: 8) {
                searchField

                modeToggle
                caseSensitiveToggle

                navigationButtons

                dismissButton
            }

            // Error message for invalid regex per FEAT-017 AC-5
            if let errorMessage = state.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .imageScale(.small)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(errorMessage)")
            }

            // Replace row
            HStack(spacing: 8) {
                replaceField

                replaceButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            isSearchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find and Replace")
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField("Find", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit { state.nextMatch() }
                .accessibilityLabel("Search text")

            if !state.searchQuery.isEmpty {
                Text(state.positionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel(
                        state.matchCount == 0
                            ? "No results"
                            : "\(state.positionLabel) matches"
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            state.errorMessage != nil ? Color.red.opacity(0.6) : Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Replace Field

    private var replaceField: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil.line")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField("Replace", text: $state.replaceText)
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel("Replacement text")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Toggles

    private var modeToggle: some View {
        Button {
            state.mode = state.mode == .plainText ? .regex : .plainText
        } label: {
            Text(".*")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: 28, height: 24)
                .background(
                    state.mode == .regex
                        ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Regex mode")
        .accessibilityValue(state.mode == .regex ? "On" : "Off")
        .accessibilityHint("Toggle regular expression search")
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var caseSensitiveToggle: some View {
        Button {
            state.isCaseSensitive.toggle()
        } label: {
            Image(systemName: "textformat")
                .imageScale(.small)
                .frame(width: 28, height: 24)
                .background(
                    state.isCaseSensitive
                        ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Case sensitive")
        .accessibilityValue(state.isCaseSensitive ? "On" : "Off")
        .accessibilityHint("Toggle case-sensitive search")
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button {
                state.previousMatch()
            } label: {
                Image(systemName: "chevron.up")
                    .imageScale(.small)
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(state.matches.isEmpty)
            .accessibilityLabel("Previous match")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif

            Button {
                state.nextMatch()
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(state.matches.isEmpty)
            .accessibilityLabel("Next match")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        }
    }

    // MARK: - Replace Buttons

    private var replaceButtons: some View {
        HStack(spacing: 6) {
            Button("Replace") {
                onReplace()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.currentMatchIndex == nil)
            .accessibilityLabel("Replace current match")
            .accessibilityHint("Replace the currently highlighted match")

            Button("All") {
                onReplaceAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.matches.isEmpty)
            .accessibilityLabel("Replace all matches")
            .accessibilityHint("Replace all occurrences at once")
        }
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .imageScale(.small)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close find bar")
        .keyboardShortcut(.escape, modifiers: [])
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}
