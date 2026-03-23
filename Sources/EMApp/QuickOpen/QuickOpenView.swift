import SwiftUI
import EMCore

/// Quick Open overlay for fuzzy file search per F-011.
///
/// Presented as a sheet/overlay when user presses Cmd+P.
/// Shows a search field with fuzzy-matched results from recent files.
/// Selecting a result resolves the bookmark and opens the file.
struct QuickOpenView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RecentsManager.self) private var recentsManager
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Bindable var viewModel: QuickOpenViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search recent files\u{2026}", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .accessibilityLabel("Quick open search")
                    .accessibilityHint("Type to search recent files by name")
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                if !viewModel.query.isEmpty {
                    Button(action: { viewModel.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)

            Divider()

            // Results or empty state
            if viewModel.hasNoRecentFiles {
                emptyState
            } else if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                promptState
            } else if viewModel.results.isEmpty {
                noMatchState
            } else {
                resultsList
            }
        }
        .frame(maxWidth: 500)
        .frame(minHeight: 200, maxHeight: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Open")
    }

    // MARK: - States

    /// AC-2: Empty state when no recent files exist.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No recent files")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a file first, then use Quick Open to switch between recent files.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No recent files. Open a file first, then use Quick Open to switch between recent files.")
    }

    /// Prompt shown before the user types anything.
    private var promptState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Type to search \(recentsManager.recentItems.count) recent files")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("Type to search recent files")
    }

    /// Shown when the query has no matches.
    private var noMatchState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No matching files")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No matching files")
    }

    /// Matched results list.
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.results) { result in
                    Button(action: { openResult(result) }) {
                        QuickOpenResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(result.recentItem.filename) in \(result.recentItem.parentFolder)")
                    .accessibilityHint("Opens this file")
                }
            }
        }
    }

    // MARK: - Actions

    private func openResult(_ result: QuickOpenResult) {
        guard let url = recentsManager.resolveRecentItem(result.recentItem) else {
            // Stale entry removed by resolveRecentItem — show actionable guidance
            let staleError = EMError.file(.bookmarkStale(url: URL(fileURLWithPath: result.recentItem.urlPath)))
            errorPresenter.present(staleError)
            onDismiss()
            return
        }

        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened, .alreadyOpen:
            onDismiss()
            router.openEditor()
        case .failed:
            // Error presented by FileOpenCoordinator
            onDismiss()
        }
    }
}

/// A single row in the Quick Open results list.
struct QuickOpenResultRow: View {
    let result: QuickOpenResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.recentItem.filename)
                    .font(.body)
                    .lineLimit(1)

                Text(result.recentItem.parentFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.recentItem.lastOpenedDate, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}
