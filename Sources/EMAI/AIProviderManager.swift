import Foundation
import Observation
import os
import EMCore

/// Validated URL constants — guard-let satisfies [A-048] (no force-unwrap).
private let defaultModelDownloadURL: URL = {
    guard let url = URL(string: "https://models.easymarkdown.app/v1/model.mlpackage") else {
        preconditionFailure("Invalid hardcoded model download URL")
    }
    return url
}()

private let defaultCloudRelayURL: URL = {
    guard let url = URL(string: "https://api.easymarkdown.app/v1/generate") else {
        preconditionFailure("Invalid hardcoded cloud relay URL")
    }
    return url
}()

/// Manages AI provider selection and lifecycle per [A-030].
/// Composition root for all AI functionality. Created by EMApp and injected via environment.
@MainActor
@Observable
public final class AIProviderManager {
    /// The currently selected/active provider, if any.
    public private(set) var activeProvider: (any AIProvider)?

    /// Whether any AI provider is available on this device.
    public private(set) var isAIAvailable: Bool = false

    /// The device's AI capability — gates all AI UI visibility per AC-6.
    public let deviceCapability: DeviceCapability

    /// The model download manager for on-device AI.
    public let downloadManager: ModelDownloadManager

    /// Storage manager for model files.
    public let storageManager: ModelStorageManager

    private let applePlatformProvider: ApplePlatformAIProvider
    private let localModelProvider: LocalModelProvider
    private let cloudProvider: CloudAPIProvider
    private let networkMonitor: NetworkMonitor
    private let subscriptionStatus: any SubscriptionStatusProviding
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "provider-manager")

    /// Creates the AI provider manager.
    /// - Parameters:
    ///   - subscriptionStatus: Subscription status bridge from EMCloud via EMCore protocol.
    ///   - modelDownloadURL: Remote URL for the AI model download.
    ///   - cloudRelayURL: URL of the cloud AI relay server.
    ///   - modelDirectory: Override for model storage directory (for testing).
    public init(
        subscriptionStatus: any SubscriptionStatusProviding,
        modelDownloadURL: URL = defaultModelDownloadURL,
        cloudRelayURL: URL = defaultCloudRelayURL,
        modelDirectory: URL? = nil
    ) {
        self.subscriptionStatus = subscriptionStatus
        self.deviceCapability = DeviceCapability.detect()
        self.networkMonitor = NetworkMonitor()
        self.storageManager = ModelStorageManager(modelDirectory: modelDirectory)

        let modelLoader = ModelLoader(storage: storageManager)

        self.applePlatformProvider = ApplePlatformAIProvider()
        self.localModelProvider = LocalModelProvider(
            modelLoader: modelLoader,
            storage: storageManager
        )
        self.cloudProvider = CloudAPIProvider(
            relayURL: cloudRelayURL,
            networkMonitor: networkMonitor,
            subscriptionStatus: subscriptionStatus
        )
        self.downloadManager = ModelDownloadManager(
            modelURL: modelDownloadURL,
            storage: storageManager,
            networkMonitor: networkMonitor
        )

        // On unsupported devices, AI is never available per AC-6
        if deviceCapability == .noAI {
            isAIAvailable = false
        }
    }

    /// Selects the best available provider for the given action per [A-030].
    /// Priority: platform AI → local model → cloud (if subscribed).
    public func selectProvider(
        for action: AIAction,
        context: AIContext
    ) async -> (any AIProvider)? {
        // No AI on unsupported devices per AC-6
        guard deviceCapability == .fullAI else { return nil }

        // 1. Platform AI — highest priority when available
        if await applePlatformProvider.isAvailable,
           applePlatformProvider.supports(action: action) {
            return applePlatformProvider
        }

        // 2. Local model — default for most actions
        if await localModelProvider.isAvailable,
           localModelProvider.supports(action: action) {
            return localModelProvider
        }

        // 3. Cloud — only if subscribed AND user opted in
        if await context.subscriptionStatus.isProSubscriptionActive,
           !context.isOffline,
           cloudProvider.supports(action: action) {
            return cloudProvider
        }

        return nil
    }

    /// Refreshes the AI availability state.
    /// Call after model download completes or subscription status changes.
    public func refreshAvailability() async {
        guard deviceCapability == .fullAI else {
            isAIAvailable = false
            return
        }

        if await applePlatformProvider.isAvailable {
            isAIAvailable = true
            activeProvider = applePlatformProvider
        } else if await localModelProvider.isAvailable {
            isAIAvailable = true
            activeProvider = localModelProvider
        } else if await cloudProvider.isAvailable {
            isAIAvailable = true
            activeProvider = cloudProvider
        } else {
            isAIAvailable = false
            activeProvider = nil
        }
    }

    /// Preloads the local model on app launch for capable devices.
    public func preloadLocalModel() async {
        guard deviceCapability == .fullAI else { return }
        do {
            try await localModelProvider.preloadModel()
            await refreshAvailability()
        } catch {
            logger.error("Failed to preload model: \(error.localizedDescription)")
        }
    }

    /// Whether AI UI elements should be shown per AC-3.
    /// iPhone 14 (including Pro) and older devices show no AI-related UI elements.
    public var shouldShowAIUI: Bool {
        deviceCapability == .fullAI
    }

    /// Whether the user has an active Pro AI subscription.
    /// Used by the floating action bar to show Pro badge vs upgrade prompt per FEAT-054.
    public func checkProSubscription() async -> Bool {
        await subscriptionStatus.isProSubscriptionActive
    }

    /// Creates an AIContext from current state.
    public func makeContext() -> AIContext {
        AIContext(
            deviceCapability: deviceCapability,
            isOffline: !networkMonitor.isConnected,
            subscriptionStatus: subscriptionStatus
        )
    }
}
