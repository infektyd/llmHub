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
        guard let key = keychain.apiKey(for: .openAI) else { return [:] }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json",
        ]
    }

    var pricing: PricingMetadata {
        config.pricing
            ?? PricingMetadata(inputPer1KUSD: 0.005, outputPer1KUSD: 0.015, currency: "USD")
    }

    var isConfigured: Bool {
        keychain.apiKey(for: .openAI) != nil
    }

    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = keychain.apiKey(for: .openAI) else { return [] }
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

    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        try buildRequest(messages: messages, model: model, tools: nil, jsonMode: false)
    }

    func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) throws
        -> URLRequest
    {
        try buildRequest(messages: messages, model: model, tools: tools, jsonMode: false)
    }

    func buildRequest(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]?, jsonMode: Bool
    ) throws -> URLRequest {
        guard let apiKey = keychain.apiKey(for: .openAI) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = OpenAIManager(apiKey: apiKey)

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

        // Build request with tools
        return try manager.makeChatRequest(
            messages: openAIMessages,
            model: model,
            stream: false,
            tools: openAITools,
            responseFormat: jsonMode ? OpenAIResponseFormat(type: "json_object") : nil
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
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
                        // Enable stream options for usage in final chunk
                        json["stream_options"] = ["include_usage": true]
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    // 2. Execute
                    let (result, response) = try await URLSession.shared.bytes(for: streamRequest)

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
                    // Track tool calls being accumulated (streaming tool calls come in chunks)
                    var toolCallsInProgress: [Int: (id: String, name: String, arguments: String)] =
                        [:]

                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }

                            if let data = jsonStr.data(using: .utf8),
                                let chunk = try? JSONDecoder().decode(
                                    OpenAIStreamChunk.self, from: data)
                            {

                                if let choice = chunk.choices.first {
                                    // Handle text content
                                    if let content = choice.delta.content {
                                        fullText += content
                                        continuation.yield(.token(text: content))
                                    }

                                    // Handle tool calls (streamed in chunks)
                                    if let toolCalls = choice.delta.toolCalls {
                                        for tc in toolCalls {
                                            let idx = tc.index

                                            // Initialize new tool call
                                            if let id = tc.id {
                                                toolCallsInProgress[idx] = (
                                                    id: id, name: tc.function?.name ?? "",
                                                    arguments: ""
                                                )
                                            }

                                            // Accumulate function name
                                            if let name = tc.function?.name, !name.isEmpty {
                                                if var existing = toolCallsInProgress[idx] {
                                                    existing.name += name
                                                    toolCallsInProgress[idx] = existing
                                                }
                                            }

                                            // Accumulate arguments
                                            if let args = tc.function?.arguments, !args.isEmpty {
                                                if var existing = toolCallsInProgress[idx] {
                                                    existing.arguments += args
                                                    toolCallsInProgress[idx] = existing
                                                }
                                            }
                                        }
                                    }

                                    // Check for finish_reason to emit completed tool calls
                                    if choice.finishReason == "tool_calls" {
                                        for (_, toolCall) in toolCallsInProgress.sorted(by: {
                                            $0.key < $1.key
                                        }) {
                                            continuation.yield(
                                                .toolUse(
                                                    id: toolCall.id,
                                                    name: toolCall.name,
                                                    input: toolCall.arguments
                                                ))
                                        }
                                    }
                                }

                                // Usage in final chunk (sometimes provided by OpenAI)
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
                    }

                    // Final completion
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

                    // Add tool calls to message if any
                    if !toolCallsInProgress.isEmpty {
                        message.toolCalls = toolCallsInProgress.values.map { tc in
                            ToolCall(id: tc.id, name: tc.name, input: tc.arguments)
                        }
                    }

                    continuation.yield(.completion(message: message))
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
