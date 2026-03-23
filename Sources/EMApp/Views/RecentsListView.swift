import SwiftUI
import EMCore

/// Displays the list of recently opened files per [D-UX-2].
///
/// Shows filename, parent folder, and last opened date for each entry.
/// Tapping an entry resolves its bookmark and opens the file via FileOpenCoordinator.
/// Stale entries (file deleted/moved) are removed gracefully.
struct RecentsListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RecentsManager.self) private var recentsManager
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(ErrorPresenter.self) private var errorPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            Text("Recents")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityAddTraits(.isHeader)

            List {
                ForEach(recentsManager.recentItems) { item in
                    Button(action: { openRecent(item) }) {
                        RecentItemRow(item: item)
                    }
                    .accessibilityLabel("\(item.filename) in \(item.parentFolder)")
                    .accessibilityHint("Opens this recently opened file")
                }
                .onDelete(perform: deleteRecents)
            }
            .listStyle(.plain)
            .frame(maxHeight: 280)
        }
    }

    private func openRecent(_ item: RecentItem) {
        guard let url = recentsManager.resolveRecentItem(item) else {
            // Entry was stale and has been removed — show actionable guidance
            let staleError = EMError.file(.bookmarkStale(url: URL(fileURLWithPath: item.urlPath)))
            errorPresenter.present(staleError)
            return
        }

        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened, .alreadyOpen:
            router.openEditor()
        case .failed:
            // Error already presented by FileOpenCoordinator
            break
        }
    }

    private func deleteRecents(at offsets: IndexSet) {
        for index in offsets {
            recentsManager.removeRecentItem(recentsManager.recentItems[index])
        }
    }
}

/// A single row in the recents list per AC-4.
/// Shows filename, parent folder, and last opened date.
struct RecentItemRow: View {
    let item: RecentItem

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.body)
                    .lineLimit(1)

                Text(item.parentFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.lastOpenedDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
