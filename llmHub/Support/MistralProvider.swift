import Foundation

@MainActor
struct MistralProvider: LLMProvider {
    nonisolated let id: String = "mistral"
    nonisolated let name: String = "Mistral"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.Mistral

    init(keychain: KeychainStore, config: ProvidersConfig.Mistral) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        if let url = config.baseURL { return url }
        return URL(string: "https://api.mistral.ai/v1")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String: String] {
        get async {
            guard let key = await keychain.apiKey(for: .mistral) else { return [:] }
            return [
                "Authorization": "Bearer \(key)",
                "Content-Type": "application/json",
            ]
        }
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    var isConfigured: Bool {
        get async {
            await keychain.apiKey(for: .mistral) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = await keychain.apiKey(for: .mistral) else { return [] }
        let manager = MistralManager(apiKey: apiKey)
        let models = try await manager.listModels()
        return models.data.map {
            LLMModel(id: $0.id, name: $0.id, maxOutputTokens: 4096)  // Approximate defaults
        }
    }

    func buildRequest(messages: [ChatMessage], model: String) async throws -> URLRequest {
        try await buildRequest(messages: messages, model: model, jsonMode: false)
    }

    func buildRequest(messages: [ChatMessage], model: String, jsonMode: Bool) async throws
        -> URLRequest
    {
        guard let apiKey = await keychain.apiKey(for: .mistral) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = MistralManager(apiKey: apiKey)

        // Map messages
        let mistralMessages = messages.map { msg -> MistralMessage in
            // Check for parts
            if !msg.parts.isEmpty {
                var mistralParts: [MistralContentPart] = []

                // Add text if present
                if !msg.content.isEmpty {
                    mistralParts.append(.text(msg.content))
                }

                for part in msg.parts {
                    switch part {
                    case .text(let t):
                        if t != msg.content { mistralParts.append(.text(t)) }
                    case .image(let data, _):
                        mistralParts.append(.image(base64: data.base64EncodedString()))
                    case .imageURL(let url):
                        // Assuming direct URL for now, could fetch if needed
                        mistralParts.append(
                            MistralContentPart(
                                type: "image_url", text: nil,
                                imageUrl: MistralImageURL(url: url.absoluteString)))
                    }
                }

                if mistralParts.isEmpty {
                    return MistralMessage(role: msg.role.rawValue, content: .text(msg.content))
                }

                return MistralMessage(role: msg.role.rawValue, content: .parts(mistralParts))
            } else {
                // Legacy / Text only
                return MistralMessage(role: msg.role.rawValue, content: .text(msg.content))
            }
        }

        // Default to non-streaming request builder
        return try manager.makeChatRequest(
            messages: mistralMessages,
            model: model,
            stream: false
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            Task {
                do {
                    // 1. Modify request to enable streaming if not already
                    var streamRequest = request
                    // Ensure stream=true in body
                    if let bodyData = request.httpBody,
                        var json = try? JSONSerialization.jsonObject(with: bodyData)
                            as? [String: Any]
                    {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    // 2. Execute
                    let (result, response) = try await LLMURLSession.shared.bytes(
                        for: streamRequest)

                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        continuation.yield(
                            .error(
                                .server(
                                    reason: errorText.isEmpty ? "Unknown stream error" : errorText))
                        )
                        continuation.finish()
                        return
                    }

                    var fullText = ""
                    var toolCallsInProgress: [Int: PendingToolCall] = [:]
                    var lastFinishReason: String? = nil

                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }

                            guard let data = jsonStr.data(using: .utf8),
                                let chunk = try? JSONDecoder().decode(
                                    MistralStreamChunk.self, from: data),
                                let choice = chunk.choices.first
                            else { continue }

                            if let content = choice.delta.content {
                                fullText += content
                                continuation.yield(.token(text: content))
                            }

                            if let toolCalls = choice.delta.toolCalls {
                                for tc in toolCalls {
                                    let idx = tc.index
                                    if toolCallsInProgress[idx] == nil {
                                        toolCallsInProgress[idx] = PendingToolCall(
                                            index: idx, id: nil, name: nil, arguments: "")
                                    }

                                    if let id = tc.id {
                                        toolCallsInProgress[idx]?.id = id
                                    }
                                    if let name = tc.function?.name {
                                        toolCallsInProgress[idx]?.name = name
                                    }
                                    if let args = tc.function?.arguments {
                                        toolCallsInProgress[idx]?.arguments += args
                                    }
                                }
                            }

                            // Track the finish reason
                            if let finishReason = choice.finishReason {
                                lastFinishReason = finishReason
                            }

                            if choice.finishReason == "tool_calls" {
                                for (_, tc) in toolCallsInProgress.sorted(by: { $0.key < $1.key }) {
                                    if let id = tc.id, let name = tc.name {
                                        continuation.yield(
                                            .toolUse(id: id, name: name, input: tc.arguments))
                                    }
                                }
                            }

                            // Usage in final chunk
                            if let usage = chunk.usage {
                                continuation.yield(
                                    .usage(
                                        TokenUsage(
                                            inputTokens: usage.promptTokens,
                                            outputTokens: usage.completionTokens,
                                            cachedTokens: 0
                                        )))
                            }
                        }
                    }

                    // Final completion
                    let message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        parts: [],  // Initialize with empty parts
                        createdAt: Date(),
                        codeBlocks: [],
                        tokenUsage: nil,
                        costBreakdown: nil
                    )

                    // Check if response was truncated due to max_tokens
                    if lastFinishReason == "length" {
                        continuation.yield(.truncated(message: message))
                    } else {
                        continuation.yield(.completion(message: message))
                    }
                    continuation.finish()

                } catch {
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
            }
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        let decoded = try? JSONDecoder().decode(MistralChatResponse.self, from: response)
        if let usage = decoded?.usage {
            return TokenUsage(
                inputTokens: usage.promptTokens,
                outputTokens: usage.completionTokens,
                cachedTokens: 0
            )
        }
        return nil
    }
}
