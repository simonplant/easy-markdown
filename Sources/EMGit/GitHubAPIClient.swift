import Foundation
import EMCore
import os

/// GitHub REST API client for repo listing and token validation per [A-064].
/// Uses URLSession with structured concurrency per [A-047].
public struct GitHubAPIClient: Sendable {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.easymarkdown.emgit", category: "api")

    /// Creates a client using the given URLSession.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Repo Listing (AC3, AC4)

    /// Fetches all repos the authenticated user has access to (personal + org).
    /// Uses the /user/repos endpoint which returns both personal and org repos.
    /// Paginates automatically to get all repos.
    public func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        var allRepos: [GitHubRepository] = []
        var page = 1
        let perPage = 100

        while true {
            let url = URL(string: "https://api.github.com/user/repos?per_page=\(perPage)&page=\(page)&sort=pushed&direction=desc&type=all")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EMError.git(.repoListFailed(underlying: GitHubAPIError.invalidResponse))
            }

            if httpResponse.statusCode == 401 {
                throw EMError.git(.authenticationExpired)
            }

            guard httpResponse.statusCode == 200 else {
                throw EMError.git(.repoListFailed(
                    underlying: GitHubAPIError.httpError(statusCode: httpResponse.statusCode)
                ))
            }

            let repos = try decodeRepositories(from: data)
            allRepos.append(contentsOf: repos)

            // Stop if we got fewer than a full page.
            if repos.count < perPage { break }
            page += 1
        }

        logger.info("Fetched \(allRepos.count) repositories")
        return allRepos
    }

    // MARK: - Token Validation (AC6)

    /// Checks if the given token is still valid by hitting a lightweight endpoint.
    /// Returns true if the token is valid, false if expired/revoked.
    public func validateToken(_ token: String) async -> Bool {
        guard let url = URL(string: "https://api.github.com/user") else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            logger.debug("Token validation network error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Device Flow (AC1)

    /// Initiates the GitHub OAuth device flow.
    /// Returns the device code response containing the user code and verification URL.
    public func requestDeviceCode(clientID: String) async throws -> GitHubDeviceCodeResponse {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["client_id": clientID, "scope": "repo"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EMError.git(.authenticationFailed)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURI = json["verification_uri"] as? String,
              let verificationURL = URL(string: verificationURI),
              let interval = json["interval"] as? Int,
              let expiresIn = json["expires_in"] as? Int
        else {
            throw EMError.git(.authenticationFailed)
        }

        return GitHubDeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURL,
            interval: interval,
            expiresIn: expiresIn
        )
    }

    /// Polls the device flow token endpoint once.
    /// Caller is responsible for polling at the correct interval.
    public func pollDeviceFlowToken(clientID: String, deviceCode: String) async throws -> GitHubDeviceFlowPollResult {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EMError.git(.authenticationFailed)
        }

        // Success case — token is present.
        if let accessToken = json["access_token"] as? String {
            return .success(accessToken: accessToken)
        }

        // Error cases per the device flow spec.
        if let error = json["error"] as? String {
            switch error {
            case "authorization_pending":
                return .pending
            case "slow_down":
                return .slowDown
            case "expired_token":
                return .expired
            case "access_denied":
                return .denied
            default:
                throw EMError.git(.authenticationFailed)
            }
        }

        throw EMError.git(.authenticationFailed)
    }

    // MARK: - JSON Decoding

    private func decodeRepositories(from data: Data) throws -> [GitHubRepository] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw EMError.git(.repoListFailed(underlying: GitHubAPIError.invalidJSON))
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return jsonArray.compactMap { json -> GitHubRepository? in
            guard let id = json["id"] as? Int,
                  let fullName = json["full_name"] as? String,
                  let name = json["name"] as? String,
                  let owner = json["owner"] as? [String: Any],
                  let ownerLogin = owner["login"] as? String,
                  let isPrivate = json["private"] as? Bool,
                  let defaultBranch = json["default_branch"] as? String
            else {
                return nil
            }

            let avatarURLString = owner["avatar_url"] as? String
            let avatarURL = avatarURLString.flatMap { URL(string: $0) }
            let description = json["description"] as? String
            let updatedAtString = json["pushed_at"] as? String
            let updatedAt = updatedAtString.flatMap {
                dateFormatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
            }

            return GitHubRepository(
                id: id,
                fullName: fullName,
                name: name,
                ownerLogin: ownerLogin,
                ownerAvatarURL: avatarURL,
                isPrivate: isPrivate,
                repoDescription: description,
                updatedAt: updatedAt,
                defaultBranch: defaultBranch
            )
        }
    }
}

/// Internal API error types.
enum GitHubAPIError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidJSON
}
