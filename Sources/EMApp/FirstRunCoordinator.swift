import Foundation
import Observation
import EMCore
import EMSettings
import EMAI

/// Coordinates the first-run experience per FEAT-044 and [D-UX-1].
///
/// After a 2-second delay on capable devices, shows a non-modal banner
/// offering AI model download. The banner is dismissable — if dismissed,
/// the user is asked again on next launch. On unsupported devices, no
/// prompt appears.
@MainActor
@Observable
final class FirstRunCoordinator {
    private let settings: SettingsManager
    private let capability: DeviceCapability
    private let downloadManager: ModelDownloadManager?

    /// Whether the model download banner should be visible.
    private(set) var showModelDownloadBanner = false

    /// Initializes with the given settings manager and device capability.
    ///
    /// - Parameters:
    ///   - settings: The settings manager for persisting download state.
    ///   - downloadManager: The EMAI download manager for starting actual downloads.
    ///   - capability: The detected device capability. Defaults to auto-detection.
    init(
        settings: SettingsManager,
        downloadManager: ModelDownloadManager? = nil,
        capability: DeviceCapability = .detect()
    ) {
        self.settings = settings
        self.downloadManager = downloadManager
        self.capability = capability
    }

    /// Evaluates whether to show the first-run AI download prompt.
    /// Called once from the root view's `.task` modifier.
    ///
    /// Shows the banner after a 2-second delay if:
    /// - Device supports AI (A16+/M1+)
    /// - Model is not already downloaded
    /// - Model is not currently downloading
    func evaluateFirstRunPrompt() async {
        guard capability == .fullAI else { return }
        guard settings.modelDownloadState == .notDownloaded else { return }

        // Brief delay so the user sees the home screen first.
        try? await Task.sleep(for: .seconds(2))

        // If the task was cancelled during sleep (e.g., view disappeared), bail out.
        guard !Task.isCancelled else { return }

        // Re-check after delay — user may have navigated or state changed.
        guard settings.modelDownloadState == .notDownloaded else { return }

        showModelDownloadBanner = true
    }

    /// User accepted the download prompt.
    /// Triggers the actual model download via EMAI's ModelDownloadManager.
    func acceptDownload() {
        showModelDownloadBanner = false
        settings.hasSeenModelDownloadPrompt = true
        settings.modelDownloadState = .downloading

        // Start the actual download via EMAI's download manager.
        downloadManager?.startDownload()
    }

    /// User dismissed the download prompt.
    /// They will be asked again on next launch.
    func dismissDownload() {
        showModelDownloadBanner = false
        // hasSeenModelDownloadPrompt stays false so the prompt
        // reappears on next launch, per spec: "asked again next launch".
    }
}
