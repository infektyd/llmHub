import Foundation

struct GoogleAIProvider: LLMProvider, Sendable {
    let id: String = "google"
    let name: String = "Google AI"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.GoogleAI

    init(keychain: KeychainStore, config: ProvidersConfig.GoogleAI) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        // Replace with the official Gemini/Vertex AI endpoint depending on your integration
        config.baseURL ?? URL(string: "https://generativelanguage.googleapis.com")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String : String] {
        // Some Google endpoints use API key as query param. If headers are required, set here.
        ["Content-Type": "application/json"]
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        // Replace path, query key, and payload per Google AI docs (Gemini/Vertex)
        var url = endpoint
        // Example path placeholder; consult docs
        url.appendPathComponent("/v1beta/models/\(model):generateContent")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let apiKey = keychain.apiKey(for: .google) {
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }
        guard let finalURL = components.url else { throw LLMProviderError.invalidRequest }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let payload = GooglePayload(messages: messages.map { GoogleMessage(role: $0.role.rawValue, parts: [GooglePart(text: $0.content)]) })
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            // TODO: Implement streaming per Google AI docs
            continuation.finish()
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        // TODO: Parse token usage per Google AI response schema
        return nil
    }
}

private struct GooglePayload: Encodable {
    let messages: [GoogleMessage]
}

private struct GoogleMessage: Encodable {
    let role: String
    let parts: [GooglePart]
}

private struct GooglePart: Encodable {
    let text: String
}
