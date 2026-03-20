import Foundation
import EMCore

/// Future Apple platform AI provider per [A-007] and [A-029].
/// Currently a stub that returns `isAvailable = false`.
/// When Apple ships system AI APIs (evaluated in SPIKE-008 after WWDC 2026),
/// implement this first — it has the highest selection priority.
public struct ApplePlatformAIProvider: AIProvider {
    public let name = "Apple AI"
    public let requiresNetwork = false
    public let requiresSubscription = false

    public init() {}

    public var isAvailable: Bool {
        get async { false }
    }

    public func supports(action: AIAction) -> Bool {
        // Will support all actions when Apple platform AI ships
        false
    }

    public func generate(
        prompt: AIPrompt,
        context: AIContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: EMError.ai(.deviceNotSupported)) }
    }
}
