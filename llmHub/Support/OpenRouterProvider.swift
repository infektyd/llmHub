import Foundation

struct OpenRouterProvider: LLMProvider, Sendable {
    let id: String = "openrouter"
    let name: String = "OpenRouter"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.OpenRouter

    init(keychain: KeychainStore, config: ProvidersConfig.OpenRouter) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        // Replace with the official OpenRouter endpoint
        config.baseURL ?? URL(string: "https://openrouter.ai/api")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String : String] {
        guard let key = keychain.apiKey(for: .openRouter) else { return [:] }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        guard defaultHeaders["Authorization"] != nil else { throw LLMProviderError.authenticationMissing }
        // Replace path and payload structure per OpenRouter docs
        let url = endpoint.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let payload = OpenRouterPayload(model: model, messages: messages.map { OpenRouterMessage(role: $0.role.rawValue, content: $0.content) })
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            // TODO: Implement streaming per OpenRouter docs
            continuation.finish()
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        // TODO: Parse token usage per OpenRouter response schema
        return nil
    }
}

private struct OpenRouterPayload: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
}

private struct OpenRouterMessage: Encodable {
    let role: String
    let content: String
}
