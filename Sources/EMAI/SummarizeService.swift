/// Orchestrates the AI Summarize flow per FEAT-055.
/// Selects a provider, builds the prompt, streams tokens, and manages session state.
/// Lives in EMAI (primary package per [A-050]).

import Foundation
import Observation
import os
import EMCore

/// The current state of a summarize session.
public enum SummarizeSessionState: Sendable {
    /// No active session.
    case idle
    /// AI is generating the summary.
    case generating
    /// Generation completed successfully.
    case completed
    /// Generation failed with an error.
    case failed(EMError)
    /// User cancelled the session.
    case cancelled
}

/// Service that manages AI Summarize sessions.
/// Created by AIProviderManager, used by EMEditor's coordinator.
@MainActor
@Observable
public final class SummarizeService {
    /// Current session state.
    public private(set) var state: SummarizeSessionState = .idle

    /// The original text being summarized.
    public private(set) var originalText: String = ""

    /// The summary text accumulated so far (streams progressively).
    public private(set) var summaryText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "summarize")

    /// Signpost for measuring first-token and total latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "summarize")

    /// Creates a summarize service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts a summarize session for the given text.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - selectedText: The text the user selected to summarize.
    ///   - surroundingContext: Optional surrounding paragraph for context.
    ///   - contentType: The detected content type of the selection.
    ///   - isFullDocument: Whether the entire document is selected.
    /// - Returns: An `AsyncStream` of `SummarizeUpdate` values.
    public func startSummarizing(
        selectedText: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose,
        isFullDocument: Bool = false
    ) -> AsyncStream<SummarizeUpdate> {
        // Cancel any existing session
        cancel()

        originalText = selectedText
        summaryText = ""
        state = .generating

        let prompt = SummarizePromptTemplate.buildPrompt(
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            contentType: contentType,
            isFullDocument: isFullDocument
        )

        return AsyncStream<SummarizeUpdate> { [weak self] (continuation: AsyncStream<SummarizeUpdate>.Continuation) in
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
                    for: .summarize,
                    context: context
                ) else {
                    let error = EMError.ai(.deviceNotSupported)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for summarize")

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

                        self.summaryText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.summaryText))
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
                        self.logger.error("Summarize failed: \(error.localizedDescription)")
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

    /// Cancels the current summarize session.
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
        summaryText = ""
        state = .idle
    }
}
