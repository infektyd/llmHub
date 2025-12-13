import Foundation

@MainActor
struct OpenAIProvider: LLMProvider {
    nonisolated let id: String = "openai"
    nonisolated let name: String = "OpenAI"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.OpenAI

    init(keychain: KeychainStore, config: ProvidersConfig.OpenAI) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        if let url = config.baseURL { return url }
        return URL(string: "https://api.openai.com/v1")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String: String] {
        get async {
            guard let key = await keychain.apiKey(for: .openAI) else { return [:] }
            return [
                "Authorization": "Bearer \(key)",
                "Content-Type": "application/json",
            ]
        }
    }

    var pricing: PricingMetadata {
        config.pricing
            ?? PricingMetadata(inputPer1KUSD: 0.005, outputPer1KUSD: 0.015, currency: "USD")
    }

    var isConfigured: Bool {
        get async {
            await keychain.apiKey(for: .openAI) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = await keychain.apiKey(for: .openAI) else { return [] }
        let manager = OpenAIManager(apiKey: apiKey)

        do {
            let models = try await manager.listModels()
            return models.map { model in
                LLMModel(
                    id: model.id,
                    name: model.id,
                    maxOutputTokens: 4096  // Default as API doesn't return this
                )
            }
        } catch {
            return config.models  // Fallback
        }
    }

    func buildRequest(messages: [ChatMessage], model: String) async throws -> URLRequest {
        try await buildRequest(messages: messages, model: model, tools: nil, jsonMode: false)
    }

    func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) async throws
        -> URLRequest
    {
        try await buildRequest(messages: messages, model: model, tools: tools, jsonMode: false)
    }

    func buildRequest(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]?, jsonMode: Bool
    ) async throws -> URLRequest {
        guard let apiKey = await keychain.apiKey(for: .openAI) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = OpenAIManager(apiKey: apiKey)
        let endpoint = ModelRouter.endpoint(for: model)

        // Map messages
        let openAIMessages = messages.map { msg -> OpenAIChatMessage in
            // Handle tool role messages
            if msg.role == .tool {
                return OpenAIChatMessage(
                    role: "tool",
                    content: .text(msg.content),
                    toolCallId: msg.toolCallID
                )
            }

            // Handle assistant messages with tool calls
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                let openAIToolCalls = toolCalls.map { tc in
                    OpenAIToolCall(
                        id: tc.id,
                        type: "function",
                        function: OpenAIToolCall.FunctionCall(name: tc.name, arguments: tc.input)
                    )
                }
                return OpenAIChatMessage(
                    role: "assistant",
                    content: .text(msg.content),
                    toolCalls: openAIToolCalls
                )
            }

            // Check for parts
            if !msg.parts.isEmpty {
                var parts: [OpenAIContentPart] = []

                if !msg.content.isEmpty {
                    parts.append(.text(msg.content))
                }

                for part in msg.parts {
                    switch part {
                    case .text(let t):
                        if t != msg.content { parts.append(.text(t)) }
                    case .image(let data, let mimeType):
                        parts.append(.image(base64: data.base64EncodedString(), mimeType: mimeType))
                    case .imageURL(let url):
                        parts.append(.image(url: url.absoluteString))
                    }
                }

                if parts.isEmpty {
                    return OpenAIChatMessage(role: msg.role.rawValue, content: .text(msg.content))
                }
                return OpenAIChatMessage(role: msg.role.rawValue, content: .parts(parts))
            } else {
                return OpenAIChatMessage(role: msg.role.rawValue, content: .text(msg.content))
            }
        }

        // Convert tool definitions to OpenAI format
        let openAITools: [OpenAITool]? = tools?.map { toolDef in
            OpenAITool(
                type: "function",
                function: OpenAIFunction(
                    name: toolDef.name,
                    description: toolDef.description,
                    parameters: toolDef.inputSchema.mapValues { OpenAIJSONValue.from($0) }
                )
            )
        }

        // Build request based on endpoint
        switch endpoint {
        case .responses:
            return try manager.makeResponsesRequest(
                messages: openAIMessages,
                model: model,
                tools: openAITools,
                jsonMode: jsonMode
            )
        case .chatCompletions:
            return try manager.makeChatRequest(
                messages: openAIMessages,
                model: model,
                stream: false,
                tools: openAITools,
                responseFormat: jsonMode ? OpenAIResponseFormat(type: "json_object") : nil
            )
        }
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            Task {
                do {
                    // Non-streaming responses endpoint
                    if request.url?.path.contains("/responses") == true {
                        var req = request
                        if let bodyData = req.httpBody,
                            var json = try? JSONSerialization.jsonObject(with: bodyData)
                                as? [String: Any]
                        {
                            json["stream"] = false
                            req.httpBody = try JSONSerialization.data(withJSONObject: json)
                        }
                        let (data, response) = try await LLMURLSession.shared.data(for: req)
                        guard let http = response as? HTTPURLResponse,
                            (200...299).contains(http.statusCode)
                        else {
                            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                            continuation.yield(.error(.server(reason: errorText)))
                            continuation.finish()
                            return
                        }
                        let decoded = try JSONDecoder().decode(
                            OpenAIResponseEnvelope.self, from: data)
                        let text =
                            decoded.output?
                            .compactMap { $0.text }
                            .joined(separator: "\n")
                            .nilIfEmpty
                            ?? decoded.output?
                            .compactMap { $0.contentText }
                            .joined(separator: "\n")
                            .nilIfEmpty
                            ?? ""
                        let message = ChatMessage(
                            id: UUID(),
                            role: .assistant,
                            content: text,
                            parts: [.text(text)],
                            createdAt: Date(),
                            codeBlocks: []
                        )
                        continuation.yield(.completion(message: message))
                        continuation.finish()
                        return
                    }

                    var streamRequest = request
                    if let bodyData = request.httpBody,
                        var json = try? JSONSerialization.jsonObject(with: bodyData)
                            as? [String: Any]
                    {
                        json["stream"] = true
                        json["stream_options"] = ["include_usage": true]
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

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
                        guard trimmed.hasPrefix("data: ") else { continue }

                        let jsonStr = String(trimmed.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        guard
                            let data = jsonStr.data(using: .utf8),
                            let chunk = try? JSONDecoder().decode(
                                OpenAIStreamChunk.self, from: data),
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

                    var message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        parts: [],
                        createdAt: Date(),
                        codeBlocks: [],
                        tokenUsage: nil,
                        costBreakdown: nil
                    )

                    if !toolCallsInProgress.isEmpty {
                        message.toolCalls = toolCallsInProgress.sorted(by: { $0.key < $1.key })
                            .compactMap { (_, tc) in
                                guard let id = tc.id, let name = tc.name else { return nil }
                                return ToolCall(id: id, name: name, input: tc.arguments)
                            }
                    }

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
        let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: response)
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

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
