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

    var supportsToolCalling: Bool { true }

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

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        LLMTrace.requestStarted(
            provider: "Mistral",
            model: model,
            messageCount: messages.count,
            toolCount: tools?.count ?? 0
        )

        guard let apiKey = await keychain.apiKey(for: .mistral) else {
            LLMTrace.authStatus(provider: "Mistral", hasKey: false)
            throw LLMProviderError.authenticationMissing
        }
        LLMTrace.authStatus(provider: "Mistral", hasKey: true)

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

        let mistralTools: [MistralTool]? = tools?.map { toolDef in
            MistralTool(
                type: "function",
                function: MistralFunction(
                    name: toolDef.name,
                    description: toolDef.description,
                    parameters: toolDef.inputSchema.mapValues(OpenAIJSONValue.from)
                )
            )
        }

        let shouldUseReasoningMode: Bool = {
            switch options.thinkingPreference {
            case .off:
                return false
            case .on:
                return model.lowercased().contains("magistral")
            case .auto:
                return model.lowercased().contains("magistral")
            }
        }()

        // Default to non-streaming request builder
        return try manager.makeChatRequest(
            messages: mistralMessages,
            model: model,
            stream: false,
            tools: mistralTools,
            parallelToolCalls: (mistralTools?.isEmpty == false) ? true : nil,
            promptMode: shouldUseReasoningMode ? "reasoning" : nil
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

                    if let bodyData = streamRequest.httpBody,
                        let bodyStr = String(data: bodyData, encoding: .utf8)
                    {
                        LLMTrace.requestDetails(
                            provider: "Mistral",
                            url: streamRequest.url?.absoluteString ?? "unknown",
                            bodyPreview: bodyStr)
                    }
                    LLMTrace.requestSent(provider: "Mistral")

                    // 2. Execute
                    let (result, response) = try await LLMURLSession.bytes(
                        for: streamRequest)

                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        LLMTrace.responseReceived(provider: "Mistral", statusCode: statusCode)
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        LLMTrace.errorWithBody(
                            provider: "Mistral", statusCode: statusCode, body: errorText)
                        continuation.yield(
                            .error(
                                .server(
                                    reason: errorText.isEmpty ? "Unknown stream error" : errorText))
                        )
                        continuation.finish()
                        return
                    }

                    var fullText = ""
                    var thoughtProcess = ""
                    var thinkExtractor = ThinkTagStreamExtractor()
                    var toolAssembler = PartialToolCallAssembler()
                    var finalizedToolCalls: [ToolCall] = []
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

                            if let content = choice.delta.content, !content.isEmpty {
                                let extracted = thinkExtractor.process(delta: content)
                                if !extracted.thinking.isEmpty {
                                    thoughtProcess += extracted.thinking
                                    continuation.yield(.thinking(extracted.thinking))
                                }
                                if !extracted.visible.isEmpty {
                                    fullText += extracted.visible
                                    continuation.yield(.token(text: extracted.visible))
                                }
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

                    let flushed = thinkExtractor.flush()
                    if !flushed.thinking.isEmpty {
                        thoughtProcess += flushed.thinking
                        continuation.yield(.thinking(flushed.thinking))
                    }
                    if !flushed.visible.isEmpty {
                        fullText += flushed.visible
                        continuation.yield(.token(text: flushed.visible))
                    }

                    // Final completion
                    var message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        thoughtProcess: thoughtProcess.isEmpty ? nil : thoughtProcess,
                        parts: [],  // Initialize with empty parts
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
                    LLMTrace.error(provider: "Mistral", message: "Stream error: \(error)")
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
