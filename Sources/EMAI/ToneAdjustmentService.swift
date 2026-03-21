/// Orchestrates the AI Tone Adjustment flow per FEAT-023.
/// Selects a provider, builds the prompt, streams tokens, and manages session state.
/// Lives in EMAI (primary package per feature-to-package mapping).

import Foundation
import Observation
import os
import EMCore

/// The current state of a tone adjustment session.
public enum ToneAdjustmentSessionState: Sendable {
    /// No active session.
    case idle
    /// AI is generating tone-adjusted text.
    case generating
    /// Generation completed successfully.
    case completed
    /// Generation failed with an error.
    case failed(EMError)
    /// User cancelled the session.
    case cancelled
}

/// Service that manages AI Tone Adjustment sessions.
/// Created by AIProviderManager, used by EMEditor's coordinator.
@MainActor
@Observable
public final class ToneAdjustmentService {
    /// Current session state.
    public private(set) var state: ToneAdjustmentSessionState = .idle

    /// The original text being adjusted.
    public private(set) var originalText: String = ""

    /// The tone-adjusted text accumulated so far (streams progressively).
    public private(set) var adjustedText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "tone-adjustment")

    /// Signpost for measuring first-token and total latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "tone")

    /// Creates a tone adjustment service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts a tone adjustment session for the given text.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - selectedText: The text the user selected to adjust.
    ///   - toneStyle: The target tone style.
    ///   - surroundingContext: Optional surrounding paragraph for context.
    ///   - contentType: The detected content type of the selection.
    /// - Returns: An `AsyncStream` of `ToneAdjustmentUpdate` values.
    public func startAdjusting(
        selectedText: String,
        toneStyle: ToneStyle,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AsyncStream<ToneAdjustmentUpdate> {
        // Cancel any existing session
        cancel()

        originalText = selectedText
        adjustedText = ""
        state = .generating

        let prompt = ToneAdjustmentPromptTemplate.buildPrompt(
            selectedText: selectedText,
            toneStyle: toneStyle,
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

                // Select provider per [A-030] — tone adjustment requires cloud (Pro AI)
                guard let provider = await self.providerManager.selectProvider(
                    for: .adjustTone(style: toneStyle),
                    context: context
                ) else {
                    let error = EMError.ai(.subscriptionRequired)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for tone adjustment")

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

                        self.adjustedText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.adjustedText))
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
                        self.logger.error("Tone adjustment failed: \(error.localizedDescription)")
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

    /// Cancels the current tone adjustment session.
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
        adjustedText = ""
        state = .idle
    }
}
