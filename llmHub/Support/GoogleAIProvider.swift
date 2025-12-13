import Foundation

@MainActor
struct GoogleAIProvider: LLMProvider {
    nonisolated let id: String = "google"
    nonisolated let name: String = "Google AI (Gemini)"

    private let keychain: KeychainStore
    private let config: ProvidersConfig.GoogleAI

    init(keychain: KeychainStore, config: ProvidersConfig.GoogleAI) {
        self.keychain = keychain
        self.config = config
    }

    var endpoint: URL {
        if let url = config.baseURL { return url }
        return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    var supportsStreaming: Bool { true }

    var availableModels: [LLMModel] { config.models }

    var defaultHeaders: [String: String] { 
        get async {
            ["Content-Type": "application/json"] 
        }
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }

    var isConfigured: Bool {
        get async {
            await keychain.apiKey(for: .google) != nil
        }
    }

    func fetchModels() async throws -> [LLMModel] {

        guard let apiKey = await keychain.apiKey(for: .google) else {
            throw LLMProviderError.authenticationMissing
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)"

        guard let url = URL(string: urlString) else { throw LLMProviderError.invalidRequest }

        var request = URLRequest(url: url)

        request.httpMethod = "GET"

        let (data, response) = try await LLMURLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {

            throw LLMProviderError.server(reason: "Failed to fetch models")

        }

        struct GoogleModelsResponse: Decodable {

            let models: [GoogleModel]

            struct GoogleModel: Decodable {

                let name: String

                let displayName: String?

                let inputTokenLimit: Int?

                let outputTokenLimit: Int?

            }

        }

        let decoded = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)

        return decoded.models.map { model in

            LLMModel(

                id: model.name.replacingOccurrences(of: "models/", with: ""),

                displayName: model.displayName ?? model.name,

                contextWindow: model.inputTokenLimit ?? 128000,

                supportsToolUse: true,

                maxOutputTokens: model.outputTokenLimit ?? 8192

            )

        }

    }

    func buildRequest(messages: [ChatMessage], model: String) async throws -> URLRequest {
        try await buildRequest(messages: messages, model: model, jsonMode: false)
    }

    func buildRequest(messages: [ChatMessage], model: String, jsonMode: Bool) async throws -> URLRequest {
        guard let apiKey = await keychain.apiKey(for: .google) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = GeminiManager(apiKey: apiKey)

        var prompt = ""
        var history: [Content] = []

        // Filter out empty messages just in case
        let validMessages = messages.filter { !$0.content.isEmpty }

        if let last = validMessages.last {
            prompt = last.content

            if validMessages.count > 1 {
                let historyMessages = validMessages.dropLast()
                history = historyMessages.map { msg in
                    let role: String
                    switch msg.role {
                    case .user, .system: role = "user"  // Gemini 1.5 usually treats system prompts via config or user role
                    case .assistant: role = "model"
                    case .tool: role = "user"  // tool responses feed as user content
                    }
                    return Content(role: role, parts: [.text(msg.content)])
                }
            }
        }

        // Note: For now we default to no media files and thinking level off.
        // These could be exposed via options if LLMProvider protocol supported them.

        // Extract media from parts
        var mediaFiles: [MediaFile] = []

        // Only the LAST user message usually carries new attachments in a typical chat flow,
        // but if history has images, Gemini expects them inline in the history.
        // We'll map all history.

        if let last = validMessages.last {
            prompt = last.content  // Text content

            // Add attachments from last message
            for part in last.parts {
                if case .image(let data, let mime) = part {
                    mediaFiles.append(MediaFile(data: data, mimeType: mime))
                }
            }

            if validMessages.count > 1 {
                let historyMessages = validMessages.dropLast()
                history = historyMessages.map { msg in
                    let role: String
                    switch msg.role {
                    case .user, .system: role = "user"
                    case .assistant: role = "model"
                    case .tool: role = "user"
                    }

                    var parts: [Part] = []
                    // Text
                    if !msg.content.isEmpty {
                        parts.append(.text(msg.content))
                    }
                    // Images
                    for part in msg.parts {
                        if case .image(let data, let mime) = part {
                            let base64 = data.base64EncodedString()
                            parts.append(.inlineData(InlineData(mimeType: mime, data: base64)))
                        }
                    }

                    // Fallback if empty (shouldn't happen with filter)
                    if parts.isEmpty { parts.append(.text("...")) }

                    return Content(role: role, parts: parts)
                }
            }
        }

        // We build a non-streaming request by default.
        // streamResponse will convert it to a streaming request if needed.
        return try manager.makeGenerateContentRequest(
            prompt: prompt,
            files: mediaFiles,  // Only new files attached to the current prompt
            model: model,
            history: history,
            stream: false
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            Task {
                do {
                    // Convert to streaming request
                    var streamRequest = request
                    if let url = request.url, url.absoluteString.contains(":generateContent") {
                        let newString =
                            url.absoluteString
                            .replacingOccurrences(
                                of: ":generateContent", with: ":streamGenerateContent")
                            + "&alt=sse"
                        streamRequest.url = URL(string: newString)
                    }

                    let (result, response) = try await LLMURLSession.shared.bytes(for: streamRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    else {
                        // Attempt to read error
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        continuation.yield(
                            .error(
                                .server(
                                    reason: errorText.isEmpty
                                        ? "Unknown streaming error" : errorText)))
                        continuation.finish()
                        return
                    }

	                    var fullText = ""
	                    var accumulatedToolCalls: [ToolCall] = []

	                    for try await line in result.lines {
	                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

	                        if trimmed.hasPrefix("data: ") {
	                            let json = String(trimmed.dropFirst(6))
	                            if json == "[DONE]" { break }

	                            if let data = json.data(using: .utf8),
	                                let chunk = try? JSONDecoder().decode(
	                                    GenerationResponse.self, from: data)
	                            {
	                                if let text = chunk.text, !text.isEmpty {
	                                    fullText += text
	                                    continuation.yield(.token(text: text))
	                                }
	                                
	                                // Handle Function Calls even when text is nil/empty.
	                                if let candidates = chunk.candidates, let first = candidates.first {
	                                    for part in first.content.parts {
	                                        if case .functionCall(let fc) = part {
	                                            let encoder = JSONEncoder()
	                                            if let argsData = try? encoder.encode(fc.args),
	                                               let argsStr = String(data: argsData, encoding: .utf8) {
	                                                let callId = "call_\(UUID().uuidString.prefix(8))"
	                                                let toolCall = ToolCall(id: callId, name: fc.name, input: argsStr)
	                                                accumulatedToolCalls.append(toolCall)
	                                                continuation.yield(.toolUse(id: callId, name: fc.name, input: argsStr))
	                                            }
	                                        }
	                                    }
	                                }
	                            } else {
	#if DEBUG
	                                if !json.isEmpty {
	                                    print("GoogleAIProvider: Failed to decode stream chunk: \(json.prefix(200))")
	                                }
	#endif
	                            }
	                        }
	                    }

	                    // Final completion event with full message
	                    let message = ChatMessage(
	                        id: UUID(),
	                        role: .assistant,
	                        content: fullText,
	                        parts: fullText.isEmpty ? [] : [.text(fullText)],
	                        createdAt: Date(),
	                        codeBlocks: [],
	                        tokenUsage: nil,
	                        costBreakdown: nil,
	                        toolCallID: nil,
	                        toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
	                    )
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
        return nil
    }
}
