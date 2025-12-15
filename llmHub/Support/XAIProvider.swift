import Foundation
import OSLog

@MainActor
struct XAIProvider: LLMProvider {
    private let logger = Logger(subsystem: "com.llmhub", category: "XAIProvider")
    nonisolated let id: String = "xai"
    nonisolated let name: String = "xAI (Grok)"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.XAI

    init(keychain: KeychainStore, config: ProvidersConfig.XAI) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        if let url = config.baseURL { return url }
        return URL(string: "https://api.x.ai/v1")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String: String] {
        get async {
            guard let key = await keychain.apiKey(for: .xai) else { return [:] }
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
            await keychain.apiKey(for: .xai) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {

        // xAI does not provide a public /models endpoint; using static config list

        return config.models

    }

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        guard let apiKey = await keychain.apiKey(for: .xai) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = XAIManager(apiKey: apiKey)

        // Map messages
        let xaiMessages = messages.map { msg -> XAIChatMessage in
            // Check for parts
            if !msg.parts.isEmpty {
                var xaiParts: [XAIChatMessage.Part] = []

                // Add text if present
                if !msg.content.isEmpty {
                    xaiParts.append(.text(msg.content))
                }

                for part in msg.parts {
                    switch part {
                    case .text(let t):
                        // If content is already populated, this might be dup, but let's trust parts if present
                        if t != msg.content { xaiParts.append(.text(t)) }
                    case .image(let data, _):
                        // XAI supports base64 images
                        xaiParts.append(.image(base64: data.base64EncodedString()))
                    case .imageURL:
                        // Not directly supported in XAIChatMessage helper yet, but schema supports it.
                        // For now, ignore or fetch? Assuming data based.
                        break
                    }
                }

                if xaiParts.isEmpty {
                    return XAIChatMessage(role: msg.role.rawValue, content: msg.content)
                }

                return XAIChatMessage(role: msg.role.rawValue, parts: xaiParts)
            } else {
                // Legacy / Text only
                return XAIChatMessage(role: msg.role.rawValue, content: msg.content)
            }
        }

        // Default to non-streaming
        return try manager.makeChatRequest(
            messages: xaiMessages,
            model: model,
            stream: false
        )
    }

	    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
	        AsyncThrowingStream(ProviderEvent.self) { continuation in
	            Task {
	                do {
	                    // 1. Modify request to enable streaming
	                    var streamRequest = request
                    if let bodyData = request.httpBody,
                        var json = try? JSONSerialization.jsonObject(with: bodyData)
                            as? [String: Any]
                    {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }

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
                    var thoughtProcess = ""
                    var toolAssembler = PartialToolCallAssembler()
                    var finalizedToolCalls: [ToolCall] = []
                    var emittedReferences: Set<String> = []
                    var lastFinishReason: String? = nil

                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }

                            guard let data = jsonStr.data(using: .utf8),
                                let chunk = try? JSONDecoder().decode(
                                    XAIChatStreamChunk.self, from: data),
                                let choice = chunk.choices.first
                            else { continue }

                            if let reasoning = choice.delta.reasoning_content, !reasoning.isEmpty {
                                thoughtProcess += reasoning
                                continuation.yield(.thinking(reasoning))
                            }

                            if let content = choice.delta.content, !content.isEmpty {
                                fullText += content
                                continuation.yield(.token(text: content))
                            }

                            if let citations = chunk.citations, !citations.isEmpty {
                                for citation in citations where !citation.isEmpty {
                                    if emittedReferences.insert(citation).inserted {
                                        continuation.yield(.reference(citation))
                                    }
                                }
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
                                    continuation.yield(.toolUse(id: tc.id, name: tc.name, input: tc.input))
                                }
                            }
                        }
                    }

                    // Final completion
                    var message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        thoughtProcess: thoughtProcess.isEmpty ? nil : thoughtProcess,
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
