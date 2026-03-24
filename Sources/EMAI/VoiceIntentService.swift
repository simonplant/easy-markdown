/// Orchestrates the AI Voice Intent flow per FEAT-068.
/// Takes a voice transcript, interprets the intent, and streams the modified text.
/// Lives in EMAI (primary package per [A-050]).

import Foundation
import Observation
import os
import EMCore

/// The current state of a voice intent session.
public enum VoiceIntentSessionState: Sendable {
    /// No active session.
    case idle
    /// AI is interpreting the voice command and generating modified text.
    case generating
    /// Generation completed successfully.
    case completed
    /// Generation failed with an error.
    case failed(EMError)
    /// User cancelled the session.
    case cancelled
}

/// Service that manages AI Voice Intent sessions.
/// Created by AIProviderManager, used by EMEditor's VoiceCoordinator.
@MainActor
@Observable
public final class VoiceIntentService {
    /// Current session state.
    public private(set) var state: VoiceIntentSessionState = .idle

    /// The transcript that was sent to the AI.
    public private(set) var transcript: String = ""

    /// The modified text accumulated so far (streams progressively).
    public private(set) var modifiedText: String = ""

    private let providerManager: AIProviderManager
    private var generationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "voice-intent")

    /// Signpost for measuring first-token and total latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emai", category: "voice-intent")

    /// Creates a voice intent service.
    /// - Parameter providerManager: The AI provider manager for provider selection.
    public init(providerManager: AIProviderManager) {
        self.providerManager = providerManager
    }

    /// Starts a voice intent session for the given transcript and text.
    /// Streams tokens back via the returned `AsyncStream`.
    /// - Parameters:
    ///   - transcript: The transcribed speech from the user.
    ///   - selectedText: The text to operate on (selection or current paragraph).
    ///   - surroundingContext: Optional surrounding paragraph for context.
    ///   - contentType: The detected content type of the selection.
    /// - Returns: An `AsyncStream` of `ImproveWritingUpdate` values.
    public func startInterpretingIntent(
        transcript: String,
        selectedText: String,
        surroundingContext: String? = nil,
        contentType: ContentType = .prose
    ) -> AsyncStream<ImproveWritingUpdate> {
        // Cancel any existing session
        cancel()

        self.transcript = transcript
        modifiedText = ""
        state = .generating

        let prompt = VoiceIntentPromptTemplate.buildPrompt(
            transcript: transcript,
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            contentType: contentType
        )

        return AsyncStream<ImproveWritingUpdate> { [weak self] (continuation: AsyncStream<ImproveWritingUpdate>.Continuation) in
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

                // Select provider per [A-030] — voice intent uses local model
                guard let provider = await self.providerManager.selectProvider(
                    for: .intentFromVoice(transcript: transcript),
                    context: context
                ) else {
                    let error = EMError.ai(.deviceNotSupported)
                    self.state = .failed(error)
                    continuation.yield(.failed(error))
                    continuation.finish()
                    self.signposter.endInterval("first-token", firstTokenState)
                    return
                }

                self.logger.debug("Using provider: \(provider.name) for voice intent")

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

                        self.modifiedText += token
                        continuation.yield(.token(token))
                    }

                    self.state = .completed
                    continuation.yield(.completed(fullText: self.modifiedText))
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
                        self.logger.error("Voice intent failed: \(error.localizedDescription)")
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

    /// Cancels the current voice intent session.
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
        transcript = ""
        modifiedText = ""
        state = .idle
    }
}
