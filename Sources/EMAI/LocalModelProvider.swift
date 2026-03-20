import Foundation
import os
import EMCore

/// On-device AI inference provider per [A-008] and [A-029].
/// Uses MLX Swift or Core ML for inference (determined by SPIKE-005).
/// Only available on A16+/M1+ devices per [D-AI-5].
public final class LocalModelProvider: AIProvider, Sendable {
    public let name = "On-Device AI"
    public let requiresNetwork = false
    public let requiresSubscription = false

    private let modelLoader: ModelLoader
    private let storage: ModelStorageManager
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "local-provider")

    /// Creates a local model provider.
    /// - Parameters:
    ///   - modelLoader: The model loader responsible for loading/unloading the model.
    ///   - storage: Storage manager for checking model presence.
    public init(modelLoader: ModelLoader, storage: ModelStorageManager) {
        self.modelLoader = modelLoader
        self.storage = storage
    }

    public var isAvailable: Bool {
        get async {
            // Must be on a capable device AND have the model downloaded
            guard DeviceCapability.detect() == .fullAI else { return false }
            return storage.isModelPresent
        }
    }

    public func supports(action: AIAction) -> Bool {
        switch action {
        case .improve, .summarize, .continueWriting,
             .ghostTextComplete, .smartComplete:
            return true
        case .translate, .adjustTone, .generateFromPrompt,
             .analyzeDocument, .editDiagram, .intentFromVoice:
            // Complex actions require cloud provider (Pro AI)
            return false
        }
    }

    public func generate(
        prompt: AIPrompt,
        context: AIContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { [modelLoader, logger] continuation in
            Task {
                do {
                    // Ensure model is loaded
                    if await !modelLoader.isLoaded {
                        try await modelLoader.loadModel()
                    }

                    logger.debug("Starting local inference for action")

                    // Construct the full prompt from template
                    let fullPrompt = prompt.systemPrompt + "\n\n" + prompt.selectedText

                    // Stream tokens from the model
                    let stream = await modelLoader.runInference(prompt: fullPrompt)
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    logger.error("Local inference failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Preloads the model on app launch for capable devices.
    /// Call from EMApp at startup for A16+/M1+ devices.
    public func preloadModel() async throws {
        guard DeviceCapability.detect() == .fullAI else { return }
        guard storage.isModelPresent else { return }
        try await modelLoader.loadModel()
    }

    /// Unloads the model to free memory.
    public func unloadModel() async {
        await modelLoader.unloadModel()
    }
}
