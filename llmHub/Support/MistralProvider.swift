import Foundation

struct MistralProvider: LLMProvider, Sendable {
    let id: String = "mistral"
    let name: String = "Mistral"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.Mistral

    init(keychain: KeychainStore, config: ProvidersConfig.Mistral) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        // Replace with the official Mistral endpoint
        config.baseURL ?? URL(string: "https://api.mistral.ai")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String : String] {
        guard let key = keychain.apiKey(for: .mistral) else { return [:] }
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
        // Replace path and payload structure per Mistral docs
        let url = endpoint.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let payload = MistralPayload(model: model, messages: messages.map { MistralMessage(role: $0.role.rawValue, content: $0.content) })
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            // TODO: Implement streaming per Mistral docs
            continuation.finish()
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        // TODO: Parse token usage per Mistral response schema
        return nil
    }
}

private struct MistralPayload: Encodable {
    let model: String
    let messages: [MistralMessage]
}

private struct MistralMessage: Encodable {
    let role: String
    let content: String
}
