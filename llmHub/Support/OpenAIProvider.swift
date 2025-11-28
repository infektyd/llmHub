import Foundation

struct OpenAIProvider: LLMProvider, Sendable {
    let id: String = "openai"
    let name: String = "OpenAI"
    let endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
    let supportsStreaming: Bool = true

    let availableModels: [LLMModel] = [
        .init(id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128_000, supportsToolUse: true, maxOutputTokens: 16_384)
    ]

    let pricing: PricingMetadata = PricingMetadata(inputPer1KUSD: 0.005, outputPer1KUSD: 0.015, currency: "USD")

    private let keychain: KeychainStore

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    var defaultHeaders: [String: String] {
        guard let key = keychain.apiKey(for: .openAI) else { return [:] }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
    }

    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        guard defaultHeaders["Authorization"] != nil else {
            throw LLMProviderError.authenticationMissing
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        defaultHeaders.forEach { header, value in
            request.setValue(value, forHTTPHeaderField: header)
        }
        let payload = OpenAIPayload(
            model: model,
            messages: messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            temperature: nil,
            maxTokens: nil,
            topP: nil,
            frequencyPenalty: nil,
            presencePenalty: nil,
            stop: nil
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            // TODO: Implement streaming (SSE/Chunked) parsing for real responses.
            // For now, immediately finish to keep the pipeline compiling.
            continuation.finish()
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        // TODO: Parse actual token usage from OpenAI response.
        return nil
    }
}

private struct OpenAIPayload: Encodable {
    let model: String
    let messages: [[String: String]]
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let stop: [String]?
}
