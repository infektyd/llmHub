import Foundation

@MainActor
struct OpenRouterProvider: LLMProvider {
    nonisolated let id: String = "openrouter"
    nonisolated let name: String = "OpenRouter"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.OpenRouter

    init(keychain: KeychainStore, config: ProvidersConfig.OpenRouter) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        if let url = config.baseURL { return url }
        return URL(string: "https://openrouter.ai/api/v1")!
    }

    var supportsStreaming: Bool { true }

    var supportsToolCalling: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String: String] {
        get async {
            guard let key = await keychain.apiKey(for: .openrouter) else { return [:] }
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
            await keychain.apiKey(for: .openrouter) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = await keychain.apiKey(for: .openrouter) else { return [] }
        let manager = OpenRouterManager(apiKey: apiKey)
        let models = try await manager.listModels()
        return models.map {
            LLMModel(
                id: $0.id,
                name: $0.name,
                maxOutputTokens: $0.context_length,
                contextWindow: $0.context_length
            )
        }
    }

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        LLMTrace.requestStarted(
            provider: "OpenRouter",
            model: model,
            messageCount: messages.count,
            toolCount: tools?.count ?? 0
        )

        guard let apiKey = await keychain.apiKey(for: .openrouter) else {
            LLMTrace.authStatus(provider: "OpenRouter", hasKey: false)
            throw LLMProviderError.authenticationMissing
        }
        LLMTrace.authStatus(provider: "OpenRouter", hasKey: true)

        let manager = OpenRouterManager(apiKey: apiKey)

        // Map messages
        let orMessages = messages.map { msg -> ORMessage in
            // Check for parts
            if !msg.parts.isEmpty {
                var parts: [ORContentPart] = []

                if !msg.content.isEmpty {
                    parts.append(.text(msg.content))
                }

                for part in msg.parts {
                    switch part {
                    case .text(let t):
                        if t != msg.content { parts.append(.text(t)) }
                    case .image(let data, _):
                        parts.append(.image(base64: data.base64EncodedString()))
                    case .imageURL(let url):
                        parts.append(.image(url: url.absoluteString))
                    }
                }

                if parts.isEmpty {
                    return ORMessage(role: msg.role.rawValue, content: .text(msg.content))
                }
                return ORMessage(role: msg.role.rawValue, content: .parts(parts))
            } else {
                return ORMessage(role: msg.role.rawValue, content: .text(msg.content))
            }
        }

        let orTools: [ORTool]? = tools?.map { toolDef in
            ORTool(
                type: "function",
                function: ORFunction(
                    name: toolDef.name,
                    description: toolDef.description,
                    parameters: toolDef.inputSchema.mapValues(OpenAIJSONValue.from)
                )
            )
        }

        // Default to non-streaming request builder
        return try manager.makeChatRequest(
            messages: orMessages,
            model: model,
            stream: false,
            tools: orTools,
            parallelToolCalls: (orTools?.isEmpty == false) ? true : nil
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            let task = Task {
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

                    if let bodyData = streamRequest.httpBody,
                        let bodyStr = String(data: bodyData, encoding: .utf8)
                    {
                        LLMTrace.requestDetails(
                            provider: "OpenRouter",
                            url: streamRequest.url?.absoluteString ?? "unknown",
                            bodyPreview: bodyStr)
                    }
                    LLMTrace.requestSent(provider: "OpenRouter")

                    // 2. Execute
                    let (result, response) = try await LLMURLSession.bytes(
                        for: streamRequest)

                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        LLMTrace.responseReceived(provider: "OpenRouter", statusCode: statusCode)
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        LLMTrace.errorWithBody(
                            provider: "OpenRouter", statusCode: statusCode, body: errorText)
                        continuation.yield(
                            .error(
                                .server(
                                    reason: errorText.isEmpty ? "Unknown stream error" : errorText))
                        )
                        continuation.finish()
                        return
                    }

                    // Determine stream format from model prefix and provider hints.
                    let modelID: String = {
                        guard let body = request.httpBody,
                            let json = try? JSONSerialization.jsonObject(with: body)
                                as? [String: Any]
                        else { return "" }
                        return (json["model"] as? String) ?? ""
                    }()

                    let headerProviderHint =
                        (http.value(forHTTPHeaderField: "x-model-provider")
                        ?? http.value(forHTTPHeaderField: "X-Model-Provider"))?
                        .lowercased()

                    enum StreamFormat {
                        case openAIStyle
                        case anthropicStyle
                        case geminiStyle
                        case unknown
                    }

                    let streamFormat: StreamFormat = {
                        let lower = modelID.lowercased()
                        if lower.hasPrefix("anthropic/") { return .anthropicStyle }
                        if lower.hasPrefix("google/") { return .geminiStyle }
                        if lower.hasPrefix("openai/") { return .openAIStyle }
                        if let hint = headerProviderHint {
                            if hint.contains("anthropic") { return .anthropicStyle }
                            if hint.contains("google") || hint.contains("gemini") {
                                return .geminiStyle
                            }
                            if hint.contains("openai") { return .openAIStyle }
                        }
                        return modelID.isEmpty ? .unknown : .openAIStyle
                    }()

                    var fullText = ""
                    var toolAssembler = PartialToolCallAssembler()
                    var finalizedToolCalls: [ToolCall] = []
                    var lastFinishReason: String? = nil

                    switch streamFormat {
                    case .geminiStyle:
                        // Gemini-style SSE can emit multi-line `data:` payloads; use buffered framing.
                        var sse = SSEEventParser()
                        let decoder = JSONDecoder()

                        for try await byte in result {
                            for payload in sse.append(byte: byte) {
                                if payload == "[DONE]" { break }
                                guard let data = payload.data(using: .utf8) else { continue }
                                guard
                                    let chunk = try? decoder.decode(
                                        GenerationResponse.self, from: data)
                                else {
                                    continue
                                }

                                if let text = chunk.text, !text.isEmpty {
                                    fullText += text
                                    continuation.yield(.token(text: text))
                                }

                                if let usage = chunk.usageMetadata {
                                    continuation.yield(
                                        .usage(
                                            TokenUsage(
                                                inputTokens: usage.promptTokenCount ?? 0,
                                                outputTokens: usage.candidatesTokenCount ?? 0,
                                                cachedTokens: 0
                                            )))
                                }
                            }
                        }

                    case .anthropicStyle:
                        // Anthropic-style SSE events proxied through OpenRouter.
                        let decoder = JSONDecoder()
                        var toolCalls: [ToolCall] = []
                        var currentToolUse: (id: String, name: String, input: String)? = nil

                        for try await line in result.lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard trimmed.hasPrefix("data: ") else { continue }

                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }
                            guard let data = jsonStr.data(using: .utf8) else { continue }

                            guard
                                let event = try? decoder.decode(
                                    AnthropicStreamEvent.self, from: data)
                            else {
                                continue
                            }

                            switch event.type {
                            case "content_block_start":
                                if let contentBlock = event.content_block,
                                    contentBlock.type == "tool_use"
                                {
                                    currentToolUse = (
                                        id: contentBlock.id ?? "",
                                        name: contentBlock.name ?? "",
                                        input: ""
                                    )
                                }

                            case "content_block_delta":
                                if let text = event.delta?.text, !text.isEmpty {
                                    fullText += text
                                    continuation.yield(.token(text: text))
                                }
                                if let thinking = event.delta?.thinking, !thinking.isEmpty {
                                    continuation.yield(.thinking(thinking))
                                }
                                if let partialJson = event.delta?.partial_json, !partialJson.isEmpty
                                {
                                    if var tu = currentToolUse {
                                        tu.input += partialJson
                                        currentToolUse = tu
                                    }
                                }

                            case "content_block_stop":
                                if let tu = currentToolUse, !tu.id.isEmpty, !tu.name.isEmpty {
                                    let call = ToolCall(id: tu.id, name: tu.name, input: tu.input)
                                    toolCalls.append(call)
                                    continuation.yield(
                                        .toolUse(id: tu.id, name: tu.name, input: tu.input))
                                    currentToolUse = nil
                                }

                            case "message_delta":
                                if let usage = event.usage {
                                    continuation.yield(
                                        .usage(
                                            TokenUsage(
                                                inputTokens: usage.input_tokens,
                                                outputTokens: usage.output_tokens,
                                                cachedTokens: 0
                                            )))
                                }

                            case "message_stop":
                                break

                            default:
                                break
                            }
                        }

                        finalizedToolCalls = toolCalls

                    case .openAIStyle, .unknown:
                        // OpenAI-style SSE chunks (OpenRouter default), with fallback to Anthropic event decoding.
                        let decoder = JSONDecoder()
                        var toolCalls: [ToolCall] = []
                        var currentToolUse: (id: String, name: String, input: String)? = nil

                        for try await line in result.lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard trimmed.hasPrefix("data: ") else { continue }
                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }
                            guard let data = jsonStr.data(using: .utf8) else { continue }

                            if let chunk = try? decoder.decode(ORStreamChunk.self, from: data),
                                let choice = chunk.choices.first
                            {
                                if let content = choice.delta.content, !content.isEmpty {
                                    fullText += content
                                    continuation.yield(.token(text: content))
                                }

                                if let toolCallsDelta = choice.delta.toolCalls {
                                    for tc in toolCallsDelta {
                                        toolAssembler.ingest(
                                            index: tc.index,
                                            id: tc.id,
                                            name: tc.function?.name,
                                            argumentsDelta: tc.function?.arguments
                                        )
                                    }
                                }

                                if let finishReason = choice.finishReason {
                                    lastFinishReason = finishReason
                                }

                                if choice.finishReason == "tool_calls" {
                                    let calls = toolAssembler.finalizeAll()
                                    finalizedToolCalls.append(contentsOf: calls)
                                    for tc in calls {
                                        continuation.yield(
                                            .toolUse(id: tc.id, name: tc.name, input: tc.input))
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

                                continue
                            }

                            // Fallback: try to decode Anthropic events if OpenRouter emits them.
                            if let event = try? decoder.decode(
                                AnthropicStreamEvent.self, from: data)
                            {
                                switch event.type {
                                case "content_block_start":
                                    if let contentBlock = event.content_block,
                                        contentBlock.type == "tool_use"
                                    {
                                        currentToolUse = (
                                            id: contentBlock.id ?? "",
                                            name: contentBlock.name ?? "",
                                            input: ""
                                        )
                                    }

                                case "content_block_delta":
                                    if let text = event.delta?.text, !text.isEmpty {
                                        fullText += text
                                        continuation.yield(.token(text: text))
                                    }
                                    if let thinking = event.delta?.thinking, !thinking.isEmpty {
                                        continuation.yield(.thinking(thinking))
                                    }
                                    if let partialJson = event.delta?.partial_json,
                                        !partialJson.isEmpty
                                    {
                                        if var tu = currentToolUse {
                                            tu.input += partialJson
                                            currentToolUse = tu
                                        }
                                    }

                                case "content_block_stop":
                                    if let tu = currentToolUse, !tu.id.isEmpty, !tu.name.isEmpty {
                                        let call = ToolCall(
                                            id: tu.id, name: tu.name, input: tu.input)
                                        toolCalls.append(call)
                                        continuation.yield(
                                            .toolUse(id: tu.id, name: tu.name, input: tu.input))
                                        currentToolUse = nil
                                    }

                                case "message_delta":
                                    if let usage = event.usage {
                                        continuation.yield(
                                            .usage(
                                                TokenUsage(
                                                    inputTokens: usage.input_tokens,
                                                    outputTokens: usage.output_tokens,
                                                    cachedTokens: 0
                                                )))
                                    }

                                default:
                                    break
                                }
                            }
                        }

                        if !toolCalls.isEmpty {
                            finalizedToolCalls.append(contentsOf: toolCalls)
                        }
                    }

                    var message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        parts: [],  // Initialize with empty parts
                        createdAt: Date(),
                        codeBlocks: [],
                        tokenUsage: nil,
                        costBreakdown: nil
                    )
                    if !finalizedToolCalls.isEmpty {
                        message.toolCalls = finalizedToolCalls
                    }

                    if lastFinishReason == "length" {
                        continuation.yield(.truncated(message: message))
                    } else {
                        continuation.yield(.completion(message: message))
                    }
                    continuation.finish()

                } catch {
                    if error is CancellationError {
                        continuation.finish()
                        return
                    }
                    LLMTrace.error(provider: "OpenRouter", message: "Stream error: \(error)")
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func parseTokenUsage(from response: Data) throws -> TokenUsage? {
        let decoded = try? JSONDecoder().decode(ORChatResponse.self, from: response)
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
