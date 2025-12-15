import Foundation
import OSLog

@MainActor
struct AnthropicProvider: LLMProvider {
    private let logger = Logger(subsystem: "com.llmhub", category: "AnthropicProvider")
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
        guard let key = await keychain.apiKey(for: .anthropic) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = AnthropicManager(apiKey: key)

        // Map messages
        let anthropicMessages: [AnthropicMessage] = messages.compactMap { msg in
            // Skip system messages (handled separately in Anthropic API)
            if msg.role == .system { return nil }

            // Handle tool result messages
            if msg.role == .tool {
                return AnthropicMessage(
                    role: "user",
                    content: [
                        .toolResult(
                            AnthropicToolResult(
                                tool_use_id: msg.toolCallID ?? "",
                                content: msg.content
                            ))
                    ]
                )
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
                return AnthropicMessage(role: "assistant", content: blocks)
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

            return AnthropicMessage(role: msg.role == .user ? "user" : "assistant", content: blocks)
        }

        // Convert tool definitions to Anthropic format
        let anthropicTools: [AnthropicTool]? = tools?.map { toolDef in
            AnthropicTool(
                name: toolDef.name, description: toolDef.description,
                inputSchema: toolDef.inputSchema)
        }

        let maxTokens = min(availableModels.first?.maxOutputTokens ?? 4096, 64_000)

        return try manager.makeChatRequest(
            messages: anthropicMessages,
            model: model,
            maxTokens: maxTokens,
            stream: false,
            tools: anthropicTools
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            Task {
                do {
                    // 1. Modify for stream
                    var streamRequest = request
                    if let bodyData = request.httpBody,
                        var json = try? JSONSerialization.jsonObject(with: bodyData)
                            as? [String: Any]
                    {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    // Debug: Log request
                    if let bodyData = streamRequest.httpBody,
                        let bodyStr = String(data: bodyData, encoding: .utf8)
                    {
                        Logger(subsystem: "com.llmhub", category: "AnthropicProvider").debug(
                            "Anthropic Request: \(bodyStr)")
                    }

                    let (bytes, response) = try await LLMURLSession.shared.bytes(for: streamRequest)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.yield(.error(.server(reason: "No HTTP response")))
                        continuation.finish()
                        return
                    }

                    // Handle non-success status
                    if !(200...299).contains(http.statusCode) {
                        var errorText = ""
                        for try await line in bytes.lines { errorText += line }
                        Logger(subsystem: "com.llmhub", category: "AnthropicProvider").error(
                            "Anthropic Error (\(http.statusCode)): \(errorText)")
                        continuation.yield(
                            .error(.server(reason: "HTTP \(http.statusCode): \(errorText)")))
                        continuation.finish()
                        return
                    }

                    let decoder = JSONDecoder()
                    var aggregated = ""
                    var toolCalls: [ToolCall] = []
                    var currentToolUse: (id: String, name: String, input: String)? = nil

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
                                    contentBlock.type == "tool_use"
                                {
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
                    Logger(subsystem: "com.llmhub", category: "AnthropicProvider").error(
                        "Stream error: \(error)")
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
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
}
