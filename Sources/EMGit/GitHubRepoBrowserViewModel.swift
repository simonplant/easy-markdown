import Foundation
import Observation
import EMCore
import os

/// View model for the GitHub repo browser per [A-064].
/// Fetches repos, supports search/filter (AC4), caches for offline (description says so).
@MainActor
@Observable
public final class GitHubRepoBrowserViewModel {
    // MARK: - Public State

    /// All fetched repositories.
    public private(set) var repositories: [GitHubRepository] = []

    /// Filtered repositories based on search text.
    public var filteredRepositories: [GitHubRepository] {
        guard !searchText.isEmpty else { return repositories }
        let query = searchText.lowercased()
        return repositories.filter { repo in
            repo.name.lowercased().contains(query)
                || repo.fullName.lowercased().contains(query)
                || (repo.repoDescription?.lowercased().contains(query) ?? false)
        }
    }

    /// Current search/filter text (AC4).
    public var searchText = ""

    /// Whether repos are currently loading.
    public private(set) var isLoading = false

    /// Error message to display, if any.
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let apiClient: GitHubAPIClient
    private let oauthManager: GitHubOAuthManager
    private let logger = Logger(subsystem: "com.easymarkdown.emgit", category: "repobrowser")

    /// Cached repos stored in UserDefaults for offline access.
    private static let cacheKey = "em_github_cached_repos"

    public init(oauthManager: GitHubOAuthManager, apiClient: GitHubAPIClient = GitHubAPIClient()) {
        self.oauthManager = oauthManager
        self.apiClient = apiClient

        // Load cached repos immediately for offline access.
        loadCachedRepos()
    }

    // MARK: - Fetching (AC3)

    /// Fetches repositories from GitHub. Falls back to cache on failure.
    public func fetchRepositories() async {
        guard let token = oauthManager.accessToken else {
            errorMessage = "Not signed in to GitHub."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let repos = try await apiClient.fetchRepositories(token: token)
            repositories = repos
            cacheRepos(repos)
            logger.info("Loaded \(repos.count) repos from GitHub")
        } catch let error as EMError {
            if case .git(.authenticationExpired) = error {
                // Token expired — trigger re-auth flow automatically (AC6).
                oauthManager.handleTokenExpired()
                errorMessage = error.errorDescription
            } else {
                errorMessage = error.errorDescription
            }
            logger.error("Failed to fetch repos: \(error.localizedDescription)")
        } catch {
            errorMessage = EMError.git(.networkUnavailable).errorDescription
            logger.error("Network error fetching repos: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Cache

    private func loadCachedRepos() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([CachedRepo].self, from: data)
        else { return }

        repositories = cached.map { $0.toRepository() }
    }

    private func cacheRepos(_ repos: [GitHubRepository]) {
        let cached = repos.map { CachedRepo(from: $0) }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    /// Clears cached repository data. Called on sign out.
    public func clearCache() {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        repositories = []
        searchText = ""
    }
}

// MARK: - Codable Cache Model

/// Lightweight Codable wrapper for caching repos in UserDefaults.
private struct CachedRepo: Codable {
    let id: Int
    let fullName: String
    let name: String
    let ownerLogin: String
    let ownerAvatarURL: String?
    let isPrivate: Bool
    let repoDescription: String?
    let updatedAt: Date?
    let defaultBranch: String

    init(from repo: GitHubRepository) {
        self.id = repo.id
        self.fullName = repo.fullName
        self.name = repo.name
        self.ownerLogin = repo.ownerLogin
        self.ownerAvatarURL = repo.ownerAvatarURL?.absoluteString
        self.isPrivate = repo.isPrivate
        self.repoDescription = repo.repoDescription
        self.updatedAt = repo.updatedAt
        self.defaultBranch = repo.defaultBranch
    }

    func toRepository() -> GitHubRepository {
        GitHubRepository(
            id: id,
            fullName: fullName,
            name: name,
            ownerLogin: ownerLogin,
            ownerAvatarURL: ownerAvatarURL.flatMap { URL(string: $0) },
            isPrivate: isPrivate,
            repoDescription: repoDescription,
            updatedAt: updatedAt,
            defaultBranch: defaultBranch
        )
    }
}
