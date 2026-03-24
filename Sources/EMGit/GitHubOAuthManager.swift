import Foundation
import Observation
import EMCore
import os

/// Manages GitHub OAuth device flow authentication and token lifecycle per [A-064].
///
/// Handles:
/// - OAuth device flow initiation and polling (AC1)
/// - Token persistence in Keychain across app launches (AC2)
/// - Automatic re-auth when token expires (AC6)
/// - Sign out with token deletion (AC5)
///
/// Observable for SwiftUI binding per [A-010].
@MainActor
@Observable
public final class GitHubOAuthManager {
    // MARK: - Public State

    /// Current authentication state.
    public private(set) var authState: GitHubAuthState = .unauthenticated

    /// Device flow info shown to the user during authentication.
    public private(set) var deviceFlowInfo: GitHubDeviceCodeResponse?

    /// Whether a device flow is actively polling.
    public private(set) var isAuthenticating = false

    // MARK: - Dependencies

    private let keychain: KeychainHelper
    private let apiClient: GitHubAPIClient
    private let clientID: String
    private let logger = Logger(subsystem: "com.easymarkdown.emgit", category: "auth")

    private static let tokenAccount = "github_access_token"

    /// Polling task — kept so we can cancel on sign-out or view dismissal.
    private var pollingTask: Task<Void, Never>?

    /// Creates the OAuth manager.
    /// - Parameters:
    ///   - clientID: The GitHub OAuth App client ID.
    ///   - keychain: Keychain helper for token storage.
    ///   - apiClient: GitHub API client for device flow and token validation.
    public init(
        clientID: String,
        keychain: KeychainHelper = KeychainHelper(),
        apiClient: GitHubAPIClient = GitHubAPIClient()
    ) {
        self.clientID = clientID
        self.keychain = keychain
        self.apiClient = apiClient

        // Restore token from Keychain on init.
        if let token = keychain.read(account: Self.tokenAccount) {
            authState = .authenticated(token: token)
        }
    }

    // MARK: - Device Flow (AC1)

    /// Starts the GitHub OAuth device flow.
    /// Sets `deviceFlowInfo` with the user code and verification URL,
    /// then polls until the user authorizes, denies, or the code expires.
    public func startDeviceFlow() async {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        deviceFlowInfo = nil

        do {
            let codeResponse = try await apiClient.requestDeviceCode(clientID: clientID)
            deviceFlowInfo = codeResponse

            // Start polling in a separate task so we can cancel it.
            pollingTask = Task { [weak self] in
                await self?.pollForAuthorization(
                    deviceCode: codeResponse.deviceCode,
                    interval: codeResponse.interval,
                    expiresIn: codeResponse.expiresIn
                )
            }
        } catch {
            logger.error("Device flow initiation failed: \(error.localizedDescription)")
            authState = .failed(EMError.git(.authenticationFailed))
            isAuthenticating = false
        }
    }

    /// Cancels any in-progress device flow polling.
    public func cancelDeviceFlow() {
        pollingTask?.cancel()
        pollingTask = nil
        isAuthenticating = false
        deviceFlowInfo = nil
        if case .authenticated = authState {
            // Keep authenticated state.
        } else {
            authState = .unauthenticated
        }
    }

    // MARK: - Token Validation (AC6)

    /// Validates the current token and triggers re-auth if expired.
    /// Called when the user attempts an action that needs a valid token.
    /// Returns true if token is valid, false if re-auth is needed.
    @discardableResult
    public func validateTokenIfNeeded() async -> Bool {
        guard case .authenticated(let token) = authState else {
            return false
        }

        let isValid = await apiClient.validateToken(token)
        if !isValid {
            logger.info("Token expired or revoked — triggering re-auth")
            authState = .expired
            return false
        }
        return true
    }

    /// Handles an expired token by clearing it and setting state to expired (AC6).
    /// The RepoBrowserView will detect the state change and show the auth flow.
    public func handleTokenExpired() {
        keychain.delete(account: Self.tokenAccount)
        authState = .expired
        logger.info("Token expired — cleared from Keychain, re-auth required")
    }

    // MARK: - Sign Out (AC5)

    /// Signs out — clears the token from Keychain.
    /// Caller (SettingsView) handles offering to delete local clones.
    public func signOut() {
        pollingTask?.cancel()
        pollingTask = nil
        keychain.delete(account: Self.tokenAccount)
        authState = .unauthenticated
        deviceFlowInfo = nil
        isAuthenticating = false
        logger.info("Signed out of GitHub")
    }

    /// The current access token, if authenticated.
    public var accessToken: String? {
        if case .authenticated(let token) = authState {
            return token
        }
        return nil
    }

    /// Whether the user is currently signed in to GitHub.
    public var isSignedIn: Bool {
        if case .authenticated = authState {
            return true
        }
        return false
    }

    // MARK: - Private Polling

    private func pollForAuthorization(deviceCode: String, interval: Int, expiresIn: Int) async {
        var currentInterval = interval
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))

        while !Task.isCancelled && Date() < deadline {
            // Wait the required interval before polling.
            try? await Task.sleep(for: .seconds(currentInterval))

            if Task.isCancelled { break }

            do {
                let result = try await apiClient.pollDeviceFlowToken(
                    clientID: clientID,
                    deviceCode: deviceCode
                )

                switch result {
                case .success(let accessToken):
                    // Save to Keychain (AC2).
                    do {
                        try keychain.save(token: accessToken, account: Self.tokenAccount)
                    } catch {
                        logger.error("Failed to save token to Keychain: \(error.localizedDescription)")
                    }
                    authState = .authenticated(token: accessToken)
                    isAuthenticating = false
                    deviceFlowInfo = nil
                    logger.info("GitHub authentication succeeded")
                    return

                case .pending:
                    // Keep polling.
                    continue

                case .slowDown:
                    // Increase interval by 5 seconds per spec.
                    currentInterval += 5
                    continue

                case .expired:
                    authState = .failed(EMError.git(.deviceFlowTimeout))
                    isAuthenticating = false
                    logger.info("Device code expired")
                    return

                case .denied:
                    authState = .failed(EMError.git(.deviceFlowDenied))
                    isAuthenticating = false
                    logger.info("User denied access")
                    return
                }
            } catch {
                logger.error("Polling error: \(error.localizedDescription)")
                authState = .failed(EMError.git(.authenticationFailed))
                isAuthenticating = false
                return
            }
        }

        // If we exit the loop without a result, the code expired.
        if !Task.isCancelled {
            authState = .failed(EMError.git(.deviceFlowTimeout))
            isAuthenticating = false
        }
    }
}

/// Authentication state for the GitHub integration.
public enum GitHubAuthState {
    /// Not signed in.
    case unauthenticated
    /// Signed in with a valid access token.
    case authenticated(token: String)
    /// Token has expired — needs re-authentication.
    case expired
    /// Authentication failed with an error.
    case failed(EMError)
}
