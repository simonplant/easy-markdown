import Foundation
import EMCore

/// Unified AI inference protocol per [A-029].
/// All providers (platform, local, cloud) conform to this interface.
public protocol AIProvider: Sendable {
    /// Human-readable name for UI display.
    var name: String { get }

    /// Whether this provider is currently available for inference.
    var isAvailable: Bool { get async }

    /// Whether this provider requires a network connection.
    var requiresNetwork: Bool { get }

    /// Whether this provider requires a Pro AI subscription.
    var requiresSubscription: Bool { get }

    /// Run inference and stream results token by token.
    func generate(
        prompt: AIPrompt,
        context: AIContext
    ) -> AsyncThrowingStream<String, Error>

    /// Check if the provider can handle this specific action.
    func supports(action: AIAction) -> Bool
}

/// What the AI should do.
public enum AIAction: Sendable {
    case improve
    case summarize
    case continueWriting
    case ghostTextComplete
    case smartComplete
    case translate(targetLanguage: String)
    case adjustTone(style: ToneStyle)
    case generateFromPrompt
    case analyzeDocument
    case editDiagram
    case intentFromVoice(transcript: String)
}

/// Tone adjustment styles for AI writing assistance.
public enum ToneStyle: String, Sendable {
    case formal
    case casual
    case academic
    case concise
    case friendly
}

/// Input to the AI provider.
public struct AIPrompt: Sendable {
    /// The action to perform.
    public let action: AIAction
    /// The user-selected text to operate on.
    public let selectedText: String
    /// Surrounding context (paragraph or section around selection).
    public let surroundingContext: String?
    /// System prompt from versioned template.
    public let systemPrompt: String
    /// Detected content type for content-aware prompting.
    public let contentType: ContentType

    public init(
        action: AIAction,
        selectedText: String,
        surroundingContext: String? = nil,
        systemPrompt: String,
        contentType: ContentType = .prose
    ) {
        self.action = action
        self.selectedText = selectedText
        self.surroundingContext = surroundingContext
        self.systemPrompt = systemPrompt
        self.contentType = contentType
    }
}

/// Detected content type for content-aware prompting per [A-032].
public enum ContentType: Sendable {
    case prose
    case codeBlock(language: String?)
    case table
    case mermaid
    case mixed
}

/// Device and runtime context passed to provider selection and inference.
public struct AIContext: Sendable {
    /// The current device's AI capability.
    public let deviceCapability: DeviceCapability
    /// Whether the device is currently offline.
    public let isOffline: Bool
    /// Subscription status provider for checking Pro AI access.
    public let subscriptionStatus: any SubscriptionStatusProviding

    public init(
        deviceCapability: DeviceCapability,
        isOffline: Bool,
        subscriptionStatus: any SubscriptionStatusProviding
    ) {
        self.deviceCapability = deviceCapability
        self.isOffline = isOffline
        self.subscriptionStatus = subscriptionStatus
    }
}
