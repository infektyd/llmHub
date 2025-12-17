import Foundation
import OSLog

@MainActor
struct OpenAIProvider: LLMProvider {
    nonisolated let id: String = "openai"
    nonisolated let name: String = "OpenAI"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.OpenAI
    private nonisolated let logger = Logger(subsystem: "com.llmhub", category: "OpenAIProvider")

    var supportsToolCalling: Bool { true }

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
        try await buildRequest(messages: messages, model: model, tools: nil, options: .default)
    }

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        try await buildRequest(messages: messages, model: model, tools: tools, options: options, jsonMode: false)
    }

    private func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions,
        jsonMode: Bool
    ) async throws -> URLRequest {
        guard let apiKey = await keychain.apiKey(for: .openAI) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = OpenAIManager(apiKey: apiKey)
        let endpoint = ModelRouter.endpoint(for: model)
        let requestThinking = shouldRequestThinking(model: model, preference: options.thinkingPreference)
        let isResponsesAPI = (endpoint == .responses)

        // Map messages
        let openAIMessages = messages.map { msg -> OpenAIChatMessage in
            // Handle tool role messages - Responses API requires "user" role instead of "tool"
            if msg.role == .tool {
                let mappedRole: String
                if isResponsesAPI {
                    // Responses API (gpt-5*, o1*, etc.) requires tool results as "user" role
                    mappedRole = "user"
                    logger.debug("OpenAIProvider: Mapped tool result message to 'user' role for Responses API (model: \(model))")
                } else {
                    // Chat Completions API uses "tool" role
                    mappedRole = "tool"
                }
                return OpenAIChatMessage(
                    role: mappedRole,
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
                jsonMode: jsonMode,
                reasoningSummary: requestThinking ? "auto" : nil
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

    private func shouldRequestThinking(model: String, preference: ThinkingPreference) -> Bool {
        switch preference {
        case .off:
            return false
        case .on:
            return true
        case .auto:
            let lower = model.lowercased()
            // Best-effort heuristic: OpenAI reasoning families commonly use the Responses API.
            return ModelRouter.endpoint(for: lower) == .responses
        }
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            Task {
                do {
                    // Streaming Responses endpoint
                    if request.url?.path.contains("/responses") == true {
                        var streamRequest = request
                        if let bodyData = request.httpBody,
                            var json = try? JSONSerialization.jsonObject(with: bodyData)
                                as? [String: Any]
                        {
                            json["stream"] = true
                            streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                        }
                        streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                        let (bytes, response) = try await LLMURLSession.shared.bytes(for: streamRequest)
                        guard let http = response as? HTTPURLResponse,
                            (200...299).contains(http.statusCode)
                        else {
                            var errorText = ""
                            for try await line in bytes.lines { errorText += line }
                            continuation.yield(
                                .error(
                                    .server(
                                        reason: errorText.isEmpty ? "Unknown stream error" : errorText))
                            )
                            continuation.finish()
                            return
                        }

                        func parseJSONDict(_ payload: String) -> [String: Any]? {
                            guard let data = payload.data(using: .utf8) else { return nil }
                            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                        }

                        func firstString(_ dict: [String: Any], keys: [String]) -> String? {
                            for key in keys {
                                if let s = dict[key] as? String, !s.isEmpty { return s }
                            }
                            return nil
                        }

                        func firstInt(_ dict: [String: Any], keys: [String]) -> Int? {
                            for key in keys {
                                if let i = dict[key] as? Int { return i }
                                if let s = dict[key] as? String, let i = Int(s) { return i }
                            }
                            return nil
                        }

                        func isValidJSONObjectString(_ s: String) -> Bool {
                            guard let data = s.data(using: .utf8) else { return false }
                            return (try? JSONSerialization.jsonObject(with: data)) != nil
                        }

                        var fullText = ""
                        var thinkingSummary = ""

                        // Tool call assembly (best-effort; Responses schema varies by event type).
                        struct PartialCall {
                            var id: String
                            var name: String?
                            var arguments: String
                        }
                        var partialCallsByID: [String: PartialCall] = [:]
                        var emittedToolCallIDs: Set<String> = []
                        var finalizedToolCalls: [ToolCall] = []

                        func upsertToolCall(id: String, name: String?, argsDelta: String?) {
                            var existing = partialCallsByID[id] ?? PartialCall(id: id, name: nil, arguments: "")
                            if let name, !name.isEmpty { existing.name = name }
                            if let argsDelta { existing.arguments += argsDelta }
                            partialCallsByID[id] = existing
                        }

                        func finalizeToolCallIfReady(id: String) {
                            guard var call = partialCallsByID[id] else { return }
                            guard let name = call.name, !name.isEmpty else { return }
                            guard !emittedToolCallIDs.contains(id) else { return }
                            guard isValidJSONObjectString(call.arguments) else { return }
                            emittedToolCallIDs.insert(id)
                            let tc = ToolCall(id: id, name: name, input: call.arguments)
                            finalizedToolCalls.append(tc)
                            continuation.yield(.toolUse(id: id, name: name, input: call.arguments))
                            call.name = name
                            partialCallsByID[id] = call
                        }

                        var sse = SSEEventFrameParser()
                        for try await byte in bytes {
                            for frame in sse.append(byte: byte) {
                                if frame.data == "[DONE]" { break }

                                let eventName = frame.event
                                let dict = parseJSONDict(frame.data)
                                let typeName = (dict?["type"] as? String) ?? eventName ?? ""

                                switch typeName {
                                case "response.output_text.delta":
                                    if let delta = dict.flatMap({ firstString($0, keys: ["delta", "text"]) }) {
                                        if !delta.isEmpty {
                                            fullText += delta
                                            continuation.yield(.token(text: delta))
                                        }
                                    }

                                case "response.reasoning_summary_text.delta":
                                    if let delta = dict.flatMap({ firstString($0, keys: ["delta", "text"]) }) {
                                        if !delta.isEmpty {
                                            thinkingSummary += delta
                                            continuation.yield(.thinking(delta))
                                        }
                                    }

                                case "response.function_call_arguments.delta":
                                    guard let dict else { break }
                                    let callID =
                                        firstString(dict, keys: ["call_id", "item_id", "id"])
                                        ?? "call_0"
                                    let name = firstString(dict, keys: ["name", "function_name"])
                                    let delta = firstString(dict, keys: ["delta", "arguments_delta", "arguments"])
                                    upsertToolCall(id: callID, name: name, argsDelta: delta)

                                case "response.output_item.added", "response.output_item.done":
                                    guard let dict, let item = dict["item"] as? [String: Any] else { break }
                                    let itemType = (item["type"] as? String) ?? ""
                                    guard itemType == "function_call" else { break }

                                    let callID =
                                        firstString(item, keys: ["call_id", "id", "item_id"])
                                        ?? "call_0"
                                    let name = firstString(item, keys: ["name", "function_name"])
                                    let args = firstString(item, keys: ["arguments", "input"])
                                    upsertToolCall(id: callID, name: name, argsDelta: args)
                                    if typeName == "response.output_item.done" {
                                        finalizeToolCallIfReady(id: callID)
                                    }

                                case "response.completed":
                                    // Usage may arrive here (best-effort).
                                    if let dict {
                                        let usageDict =
                                            (dict["usage"] as? [String: Any])
                                            ?? ((dict["response"] as? [String: Any])?["usage"] as? [String: Any])
                                        if let usageDict {
                                            let inputTokens = firstInt(usageDict, keys: ["input_tokens", "prompt_tokens"]) ?? 0
                                            let outputTokens = firstInt(usageDict, keys: ["output_tokens", "completion_tokens"]) ?? 0
                                            let cachedTokens = firstInt(usageDict, keys: ["cached_tokens"]) ?? 0
                                            continuation.yield(.usage(TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens, cachedTokens: cachedTokens)))
                                        }
                                    }
                                    // Attempt to finalize any fully-formed tool calls.
                                    for id in partialCallsByID.keys {
                                        finalizeToolCallIfReady(id: id)
                                    }

                                default:
                                    break
                                }
                            }
                        }

                        let message = ChatMessage(
                            id: UUID(),
                            role: .assistant,
                            content: fullText,
                            thoughtProcess: thinkingSummary.nilIfEmpty,
                            parts: fullText.isEmpty ? [] : [.text(fullText)],
                            createdAt: Date(),
                            codeBlocks: [],
                            tokenUsage: nil,
                            costBreakdown: nil,
                            toolCallID: nil,
                            toolCalls: finalizedToolCalls.isEmpty ? nil : finalizedToolCalls
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
                        print("OpenAIProvider: Helper stream request config applied (stream=true)")
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
                    var toolAssembler = PartialToolCallAssembler()
                    var finalizedToolCalls: [ToolCall] = []
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
                                toolAssembler.ingest(
                                    index: tc.index,
                                    id: tc.id,
                                    name: tc.function?.name,
                                    argumentsDelta: tc.function?.arguments
                                )
                            }
                        }

                        // Track the finish reason
                        if let finishReason = choice.finishReason {
                            lastFinishReason = finishReason
                        }

                        if choice.finishReason == "tool_calls" {
                            let calls = toolAssembler.finalizeAll()
                            finalizedToolCalls.append(contentsOf: calls)
                            for tc in calls {
                                continuation.yield(.toolUse(id: tc.id, name: tc.name, input: tc.input))
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

                    if !finalizedToolCalls.isEmpty {
                        message.toolCalls = finalizedToolCalls
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
