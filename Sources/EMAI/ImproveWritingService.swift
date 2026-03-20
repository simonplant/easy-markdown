/// Orchestrates the AI Improve Writing flow per FEAT-011.
/// Selects a provider, builds the prompt, streams tokens, and manages session state.
/// Lives in EMAI (primary package per [A-050]).

import Foundation
import Observation
import os
import EMCore

/// The current state of an improve writing session.
public enum ImproveSessionState: Sendable {
    /// No active session.
    case idle
    /// AI is generating improved text.
    case generating
    /// Generation completed successfully.
    case completed
    /// Generation failed with an error.
    case failed(EMError)
    /// User cancelled the session.
    case cancelled
}

/// Service that manages AI Improve Writing sessions.
/// Created by AIProviderManager, used by EMEditor's coordinator.
@MainActor
@Observable
public final class ImproveWritingService {
    /// Current session state.
    public private(set) var state: ImproveSessionState = .idle

    /// The original text being improved.
    public private(set) var originalText: String = ""

    /// The improved text accumulated so far (streams progressively).
    public private(set) var improvedText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "improve-writing")

    /// Signpost for measuring first-token and total latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "improve")

    /// Creates an improve writing service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts an improve writing session for the given text.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - selectedText: The text the user selected to improve.
    ///   - surroundingContext: Optional surrounding paragraph for context.
    ///   - contentType: The detected content type of the selection.
    /// - Returns: An `AsyncStream` of `ImproveWritingUpdate` values.
    public func startImproving(
        selectedText: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AsyncStream<ImproveWritingUpdate> {
        // Cancel any existing session
        cancel()

        originalText = selectedText
        improvedText = ""
        state = .generating

        let prompt = ImprovePromptTemplate.buildPrompt(
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            contentType: contentType
        )

        return AsyncStream { [weak self] continuation in
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
                    for: .improve,
                    context: context
                ) else {
                    let error = EMError.ai(.deviceNotSupported)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for improve")

                var isFirstToken = true
                let fullID = self.signposter.makeSignpostID()
                var fullState: OSSignposter.State?
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

                        self.improvedText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.improvedText))
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
                        self.logger.error("Improve writing failed: \(error.localizedDescription)")
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

    /// Cancels the current improve session.
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
        originalText = ""
        improvedText = ""
        state = .idle
    }
}
