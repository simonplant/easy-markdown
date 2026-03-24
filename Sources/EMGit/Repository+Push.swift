import Foundation
import SwiftGit2
import Clibgit2
import EMCore

/// Holds token string for the credential callback's payload.
private final class TokenPayload {
    let token: String
    init(_ token: String) { self.token = token }
}

/// libgit2 credential callback that provides plaintext username/password authentication.
/// Uses "x-access-token" as the username per GitHub HTTPS token auth convention.
private func pushCredentialsCallback(
    cred: UnsafeMutablePointer<UnsafeMutablePointer<git_cred>?>?,
    url: UnsafePointer<CChar>?,
    usernameFromURL: UnsafePointer<CChar>?,
    allowedTypes: UInt32,
    payload: UnsafeMutableRawPointer?
) -> Int32 {
    guard let payload = payload else { return -1 }
    let tokenPayload = Unmanaged<TokenPayload>.fromOpaque(payload).takeUnretainedValue()
    let result = git_cred_userpass_plaintext_new(cred, "x-access-token", tokenPayload.token)
    return (result != GIT_OK.rawValue) ? -1 : 0
}

extension Repository {

    /// Push the current branch to a remote.
    ///
    /// - Parameters:
    ///   - remoteName: The name of the remote to push to (default: "origin").
    ///   - token: A GitHub personal access token or OAuth token for authentication.
    /// - Throws: `EMError.git` cases for authentication, rejection, or network errors.
    public func push(remote remoteName: String = "origin", token: String) throws {
        // Look up the remote.
        var remotePointer: OpaquePointer? = nil
        var result = git_remote_lookup(&remotePointer, self.pointer, remoteName)
        guard result == GIT_OK.rawValue else {
            throw pushError(code: result, pointOfFailure: "git_remote_lookup")
        }
        defer { git_remote_free(remotePointer) }

        // Detect the current branch refspec from HEAD.
        let refspec = try currentBranchRefspec()

        // Build push options with credential callback.
        let tokenPayload = TokenPayload(token)
        let payloadPointer = Unmanaged.passRetained(tokenPayload).toOpaque()
        defer { Unmanaged<TokenPayload>.fromOpaque(payloadPointer).release() }

        var options = git_push_options()
        git_push_init_options(&options, UInt32(GIT_PUSH_OPTIONS_VERSION))
        options.callbacks.payload = UnsafeMutableRawPointer(payloadPointer)
        options.callbacks.credentials = pushCredentialsCallback

        // Build the refspec strarray and push.
        var refspecCString: UnsafeMutablePointer<CChar>? = strdup(refspec)
        defer { free(refspecCString) }
        try withUnsafeMutablePointer(to: &refspecCString) { stringsPtr in
            var refspecs = git_strarray(strings: stringsPtr, count: 1)
            let pushResult = git_remote_push(remotePointer, &refspecs, &options)
            guard pushResult == GIT_OK.rawValue else {
                throw pushError(code: pushResult, pointOfFailure: "git_remote_push")
            }
        }
    }

    // MARK: - Private Helpers

    /// Detect the current branch and return the push refspec (e.g. "refs/heads/main:refs/heads/main").
    private func currentBranchRefspec() throws -> String {
        var headRef: OpaquePointer? = nil
        let result = git_repository_head(&headRef, self.pointer)
        guard result == GIT_OK.rawValue else {
            throw pushError(code: result, pointOfFailure: "git_repository_head")
        }
        defer { git_reference_free(headRef) }

        guard let namePtr = git_reference_name(headRef) else {
            throw EMError.git(.pushFailed(
                underlying: NSError(
                    domain: "EMGit",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not determine current branch name."]
                )
            ))
        }
        let branchName = String(cString: namePtr)
        return "\(branchName):\(branchName)"
    }

    /// Map a libgit2 error code to an appropriate `EMError.git` case.
    private func pushError(code: Int32, pointOfFailure: String) -> EMError {
        let message: String
        let errorClass: Int32
        if let lastError = giterr_last() {
            message = lastError.pointee.message.map { String(cString: $0) }
                ?? "\(pointOfFailure) failed with code \(code)."
            errorClass = lastError.pointee.klass
        } else {
            message = "\(pointOfFailure) failed with code \(code)."
            errorClass = -1
        }

        // Authentication errors (GIT_EAUTH = -16).
        if code == -16 || message.contains("401") || message.contains("authentication") {
            return .git(.authenticationExpired)
        }

        // Non-fast-forward / rejected push.
        if message.contains("non-fast-forward") || message.contains("rejected") || message.contains("cannot push") {
            return .git(.pushRejected(reason: message))
        }

        // Network errors (GITERR_NET = 12).
        if errorClass == 12 || message.contains("resolve") || message.contains("connect") || message.contains("network") {
            return .git(.networkUnavailable)
        }

        return .git(.pushFailed(underlying: NSError(
            domain: "org.libgit2.SwiftGit2",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: message]
        )))
    }
}
