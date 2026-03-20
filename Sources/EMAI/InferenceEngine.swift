import Foundation

/// Abstraction for the on-device inference runtime per [A-008].
/// SPIKE-005 determines whether this is backed by MLX Swift or Core ML.
///
/// Implementations are registered with `ModelLoader.setInferenceEngine(_:)`
/// once the runtime is selected. The engine receives the memory-mapped
/// model data at initialization and owns tokenization + forward pass.
public protocol InferenceEngine: Sendable {
    /// Generates tokens from a prompt, streaming results.
    /// Must emit the first token within 500ms on A16+/M1+ per [D-PERF-4].
    func generateTokens(prompt: String) -> AsyncThrowingStream<String, Error>
}

/// Errors specific to inference engine lifecycle.
public enum InferenceEngineError: Error, Sendable {
    /// No inference engine has been configured. SPIKE-005 must complete
    /// to determine MLX Swift vs Core ML runtime.
    case noEngineConfigured
}
