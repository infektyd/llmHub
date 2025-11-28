import Foundation

struct AnthropicProvider: LLMProvider, Sendable {
    let id: String = "anthropic"
    let name: String = "Anthropic"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.Anthropic

    init(keychain: KeychainStore, config: ProvidersConfig.Anthropic) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        // Replace with the official Anthropic Messages API endpoint from docs
        config.baseURL ?? URL(string: "https://api.anthropic.com")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String : String] {
        guard let key = keychain.apiKey(for: .anthropic) else { return [:] }
        // Replace header names and version keys exactly per Anthropic docs
        var headers: [String: String] = [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
        if let version = config.apiVersion { headers["anthropic-version"] = version }
        return headers
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        guard defaultHeaders["Authorization"] != nil else { throw LLMProviderError.authenticationMissing }
        // Replace path and payload shape exactly per Anthropic docs
        let url = endpoint.appendingPathComponent("/v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let payload = AnthropicPayload(
            model: model,
            messages: messages.map { AnthropicMessage(role: $0.role.rawValue, content: $0.content) }
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            // TODO: Implement server-sent event (SSE) or streaming per Anthropic docs
            continuation.finish()
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        // TODO: Parse token usage fields exactly per Anthropic response schema
        return nil
    }
}

private struct AnthropicPayload: Encodable {
    let model: String
    let messages: [AnthropicMessage]
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}
