import Foundation

/// Root error type for all easy-markdown errors per [A-035].
/// Every case includes a user-facing message and recovery options.
public enum EMError: LocalizedError {

    case file(FileError)
    case ai(AIError)
    case parse(ParseError)
    case purchase(PurchaseError)
    case git(GitError)
    case unexpected(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .file(let error): return error.errorDescription
        case .ai(let error): return error.errorDescription
        case .parse(let error): return error.errorDescription
        case .purchase(let error): return error.errorDescription
        case .git(let error): return error.errorDescription
        case .unexpected: return "Something unexpected happened. Your work is safe."
        }
    }

    // MARK: - File Errors

    public enum FileError: LocalizedError {
        case notUTF8(url: URL)
        case accessDenied(url: URL)
        case notFound(url: URL)
        case saveFailed(url: URL, underlying: Error)
        case tooLarge(url: URL, sizeBytes: Int)
        case externallyDeleted(url: URL)
        case bookmarkStale(url: URL)

        public var errorDescription: String? {
            switch self {
            case .notUTF8: return "This file isn't valid UTF-8 text."
            case .accessDenied: return "Permission denied. Try opening the file again."
            case .notFound: return "This file has been moved or deleted."
            case .saveFailed: return "Couldn't save. Your changes are still in memory — try again."
            case .tooLarge: return "This file is too large to open."
            case .externallyDeleted: return "This file was deleted while you were editing."
            case .bookmarkStale: return "This file's access has expired. Re-open it from the file picker to restore access."
            }
        }
    }

    // MARK: - AI Errors

    public enum AIError: LocalizedError {
        case modelNotDownloaded
        case modelDownloadFailed(underlying: Error)
        case inferenceTimeout
        case inferenceFailed(underlying: Error)
        case deviceNotSupported
        case cloudUnavailable
        case subscriptionRequired
        case subscriptionExpired

        public var errorDescription: String? {
            switch self {
            case .modelNotDownloaded: return "AI model hasn't been downloaded yet."
            case .modelDownloadFailed: return "AI model download failed. Check your connection."
            case .inferenceTimeout: return "Cloud AI took too long. Try using on-device AI instead."
            case .inferenceFailed: return "AI couldn't process that. Try again."
            case .deviceNotSupported: return "AI features require a newer device."
            case .cloudUnavailable: return "Can't reach cloud AI. Try using on-device AI instead."
            case .subscriptionRequired: return "This feature requires Pro AI."
            case .subscriptionExpired: return "Your Pro AI subscription has expired."
            }
        }
    }

    // MARK: - Parse Errors

    public enum ParseError: LocalizedError {
        case timeout(lineCount: Int)

        public var errorDescription: String? {
            switch self {
            case .timeout(let lines):
                return "Document (\(lines) lines) took too long to parse."
            }
        }
    }

    // MARK: - Purchase Errors

    public enum PurchaseError: LocalizedError {
        case productNotFound
        case purchaseFailed(underlying: Error?)
        case userCancelled
        case purchasePending
        case receiptValidationFailed(underlying: Error)
        case restoreFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .productNotFound:
                return "Couldn't load the purchase. Check your connection and try again."
            case .purchaseFailed:
                return "Purchase failed. You haven't been charged."
            case .userCancelled:
                return nil // Silent — user chose to cancel.
            case .purchasePending:
                return "Purchase is pending approval."
            case .receiptValidationFailed:
                return "Couldn't verify your purchase. Try restoring purchases."
            case .restoreFailed:
                return "Couldn't restore purchases. Check your connection and try again."
            }
        }
    }

    // MARK: - Git Errors

    public enum GitError: LocalizedError {
        case authenticationFailed
        case authenticationExpired
        case deviceFlowTimeout
        case deviceFlowDenied
        case networkUnavailable
        case keychainAccessFailed(underlying: Error)
        case repoListFailed(underlying: Error)
        case pushRejected(reason: String)
        case pushFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .authenticationFailed:
                return "GitHub sign-in failed. Please try again."
            case .authenticationExpired:
                return "Your GitHub session has expired. Please sign in again."
            case .deviceFlowTimeout:
                return "Sign-in timed out. Please try again."
            case .deviceFlowDenied:
                return "Access was denied. Please try again and approve the request."
            case .networkUnavailable:
                return "Can't reach GitHub. Check your connection and try again."
            case .keychainAccessFailed:
                return "Couldn't access saved credentials."
            case .repoListFailed:
                return "Couldn't load your repositories. Check your connection."
            case .pushRejected(let reason):
                return "Push was rejected: \(reason)"
            case .pushFailed:
                return "Couldn't push to GitHub. Check your connection and try again."
            }
        }
    }

    // MARK: - Error Severity Classification

    /// The severity of this error, determining how it is presented to the user.
    public var severity: ErrorSeverity {
        switch self {
        case .file(let fileError):
            switch fileError {
            case .saveFailed:
                return .recoverable
            case .externallyDeleted:
                return .dataLossRisk
            case .notFound:
                return .dataLossRisk
            case .accessDenied:
                return .recoverable
            case .notUTF8:
                return .informational
            case .tooLarge:
                return .informational
            case .bookmarkStale:
                return .recoverable
            }

        case .ai(let aiError):
            switch aiError {
            case .inferenceTimeout, .inferenceFailed, .cloudUnavailable:
                return .recoverable
            case .modelDownloadFailed:
                return .recoverable
            case .modelNotDownloaded, .deviceNotSupported,
                 .subscriptionRequired, .subscriptionExpired:
                return .informational
            }

        case .purchase(let purchaseError):
            switch purchaseError {
            case .userCancelled:
                return .informational
            case .purchasePending:
                return .informational
            case .purchaseFailed, .restoreFailed:
                return .recoverable
            case .productNotFound, .receiptValidationFailed:
                return .recoverable
            }

        case .git(let gitError):
            switch gitError {
            case .authenticationExpired:
                return .recoverable
            case .authenticationFailed, .deviceFlowTimeout, .deviceFlowDenied:
                return .recoverable
            case .networkUnavailable, .repoListFailed, .pushRejected, .pushFailed:
                return .recoverable
            case .keychainAccessFailed:
                return .informational
            }

        case .parse:
            return .informational

        case .unexpected:
            return .recoverable
        }
    }

    /// Creates a presentable error with optional recovery actions.
    public func presentable(recoveryActions: [RecoveryAction] = []) -> PresentableError {
        PresentableError(
            message: errorDescription ?? "Something went wrong.",
            severity: severity,
            recoveryActions: recoveryActions
        )
    }
}
