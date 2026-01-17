import Foundation

@MainActor
struct OpenAIProvider: LLMProvider {
    nonisolated let id: String = "openai"
    nonisolated let name: String = "OpenAI"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.OpenAI

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
            guard let key = await keychain.apiKey(for: .openai) else { return [:] }
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
            await keychain.apiKey(for: .openai) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = await keychain.apiKey(for: .openai) else { return [] }
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
        try await buildRequest(
            messages: messages, model: model, tools: tools, options: options, jsonMode: false)
    }

    private func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions,
        jsonMode: Bool
    ) async throws -> URLRequest {
        guard let apiKey = await keychain.apiKey(for: .openai) else {
            LLMTrace.authStatus(provider: "OpenAI", hasKey: false)
            throw LLMProviderError.authenticationMissing
        }
        LLMTrace.authStatus(provider: "OpenAI", hasKey: true)

        LLMTrace.requestStarted(
            provider: "OpenAI",
            model: model,
            messageCount: messages.count,
            toolCount: tools?.count ?? 0
        )

        // MARK: - Message Sequence Validation
        // Log role sequence for debugging (no content exposed)
        MessageSequenceValidator.logRoleSequence(provider: "OpenAI", messages: messages)

        // Sanitize message sequence - fail-open, drops invalid messages
        let validationResult = MessageSequenceValidator.sanitize(
            messages: messages, provider: "OpenAI")
        let sanitizedMessages = validationResult.sanitizedMessages

        if validationResult.wasModified {
            LLMTrace.sequenceValidation(
                provider: "OpenAI",
                originalCount: messages.count,
                sanitizedCount: sanitizedMessages.count,
                droppedRoles: validationResult.droppedRoles
            )
        }

        // MARK: - Request Instrumentation
        let toolCount = tools?.count ?? 0
        let manifestSizeChars = toolCount * 100  // Conservative estimate
        let manifestSizeTokens = manifestSizeChars / 4
        let totalTokenEstimate =
            TokenEstimator.estimate(messages: sanitizedMessages) + manifestSizeTokens

        let attachmentCount = sanitizedMessages.reduce(0) { $0 + $1.attachments.count }
        let attachmentTotalBytes = sanitizedMessages.reduce(0) { total, message in
            total
                + message.attachments.reduce(0) { subtotal, attachment in
                    let size = (try? FileManager.default.attributesOfItem(atPath: attachment.url.path)[.size]) as? NSNumber
                    return subtotal + (size?.intValue ?? 0)
                }
        }

        LLMTrace.requestInstrumentation(
            provider: "OpenAI",
            messageCount: sanitizedMessages.count,
            toolCount: toolCount,
            manifestInjected: toolCount > 0,
            manifestSizeChars: manifestSizeChars,
            manifestSizeTokensEstimate: manifestSizeTokens,
            attachmentCount: attachmentCount,
            attachmentTotalBytes: attachmentTotalBytes,
            totalTokenEstimate: totalTokenEstimate
        )

        let manager = OpenAIManager(apiKey: apiKey)
        let endpoint = ModelRouter.endpoint(for: model)
        let requestThinking = shouldRequestThinking(
            model: model, preference: options.thinkingPreference)
        let isResponsesAPI = (endpoint == .responses)

        // Map sanitized messages
        let openAIMessages = sanitizedMessages.map { msg -> OpenAIChatMessage in
            // Handle tool role messages - Responses API requires "user" role instead of "tool"
            if msg.role == .tool {
                let mappedRole: String
                if isResponsesAPI {
                    // Responses API (gpt-5*, o1*, etc.) requires tool results as "user" role
                    mappedRole = "user"

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
            let task = Task {
                do {
                    // Streaming Responses endpoint
                    if request.url?.path.contains("/responses") == true {
                        var streamRequest = request
                        if let bodyData = request.httpBody,
                            var json = try? JSONSerialization.jsonObject(with: bodyData)
                                as? [String: Any]
                        {
                            json["stream"] = true
                            streamRequest.httpBody = try JSONSerialization.data(
                                withJSONObject: json)
                        }
                        streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                        if let bodyData = streamRequest.httpBody,
                            let bodyStr = String(data: bodyData, encoding: .utf8)
                        {
                            LLMTrace.requestDetails(
                                provider: "OpenAI (Responses)",
                                url: streamRequest.url?.absoluteString ?? "unknown",
                                bodyPreview: bodyStr)
                        }
                        LLMTrace.requestSent(provider: "OpenAI (Responses)")

                        let (bytes, response) = try await LLMURLSession.bytes(
                            for: streamRequest)
                        guard let http = response as? HTTPURLResponse,
                            (200...299).contains(http.statusCode)
                        else {
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            LLMTrace.responseReceived(
                                provider: "OpenAI (Responses)", statusCode: statusCode)
                            var errorText = ""
                            for try await line in bytes.lines { errorText += line }
                            LLMTrace.errorWithBody(
                                provider: "OpenAI (Responses)", statusCode: statusCode,
                                body: errorText)
                            continuation.yield(
                                .error(
                                    .server(
                                        reason: errorText.isEmpty
                                            ? "Unknown stream error" : errorText))
                            )
                            continuation.finish()
                            return
                        }
                        LLMTrace.responseReceived(
                            provider: "OpenAI (Responses)", statusCode: http.statusCode)

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

                        func jsonString(from value: Any) -> String? {
                            if let s = value as? String { return s }
                            guard JSONSerialization.isValidJSONObject(value) else { return nil }
                            guard let data = try? JSONSerialization.data(withJSONObject: value)
                            else {
                                return nil
                            }
                            return String(data: data, encoding: .utf8)
                        }

                        func isValidJSONObjectString(_ s: String) -> Bool {
                            guard let data = s.data(using: .utf8) else { return false }
                            return (try? JSONSerialization.jsonObject(with: data)) != nil
                        }

                        var fullText = ""
                        var thinkingSummary = ""
                        var didYieldError = false

                        // Tool call assembly (best-effort; Responses schema varies by event type).
                        struct PartialCall {
                            var id: String
                            var name: String?
                            var arguments: String
                        }
                        var partialCallsByID: [String: PartialCall] = [:]
                        var emittedToolCallIDs: Set<String> = []
                        var finalizedToolCalls: [ToolCall] = []
                        var contentBlockIDByIndex: [Int: String] = [:]

                        func upsertToolCall(id: String, name: String?, argsDelta: String?) {
                            var existing =
                                partialCallsByID[id]
                                ?? PartialCall(id: id, name: nil, arguments: "")
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

                        func resolveToolCallID(from dict: [String: Any], fallbackIndex: Int?)
                            -> String
                        {
                            if let id = firstString(
                                dict, keys: ["id", "tool_call_id", "call_id", "item_id"])
                            {
                                return id
                            }
                            if let index = fallbackIndex, let mapped = contentBlockIDByIndex[index]
                            {
                                return mapped
                            }
                            if let index = fallbackIndex {
                                return "call_\(index)"
                            }
                            return "call_0"
                        }

                        var sse = SSEEventFrameParser()
                        for try await byte in bytes {
                            for frame in sse.append(byte: byte) {
                                if frame.data == "[DONE]" { break }

                                let eventName = frame.event
                                let dict = parseJSONDict(frame.data)
                                let typeName = (dict?["type"] as? String) ?? eventName ?? ""

                                switch typeName {
                                case "content_block_start":
                                    guard let dict,
                                        let block = dict["content_block"] as? [String: Any]
                                    else { break }
                                    let blockType = (block["type"] as? String) ?? ""
                                    let index = dict["index"] as? Int
                                    if blockType == "text" {
                                        if let text = firstString(
                                            block, keys: ["text", "content", "value"])
                                        {
                                            if !text.isEmpty {
                                                fullText += text
                                                continuation.yield(.token(text: text))
                                            }
                                        }
                                    } else if blockType == "tool_use" {
                                        let callID = resolveToolCallID(
                                            from: block, fallbackIndex: index)
                                        if let index { contentBlockIDByIndex[index] = callID }
                                        let name = firstString(
                                            block, keys: ["name", "tool_name", "function_name"])
                                        let input = block["input"].flatMap { jsonString(from: $0) }
                                        upsertToolCall(id: callID, name: name, argsDelta: input)
                                        finalizeToolCallIfReady(id: callID)
                                    }

                                case "content_block_delta":
                                    guard let dict else { break }
                                    let index = dict["index"] as? Int
                                    let delta = dict["delta"] as? [String: Any]
                                    let deltaType =
                                        delta.flatMap { firstString($0, keys: ["type"]) } ?? ""
                                    if deltaType == "text_delta" {
                                        if let text = delta.flatMap({
                                            firstString($0, keys: ["text", "delta", "value"])
                                        }) {
                                            if !text.isEmpty {
                                                fullText += text
                                                continuation.yield(.token(text: text))
                                            }
                                        }
                                    } else if deltaType == "input_json_delta" {
                                        let callID = resolveToolCallID(
                                            from: dict, fallbackIndex: index)
                                        let jsonDelta = delta.flatMap({
                                            firstString(
                                                $0, keys: ["partial_json", "delta", "arguments"])
                                        })
                                        upsertToolCall(id: callID, name: nil, argsDelta: jsonDelta)
                                        finalizeToolCallIfReady(id: callID)
                                    }

                                case "message_delta":
                                    if let dict,
                                        let usageDict = dict["usage"] as? [String: Any]
                                    {
                                        let inputTokens =
                                            firstInt(
                                                usageDict, keys: ["input_tokens", "prompt_tokens"])
                                            ?? 0
                                        let outputTokens =
                                            firstInt(
                                                usageDict,
                                                keys: ["output_tokens", "completion_tokens"]) ?? 0
                                        let cachedTokens =
                                            firstInt(usageDict, keys: ["cached_tokens"]) ?? 0
                                        continuation.yield(
                                            .usage(
                                                TokenUsage(
                                                    inputTokens: inputTokens,
                                                    outputTokens: outputTokens,
                                                    cachedTokens: cachedTokens)))
                                    }

                                case "message_stop":
                                    // Finalization event; remaining frames may still follow.
                                    break

                                case "error":
                                    if let dict,
                                        let errorDict = dict["error"] as? [String: Any]
                                    {
                                        let message =
                                            firstString(
                                                errorDict, keys: ["message", "error", "type"])
                                            ?? "Unknown error"
                                        continuation.yield(.error(.server(reason: message)))
                                        didYieldError = true
                                    }

                                case "response.output_text.delta":
                                    if let delta = dict.flatMap({
                                        firstString($0, keys: ["delta", "text"])
                                    }) {
                                        if !delta.isEmpty {
                                            fullText += delta
                                            continuation.yield(.token(text: delta))
                                        }
                                    }

                                case "response.reasoning_summary_text.delta":
                                    if let delta = dict.flatMap({
                                        firstString($0, keys: ["delta", "text"])
                                    }) {
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
                                    let delta = firstString(
                                        dict, keys: ["delta", "arguments_delta", "arguments"])
                                    upsertToolCall(id: callID, name: name, argsDelta: delta)

                                case "response.output_item.added", "response.output_item.done":
                                    guard let dict, let item = dict["item"] as? [String: Any] else {
                                        break
                                    }
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
                                            ?? ((dict["response"] as? [String: Any])?["usage"]
                                                as? [String: Any])
                                        if let usageDict {
                                            let inputTokens =
                                                firstInt(
                                                    usageDict,
                                                    keys: ["input_tokens", "prompt_tokens"]) ?? 0
                                            let outputTokens =
                                                firstInt(
                                                    usageDict,
                                                    keys: ["output_tokens", "completion_tokens"])
                                                ?? 0
                                            let cachedTokens =
                                                firstInt(usageDict, keys: ["cached_tokens"]) ?? 0
                                            continuation.yield(
                                                .usage(
                                                    TokenUsage(
                                                        inputTokens: inputTokens,
                                                        outputTokens: outputTokens,
                                                        cachedTokens: cachedTokens)))
                                        }
                                    }
                                    // Attempt to finalize any fully-formed tool calls.
                                    for id in partialCallsByID.keys {
                                        finalizeToolCallIfReady(id: id)
                                    }

                                default:
                                    break
                                }
                                if didYieldError { break }
                            }
                            if didYieldError { break }
                        }

                        if didYieldError {
                            continuation.finish()
                            return
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
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    if let bodyData = streamRequest.httpBody,
                        let bodyStr = String(data: bodyData, encoding: .utf8)
                    {
                        LLMTrace.requestDetails(
                            provider: "OpenAI", url: streamRequest.url?.absoluteString ?? "unknown",
                            bodyPreview: bodyStr)
                    }
                    LLMTrace.requestSent(provider: "OpenAI")

                    let (result, response) = try await LLMURLSession.bytes(
                        for: streamRequest)
                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        LLMTrace.responseReceived(provider: "OpenAI", statusCode: statusCode)
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        LLMTrace.errorWithBody(
                            provider: "OpenAI", statusCode: statusCode, body: errorText)
                        continuation.yield(
                            .error(
                                .server(
                                    reason: errorText.isEmpty ? "Unknown stream error" : errorText))
                        )
                        continuation.finish()
                        return
                    }
                    LLMTrace.responseReceived(provider: "OpenAI", statusCode: http.statusCode)

                    var fullText = ""
                    var toolAssembler = PartialToolCallAssembler()
                    var finalizedToolCalls: [ToolCall] = []
                    var lastFinishReason: String?

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

                    continuation.finish()

                } catch {
                    if error is CancellationError {
                        continuation.finish()
                        return
                    }
                    LLMTrace.error(provider: "OpenAI", message: "Stream error: \(error)")
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
