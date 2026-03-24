/// Orchestrates the AI Smart Completions flow per FEAT-025.
/// Selects a provider, builds the prompt, streams tokens, and manages session state.
/// Lives in EMAI (primary package per [A-050]).

import Foundation
import Observation
import os
import EMCore

/// Service that manages AI Smart Completion sessions.
/// Created by AIProviderManager, used by EMEditor's smart completion coordinator.
@MainActor
@Observable
public final class SmartCompletionService {
    /// Current session state.
    public private(set) var state: GhostTextSessionState = .idle

    /// The completion text accumulated so far (streams progressively).
    public private(set) var completionText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "smart-completion")

    /// Signpost for measuring first-token and total latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "smart-completion")

    /// Creates a smart completion service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts a smart completion session for the detected markdown structure.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - structureType: The detected markdown structure at the cursor.
    ///   - precedingText: The text before the cursor position (last ~500 chars).
    ///   - surroundingContext: Optional broader document context.
    /// - Returns: An `AsyncStream` of `GhostTextUpdate` values.
    public func startCompleting(
        structureType: SmartCompletionPromptTemplate.StructureType,
        precedingText: String,
        surroundingContext: String? = nil
    ) -> AsyncStream<GhostTextUpdate> {
        // Cancel any existing session
        cancel()

        completionText = ""
        state = .generating

        let prompt = SmartCompletionPromptTemplate.buildPrompt(
            structureType: structureType,
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

                // Select provider per [A-030] — smartComplete is supported by LocalModelProvider
                guard let provider = await self.providerManager.selectProvider(
                    for: .smartComplete,
                    context: context
                ) else {
                    let error = EMError.ai(.deviceNotSupported)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for smart completion")

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

                        self.completionText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.completionText))
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
                        self.logger.error("Smart completion failed: \(error.localizedDescription)")
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

    /// Cancels the current smart completion session.
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
        completionText = ""
        state = .idle
    }
}
