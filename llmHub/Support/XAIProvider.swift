import Foundation

struct XAIProvider: LLMProvider, Sendable {
    let id: String = "xai"
    let name: String = "xAI"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.XAI

    init(keychain: KeychainStore, config: ProvidersConfig.XAI) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        // Replace with the official xAI endpoint
        config.baseURL ?? URL(string: "https://api.x.ai")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String : String] {
        guard let key = keychain.apiKey(for: .xai) else { return [:] }
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
        // Replace path and payload structure per xAI docs
        let url = endpoint.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let payload = XAIPayload(model: model, messages: messages.map { XAIMessage(role: $0.role.rawValue, content: $0.content) })
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            // TODO: Implement streaming per xAI docs
            continuation.finish()
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        // TODO: Parse token usage per xAI response schema
        return nil
    }
}

private struct XAIPayload: Encodable {
    let model: String
    let messages: [XAIMessage]
}

private struct XAIMessage: Encodable {
    let role: String
    let content: String
}
