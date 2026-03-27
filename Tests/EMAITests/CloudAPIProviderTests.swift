import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("CloudAPIProvider", .serialized)
struct CloudAPIProviderTests {

    private func makeProvider(
        isProActive: Bool = false,
        receiptJWS: String? = nil
    ) -> CloudAPIProvider {
        CloudAPIProvider(
            relayURL: URL(string: "https://api.easymarkdown.app/v1/generate")!,
            networkMonitor: NetworkMonitor(),
            subscriptionStatus: MockSubscriptionStatus(
                isActive: isProActive,
                receiptJWS: receiptJWS
            )
        )
    }

    @Test("name is Pro AI")
    func name() {
        let provider = makeProvider()
        #expect(provider.name == "Pro AI")
    }

    @Test("requiresNetwork is true")
    func requiresNetwork() {
        let provider = makeProvider()
        #expect(provider.requiresNetwork == true)
    }

    @Test("requiresSubscription is true")
    func requiresSubscription() {
        let provider = makeProvider()
        #expect(provider.requiresSubscription == true)
    }

    @Test("supports all actions")
    func supportsAllActions() {
        let provider = makeProvider()
        #expect(provider.supports(action: .improve) == true)
        #expect(provider.supports(action: .summarize) == true)
        #expect(provider.supports(action: .translate(targetLanguage: "es")) == true)
        #expect(provider.supports(action: .adjustTone(style: .formal)) == true)
        #expect(provider.supports(action: .generateFromPrompt) == true)
        #expect(provider.supports(action: .analyzeDocument) == true)
        #expect(provider.supports(action: .editDiagram) == true)
    }

    @Test("requestTimeoutSeconds is 10")
    func timeout() {
        #expect(CloudAPIProvider.requestTimeoutSeconds == 10)
    }

    // MARK: - Retry tests

    /// URLProtocol subclass that fails the first N requests with a given URLError,
    /// then succeeds with an SSE response containing "[DONE]".
    private final class RetryStubProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var failuresRemaining = 0
        nonisolated(unsafe) static var failureCode: URLError.Code = .networkConnectionLost

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if Self.failuresRemaining > 0 {
                Self.failuresRemaining -= 1
                client?.urlProtocol(self, didFailWithError: URLError(Self.failureCode))
                return
            }
            let body = "data: [DONE]\n".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeProviderWithStub(session: URLSession) -> CloudAPIProvider {
        CloudAPIProvider(
            relayURL: URL(string: "https://api.easymarkdown.app/v1/generate")!,
            networkMonitor: NetworkMonitor(),
            subscriptionStatus: MockSubscriptionStatus(
                isActive: true,
                receiptJWS: "test-jws"
            ),
            session: session
        )
    }

    private func makeStubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RetryStubProtocol.self]
        return URLSession(configuration: config)
    }

    private func makePromptAndContext() -> (AIPrompt, AIContext) {
        let prompt = AIPrompt(
            action: .improve,
            selectedText: "Hello world",
            systemPrompt: "Improve this text."
        )
        let context = AIContext(
            deviceCapability: .fullAI,
            isOffline: false,
            subscriptionStatus: MockSubscriptionStatus(isActive: true, receiptJWS: "test-jws")
        )
        return (prompt, context)
    }

    @Test("generate retries once on networkConnectionLost then succeeds")
    func retryOnNetworkConnectionLost() async {
        RetryStubProtocol.failuresRemaining = 1
        RetryStubProtocol.failureCode = .networkConnectionLost

        let provider = makeProviderWithStub(session: makeStubSession())
        let (prompt, context) = makePromptAndContext()
        let stream = provider.generate(prompt: prompt, context: context)

        // Should complete without error — the retry handled the transient failure
        var thrownError: Error?
        do {
            for try await _ in stream {}
        } catch {
            thrownError = error
        }
        #expect(thrownError == nil, "Expected retry to handle networkConnectionLost, got \(String(describing: thrownError))")
    }

    @Test("generate retries once on timedOut then succeeds")
    func retryOnTimedOut() async {
        RetryStubProtocol.failuresRemaining = 1
        RetryStubProtocol.failureCode = .timedOut

        let provider = makeProviderWithStub(session: makeStubSession())
        let (prompt, context) = makePromptAndContext()
        let stream = provider.generate(prompt: prompt, context: context)

        var thrownError: Error?
        do {
            for try await _ in stream {}
        } catch {
            thrownError = error
        }
        #expect(thrownError == nil, "Expected retry to handle timedOut, got \(String(describing: thrownError))")
    }

    @Test("generate fails after two consecutive transient errors")
    func failsAfterMaxRetries() async {
        RetryStubProtocol.failuresRemaining = 2
        RetryStubProtocol.failureCode = .networkConnectionLost

        let provider = makeProviderWithStub(session: makeStubSession())
        let (prompt, context) = makePromptAndContext()
        let stream = provider.generate(prompt: prompt, context: context)

        var thrownError: Error?
        do {
            for try await _ in stream {}
        } catch {
            thrownError = error
        }

        #expect(thrownError != nil, "Expected failure after 2 consecutive transient errors")
        if let emError = thrownError as? EMError, case .ai(.cloudUnavailable) = emError {
            // Expected — surfaces as cloudUnavailable
        } else {
            Issue.record("Expected EMError.ai(.cloudUnavailable), got \(String(describing: thrownError))")
        }
    }

    @Test("generate does NOT retry on notConnectedToInternet")
    func noRetryOnNotConnected() async {
        RetryStubProtocol.failuresRemaining = 1
        RetryStubProtocol.failureCode = .notConnectedToInternet

        let provider = makeProviderWithStub(session: makeStubSession())
        let (prompt, context) = makePromptAndContext()
        let stream = provider.generate(prompt: prompt, context: context)

        var thrownError: Error?
        do {
            for try await _ in stream {}
        } catch {
            thrownError = error
        }

        #expect(thrownError != nil, "Expected immediate failure for notConnectedToInternet")
        if let emError = thrownError as? EMError, case .ai(.cloudUnavailable) = emError {
            // Expected — immediate failure, no retry
        } else {
            Issue.record("Expected EMError.ai(.cloudUnavailable), got \(String(describing: thrownError))")
        }
    }

    @Test("generate throws subscriptionRequired when not subscribed")
    func generateWithoutSubscription() async {
        let provider = makeProvider(isProActive: false)
        let prompt = AIPrompt(
            action: .improve,
            selectedText: "Hello world",
            systemPrompt: "Improve this text."
        )
        let context = AIContext(
            deviceCapability: .fullAI,
            isOffline: false,
            subscriptionStatus: MockSubscriptionStatus(isActive: false)
        )

        var thrownError: Error?
        let stream = provider.generate(prompt: prompt, context: context)
        do {
            for try await _ in stream {
                Issue.record("Expected stream to throw, not yield tokens")
            }
        } catch {
            thrownError = error
        }

        #expect(thrownError is EMError)
        if let emError = thrownError as? EMError, case .ai(.subscriptionRequired) = emError {
            // Expected
        } else {
            Issue.record("Expected EMError.ai(.subscriptionRequired), got \(String(describing: thrownError))")
        }
    }

    @Test("generate throws subscriptionRequired when no receipt JWS available")
    func generateWithoutReceipt() async {
        let provider = makeProvider(isProActive: true, receiptJWS: nil)
        let prompt = AIPrompt(
            action: .improve,
            selectedText: "Hello world",
            systemPrompt: "Improve this text."
        )
        let context = AIContext(
            deviceCapability: .fullAI,
            isOffline: false,
            subscriptionStatus: MockSubscriptionStatus(isActive: true)
        )

        var thrownError: Error?
        let stream = provider.generate(prompt: prompt, context: context)
        do {
            for try await _ in stream {
                Issue.record("Expected stream to throw, not yield tokens")
            }
        } catch {
            thrownError = error
        }

        #expect(thrownError is EMError)
        if let emError = thrownError as? EMError, case .ai(.subscriptionRequired) = emError {
            // Expected — no JWS means can't authenticate
        } else {
            Issue.record("Expected EMError.ai(.subscriptionRequired), got \(String(describing: thrownError))")
        }
    }
}
