import Foundation
import os
import EMCore

/// Cloud AI provider via SSE streaming per [A-009] and [A-029].
/// Requires Pro AI subscription. Sends only user-selected text per [D-AI-8].
/// No logging of prompts or responses.
public final class CloudAPIProvider: AIProvider, Sendable {
    public let name = "Pro AI"
    public let requiresNetwork = true
    public let requiresSubscription = true

    private let relayURL: URL
    private let networkMonitor: NetworkMonitor
    private let subscriptionStatus: any SubscriptionStatusProviding
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "cloud-provider")

    /// Timeout for cloud requests before suggesting local AI as fallback.
    public static let requestTimeoutSeconds: TimeInterval = 10

    /// Creates a cloud API provider.
    /// - Parameters:
    ///   - relayURL: The URL of the lightweight API relay server.
    ///   - networkMonitor: Network state monitor.
    ///   - subscriptionStatus: Subscription status for checking Pro AI access.
    public init(
        relayURL: URL,
        networkMonitor: NetworkMonitor,
        subscriptionStatus: any SubscriptionStatusProviding
    ) {
        self.relayURL = relayURL
        self.networkMonitor = networkMonitor
        self.subscriptionStatus = subscriptionStatus
    }

    public var isAvailable: Bool {
        get async {
            guard networkMonitor.isConnected else { return false }
            return await subscriptionStatus.isProSubscriptionActive
        }
    }

    public func supports(action: AIAction) -> Bool {
        // Cloud supports all actions
        true
    }

    public func generate(
        prompt: AIPrompt,
        context: AIContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { [relayURL, subscriptionStatus, logger] continuation in
            Task {
                do {
                    // Verify subscription before each request per [A-057]
                    guard await subscriptionStatus.isProSubscriptionActive else {
                        continuation.finish(throwing: EMError.ai(.subscriptionRequired))
                        return
                    }

                    // Get signed transaction JWS for server-side validation
                    guard let receiptJWS = await subscriptionStatus.subscriptionReceiptJWS else {
                        continuation.finish(throwing: EMError.ai(.subscriptionRequired))
                        return
                    }

                    // Build SSE request
                    var request = URLRequest(url: relayURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(receiptJWS)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = Self.requestTimeoutSeconds

                    // Only send selected text per [D-AI-8] — no retention
                    let body: [String: String] = [
                        "prompt": prompt.selectedText,
                        "system": prompt.systemPrompt,
                        "context": prompt.surroundingContext ?? "",
                    ]
                    request.httpBody = try JSONEncoder().encode(body)

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: EMError.ai(.cloudUnavailable))
                        return
                    }

                    switch httpResponse.statusCode {
                    case 200...299:
                        break
                    case 401:
                        continuation.finish(throwing: EMError.ai(.subscriptionExpired))
                        return
                    default:
                        continuation.finish(throwing: EMError.ai(.cloudUnavailable))
                        return
                    }

                    // Parse SSE stream
                    for try await line in asyncBytes.lines {
                        try Task.checkCancellation()

                        // SSE format: "data: <token>"
                        guard line.hasPrefix("data: ") else { continue }
                        let token = String(line.dropFirst(6))

                        if token == "[DONE]" {
                            break
                        }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as EMError {
                    continuation.finish(throwing: error)
                } catch {
                    logger.error("Cloud inference failed: \(error.localizedDescription)")
                    if (error as? URLError)?.code == .timedOut {
                        continuation.finish(throwing: EMError.ai(.inferenceTimeout))
                    } else if (error as? URLError)?.code == .notConnectedToInternet
                                || (error as? URLError)?.code == .networkConnectionLost {
                        continuation.finish(throwing: EMError.ai(.cloudUnavailable))
                    } else {
                        continuation.finish(throwing: EMError.ai(.cloudUnavailable))
                    }
                }
            }
        }
    }
}
