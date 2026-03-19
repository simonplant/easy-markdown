import Testing
import Foundation
@testable import EMApp
@testable import EMCore

@Suite("ErrorPresenter")
struct ErrorPresenterTests {

    @Test("Initial state has no banner or modal")
    @MainActor
    func initialState() {
        let presenter = ErrorPresenter()
        #expect(presenter.currentBanner == nil)
        #expect(presenter.currentModal == nil)
    }

    @Test("Recoverable error shows as banner")
    @MainActor
    func recoverableBanner() {
        let presenter = ErrorPresenter()
        let error = PresentableError(message: "Save failed", severity: .recoverable)
        presenter.present(error)
        #expect(presenter.currentBanner != nil)
        #expect(presenter.currentBanner?.message == "Save failed")
        #expect(presenter.currentModal == nil)
    }

    @Test("Informational error shows as banner")
    @MainActor
    func informationalBanner() {
        let presenter = ErrorPresenter()
        let error = PresentableError(message: "File is large", severity: .informational)
        presenter.present(error)
        #expect(presenter.currentBanner != nil)
        #expect(presenter.currentModal == nil)
    }

    @Test("Data-loss-risk error shows as modal")
    @MainActor
    func dataLossModal() {
        let presenter = ErrorPresenter()
        let error = PresentableError(message: "File deleted", severity: .dataLossRisk)
        presenter.present(error)
        #expect(presenter.currentModal != nil)
        #expect(presenter.currentModal?.message == "File deleted")
        #expect(presenter.currentBanner == nil)
    }

    @Test("Dismiss banner clears current banner")
    @MainActor
    func dismissBanner() {
        let presenter = ErrorPresenter()
        let error = PresentableError(message: "Error", severity: .recoverable)
        presenter.present(error)
        presenter.dismissBanner()
        #expect(presenter.currentBanner == nil)
    }

    @Test("Dismiss modal clears current modal")
    @MainActor
    func dismissModal() {
        let presenter = ErrorPresenter()
        let error = PresentableError(message: "Error", severity: .dataLossRisk)
        presenter.present(error)
        presenter.dismissModal()
        #expect(presenter.currentModal == nil)
    }

    @Test("Queued banners show after dismiss")
    @MainActor
    func bannerQueue() {
        let presenter = ErrorPresenter()
        let first = PresentableError(message: "First", severity: .recoverable)
        let second = PresentableError(message: "Second", severity: .recoverable)

        presenter.present(first)
        presenter.present(second)

        #expect(presenter.currentBanner?.message == "First")

        presenter.dismissBanner()
        #expect(presenter.currentBanner?.message == "Second")
    }

    @Test("Queue empties after all dismissed")
    @MainActor
    func bannerQueueEmpties() {
        let presenter = ErrorPresenter()
        let first = PresentableError(message: "First", severity: .recoverable)
        let second = PresentableError(message: "Second", severity: .informational)

        presenter.present(first)
        presenter.present(second)
        presenter.dismissBanner()
        presenter.dismissBanner()

        #expect(presenter.currentBanner == nil)
    }

    @Test("Convenience method routes EMError correctly")
    @MainActor
    func convenienceEMError() {
        let presenter = ErrorPresenter()
        presenter.present(.ai(.inferenceTimeout))
        #expect(presenter.currentBanner != nil)
        #expect(presenter.currentBanner?.message.contains("too long") == true)
    }

    @Test("Convenience method with recovery actions")
    @MainActor
    func convenienceWithActions() {
        let presenter = ErrorPresenter()
        let action = RecoveryAction(label: "Retry") {}
        presenter.present(.ai(.cloudUnavailable), recoveryActions: [action])
        #expect(presenter.currentBanner?.recoveryActions.count == 1)
        #expect(presenter.currentBanner?.recoveryActions[0].label == "Retry")
    }

    @Test("Modal and banner can coexist")
    @MainActor
    func modalAndBannerCoexist() {
        let presenter = ErrorPresenter()
        let banner = PresentableError(message: "Network issue", severity: .recoverable)
        let modal = PresentableError(message: "File deleted", severity: .dataLossRisk)

        presenter.present(banner)
        presenter.present(modal)

        #expect(presenter.currentBanner != nil)
        #expect(presenter.currentModal != nil)
    }
}
