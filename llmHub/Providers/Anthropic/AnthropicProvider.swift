import Foundation

@MainActor
struct AnthropicProvider: LLMProvider {

    nonisolated let id: String = "anthropic"
    nonisolated let name: String = "Anthropic (Claude)"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.Anthropic

    init(keychain: KeychainStore, config: ProvidersConfig.Anthropic) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        if let url = config.baseURL { return url }
        return URL(string: "https://api.anthropic.com/v1")!
    }

    var supportsStreaming: Bool { true }

    var supportsToolCalling: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    var isConfigured: Bool {
        get async {
            await keychain.apiKey(for: .anthropic) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {

        // Anthropic does not provide a public /models endpoint; using static config list

        return config.models

    }

    var defaultHeaders: [String: String] {
        get async {
            [:]  // Handled by Manager
        }
    }

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        LLMTrace.requestStarted(
            provider: "Anthropic",
            model: model,
            messageCount: messages.count,
            toolCount: tools?.count ?? 0
        )

        guard let key = await keychain.apiKey(for: .anthropic) else {
            LLMTrace.authStatus(provider: "Anthropic", hasKey: false)
            throw LLMProviderError.authenticationMissing
        }
        LLMTrace.authStatus(provider: "Anthropic", hasKey: true)

        let manager = AnthropicManager(apiKey: key)

        // Extract system messages into Anthropic's dedicated `system` field.
        //
        // Rationale: Anthropic's API uses a separate system prompt field rather than treating
        // system as a normal message role. If we drop system messages, we lose tool manifest
        // and rolling-summary compaction context.
        let systemPrompt: String? = {
            let systemChunks = messages
                .filter { $0.role == .system }
                .map { $0.content }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if systemChunks.isEmpty { return nil }
            return systemChunks.joined(separator: "\n\n")
        }()

        // Map non-system messages
        var anthropicMessages: [AnthropicMessage] = []
        var messageIndex = 0
        while messageIndex < messages.count {
            let msg = messages[messageIndex]

            // Skip system messages (handled separately in Anthropic API)
            if msg.role == .system {
                messageIndex += 1
                continue
            }

            // Handle tool result messages
            if msg.role == .tool {
                var toolBlocks: [AnthropicContentBlock] = []
                var toolIndex = messageIndex
                while toolIndex < messages.count, messages[toolIndex].role == .tool {
                    let toolMsg = messages[toolIndex]
                    toolBlocks.append(
                        .toolResult(
                            AnthropicToolResult(
                                tool_use_id: toolMsg.toolCallID ?? "",
                                content: toolMsg.content
                            ))
                    )
                    toolIndex += 1
                }

                anthropicMessages.append(AnthropicMessage(role: "user", content: toolBlocks))
                messageIndex = toolIndex
                continue
            }

            var blocks: [AnthropicContentBlock] = []

            // Handle assistant messages with tool use
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                if !msg.content.isEmpty {
                    blocks.append(.text(AnthropicTextBlock(text: msg.content)))
                }
                for tc in toolCalls {
                    // Parse input JSON to dictionary
                    let inputDict =
                        (try? JSONSerialization.jsonObject(
                            with: tc.input.data(using: .utf8) ?? Data()
                        ) as? [String: Any]) ?? [:]
                    blocks.append(
                        .toolUse(AnthropicToolUse(id: tc.id, name: tc.name, input: inputDict)))
                }
                anthropicMessages.append(AnthropicMessage(role: "assistant", content: blocks))
                messageIndex += 1
                continue
            }

            if !msg.content.isEmpty {
                blocks.append(.text(AnthropicTextBlock(text: msg.content)))
            }

            for part in msg.parts {
                switch part {
                case .text(let t):
                    if t != msg.content { blocks.append(.text(AnthropicTextBlock(text: t))) }
                case .image(let data, let mime):
                    blocks.append(
                        .image(
                            AnthropicImageSource(media_type: mime, data: data.base64EncodedString())
                        ))
                case .imageURL:
                    // Anthropic doesn't support image URLs directly
                    break
                }
            }

            if blocks.isEmpty {
                blocks.append(.text(AnthropicTextBlock(text: msg.content)))
            }

            anthropicMessages.append(
                AnthropicMessage(role: msg.role == .user ? "user" : "assistant", content: blocks)
            )
            messageIndex += 1
        }

        // Convert tool definitions to Anthropic format
        let anthropicTools: [AnthropicTool]? = tools?.map { toolDef in
            AnthropicTool(
                name: toolDef.name, description: toolDef.description,
                inputSchema: toolDef.inputSchema)
        }

        // Validate and sanitize tool pairing to prevent orphaned tool_results
        let sanitizedMessages = sanitizeToolResults(
            messages: sanitizeToolUseOrdering(messages: anthropicMessages)
        )
        validateToolPairing(messages: sanitizedMessages)

        let maxTokens = min(availableModels.first?.maxOutputTokens ?? 4096, 64_000)

        return try manager.makeChatRequest(
            messages: sanitizedMessages,
            model: model,
            maxTokens: maxTokens,
            stream: false,
            system: systemPrompt,
            tools: anthropicTools
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            let task = Task {
                do {
                    // 1. Modify for stream
                    var streamRequest = request
                    if let bodyData = request.httpBody,
                        var json = try? JSONSerialization.jsonObject(with: bodyData)
                            as? [String: Any] {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    // Debug: Log request
                    if let bodyData = streamRequest.httpBody,
                        let bodyStr = String(data: bodyData, encoding: .utf8) {
                        LLMTrace.requestDetails(
                            provider: "Anthropic",
                            url: streamRequest.url?.absoluteString ?? "unknown",
                            bodyPreview: bodyStr
                        )
                    }

                    LLMTrace.requestSent(provider: "Anthropic")

                    let (bytes, response) = try await LLMURLSession.bytes(for: streamRequest)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.yield(.error(.server(reason: "No HTTP response")))
                        continuation.finish()
                        return
                    }

                    // Handle non-success status
                    if !(200...299).contains(http.statusCode) {
                        LLMTrace.responseReceived(
                            provider: "Anthropic", statusCode: http.statusCode)
                        var errorText = ""
                        for try await line in bytes.lines { errorText += line }
                        LLMTrace.errorWithBody(
                            provider: "Anthropic", statusCode: http.statusCode, body: errorText)
                        continuation.yield(
                            .error(.server(reason: "HTTP \(http.statusCode): \(errorText)")))
                        continuation.finish()
                        return
                    }

                    let decoder = JSONDecoder()
                    var aggregated = ""
                    var toolCalls: [ToolCall] = []
                    var currentToolUse: (id: String, name: String, input: String)?

                    // Parse SSE line-by-line (Anthropic format: "event: ...\ndata: {...}\n\n")
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Skip event lines and empty lines
                        guard trimmed.hasPrefix("data: ") else { continue }

                        let jsonStr = String(trimmed.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        guard let data = jsonStr.data(using: .utf8) else { continue }

                        if let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) {
                            switch event.type {
                            case "content_block_start":
                                // Check if this is a tool_use block
                                if let contentBlock = event.content_block,
                                    contentBlock.type == "tool_use" {
                                    currentToolUse = (
                                        id: contentBlock.id ?? "",
                                        name: contentBlock.name ?? "",
                                        input: ""
                                    )
                                }

                            case "content_block_delta":
                                if let text = event.delta?.text {
                                    aggregated += text
                                    continuation.yield(.token(text: text))
                                }
                                // Handle thinking blocks
                                if let thinking = event.delta?.thinking {
                                    continuation.yield(.thinking(thinking))
                                }
                                // Handle tool input delta (partial_json)
                                if let partialJson = event.delta?.partial_json {
                                    if var tu = currentToolUse {
                                        tu.input += partialJson
                                        currentToolUse = tu
                                    }
                                }

                            case "content_block_stop":
                                // If we were building a tool use, finalize it
                                if let tu = currentToolUse {
                                    let toolCall = ToolCall(
                                        id: tu.id, name: tu.name, input: tu.input)
                                    toolCalls.append(toolCall)
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
                                var message = ChatMessage(
                                    id: UUID(),
                                    role: .assistant,
                                    content: aggregated,
                                    parts: [],
                                    createdAt: Date(),
                                    codeBlocks: [],
                                    tokenUsage: nil,
                                    costBreakdown: nil
                                )
                                if !toolCalls.isEmpty {
                                    message.toolCalls = toolCalls
                                }
                                continuation.yield(.completion(message: message))

                            default:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    if error is CancellationError {
                        continuation.finish()
                        return
                    }
                    LLMTrace.error(provider: "Anthropic", message: "Stream error: \(error)")
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
        if let decoded = try? JSONDecoder().decode(AnthropicMessageResponse.self, from: response) {
            return TokenUsage(
                inputTokens: decoded.usage.input_tokens,
                outputTokens: decoded.usage.output_tokens,
                cachedTokens: 0
            )
        }
        return nil
    }

    // MARK: - Tool Result Validation & Sanitization

    /// Validates that all tool_result blocks have corresponding tool_use blocks.
    /// Logs diagnostic information to help identify orphaned tool_results.
    private func validateToolPairing(messages: [AnthropicMessage]) {
        print("\n🔍 [ToolValidation] ========== VALIDATING CONVERSATION ==========")

        var toolUseRegistry: [String: Int] = [:]  // ID → message index
        var orphanedResults: [(id: String, messageIndex: Int)] = []

        for (index, message) in messages.enumerated() {
            print("\n🔍 [Message \(index)] Role: \(message.role)")

            for (contentIndex, content) in message.content.enumerated() {
                switch content {
                case .toolUse(let toolUse):
                    toolUseRegistry[toolUse.id] = index
                    print("  [\(contentIndex)] ✅ Registered tool_use: \(toolUse.id)")

                case .toolResult(let toolResult):
                    if toolUseRegistry[toolResult.tool_use_id] != nil {
                        print("  [\(contentIndex)] ✅ Valid tool_result for: \(toolResult.tool_use_id)")
                    } else {
                        print("  [\(contentIndex)] ❌ ORPHANED tool_result for: \(toolResult.tool_use_id)")
                        orphanedResults.append((id: toolResult.tool_use_id, messageIndex: index))
                    }

                case .text(let textBlock):
                    print("  [\(contentIndex)] Type: text (\(textBlock.text.prefix(50))...)")

                case .image:
                    print("  [\(contentIndex)] Type: image")
                }
            }
        }

        if orphanedResults.isEmpty {
            print("\n✅ [ToolValidation] All tool_result blocks have matching tool_use blocks")
        } else {
            print("\n❌ [ToolValidation] FOUND \(orphanedResults.count) ORPHANED TOOL RESULTS:")
            for orphan in orphanedResults {
                print("  - tool_use_id: \(orphan.id) in message[\(orphan.messageIndex)]")
            }
            print("⚠️ [ToolValidation] This will cause HTTP 400 from Anthropic!")
        }

        print("🔍 [ToolValidation] =============================================\n")
    }

    /// Removes orphaned tool_result blocks from conversation history.
    /// A tool_result is orphaned if its tool_use_id doesn't match any tool_use block in the conversation.
    private func sanitizeToolResults(messages: [AnthropicMessage]) -> [AnthropicMessage] {
        var toolUseIds = Set<String>()
        var sanitizedMessages: [AnthropicMessage] = []

        // First pass: collect all tool_use IDs
        for message in messages {
            if message.role == "assistant" {
                for content in message.content {
                    if case .toolUse(let toolUse) = content {
                        toolUseIds.insert(toolUse.id)
                    }
                }
            }
        }

        // Second pass: filter out orphaned tool_results
        for message in messages {
            var cleanedMessage = message

            if message.role == "user" {
                let filteredContents = message.content.filter { content in
                    guard case .toolResult(let toolResult) = content else {
                        return true  // Keep non-tool_result content
                    }

                    let isValid = toolUseIds.contains(toolResult.tool_use_id)
                    if !isValid {
                        print("⚠️ [Sanitize] Removing orphaned tool_result: \(toolResult.tool_use_id)")
                    }
                    return isValid
                }

                cleanedMessage = AnthropicMessage(role: message.role, content: filteredContents)

                // Skip message entirely if it's now empty
                if filteredContents.isEmpty {
                    print("⚠️ [Sanitize] Skipping empty message after filtering")
                    continue
                }
            }

            sanitizedMessages.append(cleanedMessage)
        }

        return sanitizedMessages
    }

    private func sanitizeToolUseOrdering(messages: [AnthropicMessage]) -> [AnthropicMessage] {
        var sanitized: [AnthropicMessage] = []
        var index = 0

        while index < messages.count {
            let message = messages[index]

            guard message.role == "assistant" else {
                sanitized.append(message)
                index += 1
                continue
            }

            let toolUseIds: [String] = message.content.compactMap { block in
                guard case .toolUse(let toolUse) = block else { return nil }
                return toolUse.id
            }

            guard !toolUseIds.isEmpty else {
                sanitized.append(message)
                index += 1
                continue
            }

            let nextMessage: AnthropicMessage? = (index + 1) < messages.count ? messages[index + 1] : nil
            let nextToolResultIds: Set<String> = {
                guard let nextMessage, nextMessage.role == "user" else { return [] }
                return Set(
                    nextMessage.content.compactMap { block in
                        guard case .toolResult(let toolResult) = block else { return nil }
                        return toolResult.tool_use_id
                    }
                )
            }()

            if Set(toolUseIds).isSubset(of: nextToolResultIds) {
                sanitized.append(message)
                if let nextMessage {
                    sanitized.append(nextMessage)
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            let cleanedAssistantBlocks = message.content.filter { block in
                guard case .toolUse = block else { return true }
                return false
            }

            if !cleanedAssistantBlocks.isEmpty {
                sanitized.append(AnthropicMessage(role: message.role, content: cleanedAssistantBlocks))
            }

            if let nextMessage, nextMessage.role == "user" {
                let cleanedUserBlocks = nextMessage.content.filter { block in
                    guard case .toolResult = block else { return true }
                    return false
                }
                if !cleanedUserBlocks.isEmpty {
                    sanitized.append(AnthropicMessage(role: nextMessage.role, content: cleanedUserBlocks))
                }
                index += 2
            } else {
                index += 1
            }
        }

        return sanitized
    }
}
