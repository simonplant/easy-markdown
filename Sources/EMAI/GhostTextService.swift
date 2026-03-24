/// Orchestrates the AI Continue Writing (ghost text) flow per FEAT-056.
/// Selects a provider, builds the prompt, streams tokens, and manages session state.
/// Lives in EMAI (primary package per [A-050]).

import Foundation
import Observation
import os
import EMCore

/// The current state of a ghost text session.
public enum GhostTextSessionState: Sendable {
    /// No active session.
    case idle
    /// AI is generating the continuation.
    case generating
    /// Generation completed successfully.
    case completed
    /// Generation failed with an error.
    case failed(EMError)
    /// User cancelled the session.
    case cancelled
}

/// Service that manages AI Continue Writing (ghost text) sessions.
/// Created by AIProviderManager, used by EMEditor's ghost text coordinator.
@MainActor
@Observable
public final class GhostTextService {
    /// Current session state.
    public private(set) var state: GhostTextSessionState = .idle

    /// The preceding text used as context.
    public private(set) var precedingText: String = ""

    /// The continuation text accumulated so far (streams progressively).
    public private(set) var continuationText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "ghost-text")

    /// Signpost for measuring first-token and total latency per [A-037].
    /// First token target: <500ms per [D-PERF-4].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "ghost-text")

    /// Creates a ghost text service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts a ghost text generation session for the given preceding text.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - precedingText: The text before the cursor position (last ~500 chars).
    ///   - surroundingContext: Optional broader document context.
    /// - Returns: An `AsyncStream` of `GhostTextUpdate` values.
    public func startGenerating(
        precedingText: String,
        surroundingContext: String? = nil
    ) -> AsyncStream<GhostTextUpdate> {
        // Cancel any existing session
        cancel()

        self.precedingText = precedingText
        continuationText = ""
        state = .generating

        let prompt = ContinueWritingPromptTemplate.buildPrompt(
            precedingText: precedingText,
            surroundingContext: surroundingContext
        )

        return AsyncStream<GhostTextUpdate> { [weak self] (continuation: AsyncStream<GhostTextUpdate>.Continuation) in
            guard let self else {
                continuation.finish()
                return
            }

            self.generationTask = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                let firstTokenID = self.signposter.makeSignpostID()
                let firstTokenState = self.signposter.beginInterval("first-token", id: firstTokenID)

                let context = self.providerManager.makeContext()

                // Select provider per [A-030]
                guard let provider = await self.providerManager.selectProvider(
                    for: .ghostTextComplete,
                    context: context
                ) else {
                    let error = EMError.ai(.deviceNotSupported)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for ghost text")

                var isFirstToken = true
                let fullID = self.signposter.makeSignpostID()
                var fullState: OSSignpostIntervalState?
                let tokenStream = provider.generate(prompt: prompt, context: context)

                do {
                    for try await token in tokenStream {
                        if Task.isCancelled {
                            self.state = .cancelled
                            continuation.finish()
                            if let s = fullState {
                                self.signposter.endInterval("full-generation", s)
                            } else {
                                self.signposter.endInterval("first-token", firstTokenState)
                            }
                            return
                        }

                        if isFirstToken {
                            isFirstToken = false
                            self.signposter.endInterval("first-token", firstTokenState)
                            fullState = self.signposter.beginInterval("full-generation", id: fullID)
                        }

                        self.continuationText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.continuationText))
                    continuation.finish()
                    if let s = fullState {
                        self.signposter.endInterval("full-generation", s)
                    }
                } catch {
                    if Task.isCancelled {
                        self.state = .cancelled
                    } else {
                        let emError = EMError.ai(.inferenceFailed(underlying: error))
                        self.state = .failed(emError)
                        continuation.yield(.failed(emError))
                        self.logger.error("Ghost text generation failed: \(error.localizedDescription)")
                    }
                    continuation.finish()
                    if let s = fullState {
                        self.signposter.endInterval("full-generation", s)
                    } else {
                        self.signposter.endInterval("first-token", firstTokenState)
                    }
                }
            }

            // Capture task reference for @Sendable onTermination closure
            let task = self.generationTask
            continuation.onTermination = { _ in
                task?.cancel()
            }
        }
    }

    /// Cancels the current ghost text session.
    public func cancel() {
        generationTask?.cancel()
        generationTask = nil
        if case .generating = state {
            state = .cancelled
        }
    }

    /// Resets the service to idle state.
    public func reset() {
        cancel()
        precedingText = ""
        continuationText = ""
        state = .idle
    }
}
