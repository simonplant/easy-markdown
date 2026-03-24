import Foundation

/// A GitHub repository returned by the GitHub API per [A-064].
/// Used by the repo browser to list personal and org repos.
public struct GitHubRepository: Identifiable, Sendable, Hashable {
    /// GitHub API numeric ID.
    public let id: Int

    /// Full repo name including owner (e.g. "owner/repo").
    public let fullName: String

    /// Short repo name (e.g. "repo").
    public let name: String

    /// Owner login (user or org).
    public let ownerLogin: String

    /// Owner avatar URL for display.
    public let ownerAvatarURL: URL?

    /// Whether the repo is private.
    public let isPrivate: Bool

    /// Optional repo description.
    public let repoDescription: String?

    /// When the repo was last pushed to.
    public let updatedAt: Date?

    /// Default branch name (e.g. "main").
    public let defaultBranch: String

    public init(
        id: Int,
        fullName: String,
        name: String,
        ownerLogin: String,
        ownerAvatarURL: URL?,
        isPrivate: Bool,
        repoDescription: String?,
        updatedAt: Date?,
        defaultBranch: String
    ) {
        self.id = id
        self.fullName = fullName
        self.name = name
        self.ownerLogin = ownerLogin
        self.ownerAvatarURL = ownerAvatarURL
        self.isPrivate = isPrivate
        self.repoDescription = repoDescription
        self.updatedAt = updatedAt
        self.defaultBranch = defaultBranch
    }
}

/// Response models for the GitHub OAuth device flow API.
public struct GitHubDeviceCodeResponse: Sendable {
    /// The device verification code shown to the user.
    public let deviceCode: String

    /// The short user-entered code (e.g. "ABCD-1234").
    public let userCode: String

    /// The URL where the user enters the code (github.com/login/device).
    public let verificationURI: URL

    /// How often to poll for completion, in seconds.
    public let interval: Int

    /// When this code expires, in seconds.
    public let expiresIn: Int
}

/// The result of polling the device flow token endpoint.
public enum GitHubDeviceFlowPollResult: Sendable {
    /// Still waiting for the user to authorize.
    case pending
    /// The user authorized — token received.
    case success(accessToken: String)
    /// The user denied access.
    case denied
    /// The device code has expired.
    case expired
    /// Slow down — polling too fast.
    case slowDown
}
