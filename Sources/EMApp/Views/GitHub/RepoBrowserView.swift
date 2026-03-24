import SwiftUI
import EMGit

/// Repo browser showing personal and org repos per [A-064] AC3, AC4.
/// If not authenticated, shows the device flow auth inline (AC1).
/// Supports search/filter by name (AC4).
/// Shows last updated date per sprint description.
struct RepoBrowserView: View {
    @Environment(GitHubOAuthManager.self) private var oauthManager
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GitHubRepoBrowserViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if oauthManager.isSignedIn {
                    if let viewModel {
                        repoBrowserContent(viewModel: viewModel)
                    } else {
                        ProgressView()
                            .accessibilityLabel("Loading")
                    }
                } else {
                    GitHubDeviceFlowView()
                }
            }
            .navigationTitle(oauthManager.isSignedIn ? "Repositories" : "GitHub")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        oauthManager.cancelDeviceFlow()
                        dismiss()
                    }
                }
            }
            .task(id: oauthManager.isSignedIn) {
                guard oauthManager.isSignedIn else { return }
                let vm = GitHubRepoBrowserViewModel(oauthManager: oauthManager)
                viewModel = vm
                await vm.fetchRepositories()
            }
        }
    }

    @ViewBuilder
    private func repoBrowserContent(viewModel: GitHubRepoBrowserViewModel) -> some View {
        @Bindable var vm = viewModel
        List {
            if viewModel.isLoading && viewModel.repositories.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading repositories\u{2026}")
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .accessibilityLabel("Loading repositories")
            } else if let errorMessage = viewModel.errorMessage, viewModel.repositories.isEmpty {
                ContentUnavailableView {
                    Label("Couldn\u{2019}t Load Repos", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.fetchRepositories() }
                    }
                    .accessibilityHint("Retry loading repositories")
                }
                .listRowSeparator(.hidden)
            } else if viewModel.filteredRepositories.isEmpty {
                if viewModel.searchText.isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "folder",
                        description: Text("No repositories found for your account.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ContentUnavailableView.search(text: viewModel.searchText)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(viewModel.filteredRepositories) { repo in
                    Button {
                        // Repo selected — future FEAT-070 will handle clone & open.
                        dismiss()
                    } label: {
                        RepoRowView(repo: repo)
                    }
                    .accessibilityLabel("\(repo.fullName)\(repo.isPrivate ? ", private" : "")")
                    .accessibilityHint("Select this repository")
                }
            }
        }
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Filter repos by name"
        )
        .refreshable {
            await viewModel.fetchRepositories()
        }
    }
}

/// A single row in the repo browser list.
private struct RepoRowView: View {
    let repo: GitHubRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(repo.fullName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if repo.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Private")
                }
            }

            if let description = repo.repoDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let updatedAt = repo.updatedAt {
                Text("Updated \(updatedAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
