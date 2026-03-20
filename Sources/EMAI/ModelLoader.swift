import Foundation
import os
import EMCore

/// Loads and manages the on-device AI model for inference per [A-008].
/// Memory-maps the model to minimize RAM impact per AC-5.
/// Designed as a contained, removable component — may become unnecessary if Apple ships platform AI.
public actor ModelLoader {
    /// Whether a model is currently loaded and ready for inference.
    public private(set) var isLoaded: Bool = false

    /// Memory footprint of the loaded model in bytes.
    public private(set) var modelMemoryFootprint: Int64 = 0

    private let storage: ModelStorageManager
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "model")
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "inference")

    /// Maximum memory budget for model loading per AC-5 (100MB editing session budget).
    /// The model itself is memory-mapped separately and does not count against this.
    public static let memoryBudgetBytes: Int64 = 100 * 1024 * 1024

    /// Handle to the memory-mapped model data.
    private var modelData: Data?

    /// The inference engine, set when a runtime is configured post SPIKE-005.
    /// Callers provide this via `setInferenceEngine(_:)` once the
    /// MLX Swift or Core ML runtime is selected.
    private var inferenceEngine: InferenceEngine?

    public init(storage: ModelStorageManager) {
        self.storage = storage
    }

    /// Registers the inference engine to use for token generation.
    /// Called once the runtime is determined by SPIKE-005 (MLX Swift or Core ML).
    public func setInferenceEngine(_ engine: InferenceEngine) {
        self.inferenceEngine = engine
    }

    /// Loads the model into memory using memory-mapping.
    /// Memory-mapped to minimize RAM impact — the OS pages in only what's needed per AC-5.
    public func loadModel() async throws {
        guard !isLoaded else { return }
        guard storage.isModelPresent else {
            throw EMError.ai(.modelNotDownloaded)
        }

        logger.info("Loading model from \(self.storage.modelFileURL.lastPathComponent)")

        // Memory-map the model file — OS manages paging, minimizes RSS
        let data = try Data(
            contentsOf: storage.modelFileURL,
            options: [.mappedIfSafe, .uncached]
        )

        modelData = data
        modelMemoryFootprint = Int64(data.count)
        isLoaded = true

        logger.info("Model loaded (memory-mapped, \(data.count) bytes)")
    }

    /// Unloads the model from memory.
    public func unloadModel() {
        modelData = nil
        isLoaded = false
        modelMemoryFootprint = 0
        logger.info("Model unloaded")
    }

    /// Runs inference on the loaded model, streaming tokens.
    /// First token target: <500ms per [D-PERF-4] and AC-4.
    ///
    /// The pipeline:
    /// 1. Validates model is loaded and inference engine is configured
    /// 2. Begins os_signpost interval for first-token latency measurement
    /// 3. Delegates to the InferenceEngine for tokenization and forward pass
    /// 4. Streams generated tokens back to the caller
    public func runInference(prompt: String) -> AsyncThrowingStream<String, Error> {
        let loadedData = modelData
        let engine = inferenceEngine
        let signposter = self.signposter
        let logger = self.logger

        return AsyncThrowingStream { continuation in
            guard loadedData != nil else {
                continuation.finish(throwing: EMError.ai(.modelNotDownloaded))
                return
            }

            guard let engine else {
                // Model is loaded but no inference runtime configured yet.
                // SPIKE-005 must complete to determine MLX Swift vs Core ML.
                continuation.finish(throwing: EMError.ai(.inferenceFailed(
                    underlying: InferenceEngineError.noEngineConfigured
                )))
                return
            }

            Task {
                let signpostID = signposter.makeSignpostID()
                let state = signposter.beginInterval("inference", id: signpostID)
                var firstTokenEmitted = false

                do {
                    let tokenStream = engine.generateTokens(prompt: prompt)
                    for try await token in tokenStream {
                        if !firstTokenEmitted {
                            signposter.emitEvent("first-token", id: signpostID)
                            firstTokenEmitted = true
                        }
                        continuation.yield(token)
                    }
                    signposter.endInterval("inference", state)
                    continuation.finish()
                } catch {
                    signposter.endInterval("inference", state)
                    logger.error("Inference failed: \(error.localizedDescription)")
                    continuation.finish(throwing: EMError.ai(.inferenceFailed(underlying: error)))
                }
            }
        }
    }
}
