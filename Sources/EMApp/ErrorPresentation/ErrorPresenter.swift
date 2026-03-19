import SwiftUI
import EMCore

/// Centralized error presentation manager per [A-035] and FEAT-065.
/// Manages the queue of errors to display and their lifecycle.
///
/// - Recoverable errors: shown as non-modal banners, auto-dismiss after 8 seconds.
/// - Data-loss-risk errors: shown as modal alerts, require user action.
/// - Informational warnings: shown as dismissable banners, no auto-dismiss.
@MainActor
@Observable
public final class ErrorPresenter {
    /// The current banner error (recoverable or informational). Nil when no banner is shown.
    public private(set) var currentBanner: PresentableError?

    /// The current modal error (data-loss-risk). Nil when no modal is shown.
    public private(set) var currentModal: PresentableError?

    /// Queued banner errors waiting to be shown after the current one dismisses.
    private var bannerQueue: [PresentableError] = []

    /// Active auto-dismiss task for the current banner.
    private var autoDismissTask: Task<Void, Never>?

    /// Duration before a recoverable banner auto-dismisses.
    private let autoDismissSeconds: UInt64

    public init(autoDismissSeconds: UInt64 = 8) {
        self.autoDismissSeconds = autoDismissSeconds
    }

    /// Present an error to the user. Routes to banner or modal based on severity.
    public func present(_ error: PresentableError) {
        switch error.severity {
        case .dataLossRisk:
            currentModal = error
        case .recoverable, .informational:
            if currentBanner != nil {
                bannerQueue.append(error)
            } else {
                showBanner(error)
            }
        }
    }

    /// Convenience: present an EMError with optional recovery actions.
    public func present(_ error: EMError, recoveryActions: [RecoveryAction] = []) {
        present(error.presentable(recoveryActions: recoveryActions))
    }

    /// Dismiss the current banner and show the next queued one, if any.
    public func dismissBanner() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        currentBanner = nil
        showNextBanner()
    }

    /// Dismiss the current modal alert.
    public func dismissModal() {
        currentModal = nil
    }

    // MARK: - Private

    private func showBanner(_ error: PresentableError) {
        currentBanner = error
        if error.severity == .recoverable {
            scheduleAutoDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self, autoDismissSeconds] in
            try? await Task.sleep(nanoseconds: autoDismissSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    private func showNextBanner() {
        guard !bannerQueue.isEmpty else { return }
        let next = bannerQueue.removeFirst()
        showBanner(next)
    }
}
