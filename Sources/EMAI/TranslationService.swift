/// Orchestrates the AI Translation flow per FEAT-024.
/// Selects a provider, builds the prompt, streams tokens, and manages session state.
/// Lives in EMAI (primary package per feature-to-package mapping).

import Foundation
import Observation
import os
import EMCore

/// The current state of a translation session.
public enum TranslationSessionState: Sendable {
    /// No active session.
    case idle
    /// AI is generating translated text.
    case generating
    /// Generation completed successfully.
    case completed
    /// Generation failed with an error.
    case failed(EMError)
    /// User cancelled the session.
    case cancelled
}

/// Service that manages AI Translation sessions.
/// Created by AIProviderManager, used by EMEditor's coordinator.
@MainActor
@Observable
public final class TranslationService {
    /// Current session state.
    public private(set) var state: TranslationSessionState = .idle

    /// The original text being translated.
    public private(set) var originalText: String = ""

    /// The translated text accumulated so far (streams progressively).
    public private(set) var translatedText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "translation")

    /// Signpost for measuring first-token and total latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "translation")

    /// Creates a translation service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts a translation session for the given text.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - selectedText: The text the user selected to translate.
    ///   - targetLanguage: The target language code (e.g. "es", "fr").
    ///   - surroundingContext: Optional surrounding paragraph for context.
    ///   - contentType: The detected content type of the selection.
    /// - Returns: An `AsyncStream` of `TranslationUpdate` values.
    public func startTranslating(
        selectedText: String,
        targetLanguage: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AsyncStream<TranslationUpdate> {
        // Cancel any existing session
        cancel()

        originalText = selectedText
        translatedText = ""
        state = .generating

        let prompt = TranslationPromptTemplate.buildPrompt(
            selectedText: selectedText,
            targetLanguage: targetLanguage,
            surroundingContext: surroundingContext,
            contentType: contentType
        )

        return AsyncStream<TranslationUpdate> { [weak self] (continuation: AsyncStream<TranslationUpdate>.Continuation) in
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

                // Select provider per [A-030] — translation requires cloud (Pro AI)
                guard let provider = await self.providerManager.selectProvider(
                    for: .translate(targetLanguage: targetLanguage),
                    context: context
                ) else {
                    let error = EMError.ai(.subscriptionRequired)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for translation to \(targetLanguage)")

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

                        self.translatedText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.translatedText))
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
                        self.logger.error("Translation failed: \(error.localizedDescription)")
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

    /// Cancels the current translation session.
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
        translatedText = ""
        state = .idle
    }
}
