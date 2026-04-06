import Foundation
import OSLog

/// Provider for the local OpenClaw gateway.
/// Routes chat requests to localhost:18789 (OpenAI-compatible /v1 endpoint).
@MainActor
struct OpenClawProvider: LLMProvider {

    nonisolated let id: String = "openclaw"
    nonisolated let name: String = "OpenClaw (Local)"

    private let config: ProvidersConfig.OpenClaw
    private let manager: OpenClawManager

    #if DEBUG
        private static let logger = Logger(subsystem: "com.llmhub", category: "OpenClawProvider")
    #endif

    init(config: ProvidersConfig.OpenClaw) {
        self.config = config
        let url = config.baseURL ?? URL(string: "http://localhost:18789/v1")!
        self.manager = OpenClawManager(baseURL: url)
    }

    var endpoint: URL {
        config.baseURL ?? URL(string: "http://localhost:18789/v1")!
    }

    var supportsStreaming: Bool { true }
    var supportsToolCalling: Bool { true }
    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String: String] {
        get async {
            [
                "Authorization": "Bearer 3d0f30ebdb793f1d86523ea3f2ecc52615435a3874810790",
                "Content-Type": "application/json",
            ]
        }
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    var isConfigured: Bool { get async { true } }

    func fetchModels() async throws -> [LLMModel] {
        let gatewayModels = try await manager.listModels()
        return gatewayModels.map { m in
            LLMModel(
                id: m.id,
                name: m.name ?? m.id,
                maxOutputTokens: 65536,
                contextWindow: 1_000_000,
                supportsToolUse: true
            )
        }
    }

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        // Gateway requires "openclaw" or "openclaw/<agentId>" as model ID.
        // Priority 1: Use the model parameter if it already specifies a specific agent.
        // This is set by handleGroupChat when routing to individual agents.
        let knownAgents = ["syntra", "forge", "recon", "pulse", "council"]

        var targetModel: String
        if knownAgents.contains(model) {
            // Model parameter already specifies the target agent — use it directly.
            targetModel = "openclaw/\(model)"
        } else if model.hasPrefix("openclaw/") {
            // Model already has the openclaw/ prefix — use as-is.
            targetModel = model
        } else {
            // Fallback: extract from @mention in message text for single-agent routing.
            targetModel = "openclaw"
            if let lastUserMessage = messages.last(where: { $0.role == .user }) {
                let content = lastUserMessage.content.lowercased()
                if let mentionRange = content.range(of: "@[a-z0-9-]+", options: .regularExpression) {
                    let agentName = String(content[mentionRange].dropFirst())
                    if knownAgents.contains(agentName) {
                        targetModel = "openclaw/\(agentName)"
                    }
                }
            }
        }

        LLMTrace.requestStarted(
            provider: "OpenClaw",
            model: targetModel,
            messageCount: messages.count,
            toolCount: tools?.count ?? 0
        )

        // MARK: - Message Sequence Validation
        // Log role sequence for debugging (no content exposed)
        MessageSequenceValidator.logRoleSequence(provider: "OpenClaw", messages: messages)

        // Sanitize message sequence - fail-open, drops invalid messages
        let validationResult = MessageSequenceValidator.sanitize(
            messages: messages, provider: "OpenClaw")
        let sanitizedMessages = validationResult.sanitizedMessages

        if validationResult.didMutate {
            LLMTrace.sequenceValidation(
                provider: "OpenClaw",
                originalCount: messages.count,
                sanitizedCount: sanitizedMessages.count,
                droppedRoles: validationResult.droppedRoles
            )
            #if DEBUG
                Self.logger.debug(
                    "🔧 [OpenClaw] Mutation metrics: user=\(validationResult.droppedUserCount) assistant=\(validationResult.droppedAssistantCount) tool=\(validationResult.droppedToolCount) system=\(validationResult.droppedSystemCount)"
                )
                for (reason, count) in validationResult.droppedByReason.sorted(by: {
                    $0.key < $1.key
                }) {
                    Self.logger.debug(
                        "🔧 [OpenClaw] Drop reason '\(reason)': \(count) message(s)")
                }
                Self.logger.debug(
                    "🔧 [OpenClaw] Pre-sequence: \(validationResult.preRoleSequence.joined(separator: " → "))"
                )
                Self.logger.debug(
                    "🔧 [OpenClaw] Post-sequence: \(validationResult.postRoleSequence.joined(separator: " → "))"
                )
            #endif
        }

        #if DEBUG
            LLMTrace.sendDiagnostics(
                provider: "OpenClaw",
                model: model,
                messageCountPreSanitize: messages.count,
                messageCountPostSanitize: sanitizedMessages.count,
                sanitizerDidMutate: validationResult.didMutate,
                sanitizerDroppedRoles: validationResult.droppedRoles,
                messagesForMetrics: sanitizedMessages,
                tools: tools
            )
        #endif

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
                    let size =
                        (try? FileManager.default.attributesOfItem(atPath: attachment.url.path)[
                            .size]) as? NSNumber
                    return subtotal + (size?.intValue ?? 0)
                }
        }

        LLMTrace.requestInstrumentation(
            provider: "OpenClaw",
            messageCount: sanitizedMessages.count,
            toolCount: toolCount,
            manifestInjected: toolCount > 0,
            manifestSizeChars: manifestSizeChars,
            manifestSizeTokensEstimate: manifestSizeTokens,
            attachmentCount: attachmentCount,
            attachmentTotalBytes: attachmentTotalBytes,
            totalTokenEstimate: totalTokenEstimate
        )

        let ocMessages = sanitizedMessages.map { msg -> XAIChatMessage in
            // Handle tool role messages
            if msg.role == .tool {
                return XAIChatMessage(
                    role: "tool",
                    content: msg.content,
                    toolCallId: msg.toolCallID
                )
            }

            // Handle assistant messages with tool calls
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                let xaiToolCalls = toolCalls.map { tc in
                    XAIToolCall(
                        id: tc.id,
                        type: "function",
                        function: XAIToolCall.FunctionCall(name: tc.name, arguments: tc.input)
                    )
                }
                return XAIChatMessage(
                    role: "assistant",
                    content: msg.content,
                    toolCalls: xaiToolCalls
                )
            }

            if !msg.parts.isEmpty {
                var parts: [XAIChatMessage.Part] = []
                if !msg.content.isEmpty { parts.append(.text(msg.content)) }
                for part in msg.parts {
                    switch part {
                    case .text(let t):
                        if t != msg.content { parts.append(.text(t)) }
                    case .image(let data, _):
                        parts.append(.image(base64: data.base64EncodedString()))
                    case .imageURL:
                        break
                    }
                }
                if parts.isEmpty {
                    return XAIChatMessage(role: msg.role.rawValue, content: msg.content)
                }
                return XAIChatMessage(role: msg.role.rawValue, parts: parts)
            } else {
                return XAIChatMessage(role: msg.role.rawValue, content: msg.content)
            }
        }

        let ocTools: [XAITool]? = tools?.map { toolDef in
            let params: [String: AnyEncodable] = toolDef.inputSchema.mapValues {
                AnyEncodable(OpenAIJSONValue.from($0))
            }
            return XAITool(
                type: "function",
                function: XAIFunction(
                    name: toolDef.name,
                    description: toolDef.description,
                    parameters: params
                )
            )
        }

        return try manager.makeChatRequest(
            messages: ocMessages,
            model: targetModel,
            stream: false,
            tools: ocTools
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            let task = Task {
                do {
                    var streamRequest = request
                    if let bodyData = request.httpBody,
                        var json = try? JSONSerialization.jsonObject(with: bodyData)
                            as? [String: Any]
                    {
                        json["stream"] = true
                        json["stream_options"] = ["include_usage": true]
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }

                    if let bodyData = streamRequest.httpBody,
                        let bodyStr = String(data: bodyData, encoding: .utf8)
                    {
                        LLMTrace.requestDetails(
                            provider: "OpenClaw",
                            url: streamRequest.url?.absoluteString ?? "unknown",
                            bodyPreview: bodyStr)
                    }
                    LLMTrace.requestSent(provider: "OpenClaw")

                    let (result, response) = try await LLMURLSession.bytes(for: streamRequest)

                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        LLMTrace.responseReceived(provider: "OpenClaw", statusCode: statusCode)

                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        LLMTrace.errorWithBody(
                            provider: "OpenClaw", statusCode: statusCode, body: errorText)

                        continuation.yield(
                            .error(
                                .server(
                                    reason: errorText.isEmpty
                                        ? "Gateway error (HTTP \(statusCode))" : errorText))
                        )
                        continuation.finish()
                        return
                    }

                    LLMTrace.responseReceived(provider: "OpenClaw", statusCode: http.statusCode)

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
                                XAIChatStreamChunk.self, from: data),
                            let choice = chunk.choices.first
                        else { continue }

                        if let content = choice.delta.content {
                            fullText += content
                            continuation.yield(.token(text: content))
                        }

                        if let toolCalls = choice.delta.tool_calls {
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
                        if let finishReason = choice.finish_reason {
                            lastFinishReason = finishReason
                        }

                        if choice.finish_reason == "tool_calls" {
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
                                        inputTokens: usage.prompt_tokens,
                                        outputTokens: usage.completion_tokens,
                                        cachedTokens: 0
                                    )))
                        }
                    }

                    let message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        parts: [],
                        createdAt: Date(),
                        codeBlocks: [],
                        tokenUsage: nil,
                        costBreakdown: nil,
                        toolCallID: nil,
                        toolCalls: finalizedToolCalls.isEmpty ? nil : finalizedToolCalls
                    )

                    // Check if response was truncated due to max_tokens
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
                    LLMTrace.error(provider: "OpenClaw", message: "Stream error: \(error)")
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
        let decoded = try? JSONDecoder().decode(XAIChatResponse.self, from: response)
        if let usage = decoded?.usage {
            return TokenUsage(
                inputTokens: usage.prompt_tokens,
                outputTokens: usage.completion_tokens,
                cachedTokens: 0
            )
        }
        return nil
    }
}
