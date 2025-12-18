import Foundation
import OSLog

@MainActor
struct GoogleAIProvider: LLMProvider {
    private let logger = AppLogger.category("GoogleAIProvider")
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

    var supportsToolCalling: Bool { true }

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
        try await buildRequest(messages: messages, model: model, tools: nil, options: .default)
    }

    func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        options: LLMRequestOptions
    ) async throws -> URLRequest {
        guard let apiKey = await keychain.apiKey(for: .google) else {
            throw LLMProviderError.authenticationMissing
        }

        let manager = GeminiManager(apiKey: apiKey, baseURL: endpoint)

        // Build a mapping from toolCallID -> tool name for functionResponse parts.
        var toolNameByCallID: [String: String] = [:]
        for message in messages {
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    toolNameByCallID[toolCall.id] = toolCall.name
                }
            }
        }

        var prompt = ""
        var history: [Content] = []

        // Keep assistant tool-call messages even when textual content is empty.
        let validMessages = messages.filter { msg in
            if !msg.content.isEmpty { return true }
            if !(msg.toolCalls ?? []).isEmpty { return true }
            if !msg.parts.isEmpty { return true }
            return false
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
                history = Self.buildHistoryContents(
                    historyMessages: historyMessages,
                    toolNameByCallID: toolNameByCallID
                )
            }
        }

        // We build a non-streaming request by default.
        // streamResponse will convert it to a streaming request if needed.
        let maxOutputTokens = config.models.first(where: { $0.id == model })?.maxOutputTokens
        return try manager.makeGenerateContentRequest(
            prompt: prompt,
            files: mediaFiles,  // Only new files attached to the current prompt
            model: model,
            options: options,
            history: history,
            tools: tools,
            maxOutputTokens: maxOutputTokens,
            stream: false
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream(ProviderEvent.self) { continuation in
            let baseRequest = request
            let logger = self.logger
            Task.detached {
                do {
                    // Convert to streaming request
                    var streamRequest = baseRequest
                    if let url = baseRequest.url, url.absoluteString.contains(":generateContent") {
                        var newString =
                            url.absoluteString
                            .replacingOccurrences(
                                of: ":generateContent", with: ":streamGenerateContent")
                        if !newString.contains("alt=sse") {
                            newString += (newString.contains("?") ? "&" : "?") + "alt=sse"
                        }
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
                    var stopDueToMalformedFunctionCall = false
                    var chunkCount = 0
                    var lastFinishReason: String? = nil
                    var lastCandidateCount = 0
                    var lastPartCounts: [Int] = []
                    var didReceiveDone = false

                    // Rationale: Gemini SSE can emit multi-line data events and JSON may be split across TCP frames.
                    // Buffer until a full SSE event is available before decoding.
                    var sse = SSEEventParser()
                    let decoder = JSONDecoder()

                    for try await byte in result {
                        for payload in sse.append(byte: byte) {
                            if payload == "[DONE]" {
                                didReceiveDone = true
                                break
                            }

                            guard let data = payload.data(using: .utf8) else { continue }
                            let chunk: GenerationResponse
                            do {
                                chunk = try decoder.decode(GenerationResponse.self, from: data)
                            } catch {
                                logger.debug(
                                    "Failed to decode Gemini stream event: \(payload.prefix(240), privacy: .public)"
                                )
                                continue
                            }

                            chunkCount += 1
                            lastCandidateCount = chunk.candidateCount
                            lastPartCounts = chunk.partCountsByCandidate
                            if let finishReason = chunk.candidates?.first?.finishReason {
                                lastFinishReason = finishReason
                            }

                            if chunk.candidates?.first?.finishReason == "MALFORMED_FUNCTION_CALL" {
                                // Rationale: Treat as model output error; surface a readable warning and skip tool execution.
                                stopDueToMalformedFunctionCall = true
                                accumulatedToolCalls.removeAll()

                                let warning =
                                    "\n[Gemini warning] Model produced a malformed function call; tool execution was skipped for this turn.\n"
                                fullText += warning
                                continuation.yield(.token(text: warning))
                                break
                            }

                            let deltaText = chunk.assembledText(candidateIndex: 0)
                            if !deltaText.isEmpty {
                                fullText += deltaText
                                continuation.yield(.token(text: deltaText))
                            }

                            // Handle Function Calls even when text is nil/empty.
                            if !stopDueToMalformedFunctionCall,
                                let candidates = chunk.candidates,
                                let first = candidates.first
                            {
                                for part in first.content.parts {
                                    if let fc = part.functionCall {
                                        let encoder = JSONEncoder()
                                        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                                        let argsObject = fc.args ?? [:]
                                        let argsData = (try? encoder.encode(argsObject)) ?? Data("{}".utf8)
                                        if let argsStr = String(data: argsData, encoding: .utf8) {
                                            let callId = "call_\(UUID().uuidString.prefix(8))"
                                            let toolCall = ToolCall(
                                                id: callId,
                                                name: fc.name,
                                                input: argsStr,
                                                geminiThoughtSignature: part.thoughtSignature
                                            )
                                            accumulatedToolCalls.append(toolCall)
                                            continuation.yield(
                                                .toolUse(id: callId, name: fc.name, input: argsStr))
                                        }
                                    }
                                }
                            }
                        }

                        if didReceiveDone || stopDueToMalformedFunctionCall { break }
                    }

                    let partCountsStr = lastPartCounts.map(String.init).joined(separator: ",")
                    logger.info(
                        "Gemini stream finished finishReason=\(lastFinishReason ?? "nil", privacy: .public) chunks=\(chunkCount) candidates=\(lastCandidateCount) partCounts=[\(partCountsStr, privacy: .public)] assembledLength=\(fullText.count)"
                    )

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

                    if lastFinishReason == "MAX_TOKENS" {
                        logger.warning(
                            "Gemini response truncated by provider MAX_TOKENS assembledLength=\(fullText.count)"
                        )
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
        return nil
    }
}

extension GoogleAIProvider {
    nonisolated static func buildHistoryContents(
        historyMessages: ArraySlice<ChatMessage>,
        toolNameByCallID: [String: String]
    ) -> [Content] {
        historyMessages.map { msg in
            let role: String
            switch msg.role {
            case .user, .system: role = "user"
            case .assistant: role = "model"
            case .tool: role = "user"
            }

            var parts: [Part] = []

            if msg.role != .tool, !msg.content.isEmpty {
                parts.append(.text(msg.content))
            }

            if msg.role == .assistant, let toolCalls = msg.toolCalls {
                for toolCall in toolCalls {
                    let args: [String: GeminiJSONValue]
                    if let data = toolCall.input.data(using: .utf8),
                        let decoded = try? JSONDecoder().decode([String: GeminiJSONValue].self, from: data)
                    {
                        args = decoded
                    } else {
                        args = [:]
                    }

                    let fc = FunctionCall(name: toolCall.name, args: args.isEmpty ? nil : args)
                    parts.append(.functionCall(fc, thoughtSignature: toolCall.geminiThoughtSignature))
                }
            }

            if msg.role == .tool,
                let toolCallID = msg.toolCallID,
                let toolName = toolNameByCallID[toolCallID]
            {
                let response: [String: GeminiJSONValue] = [
                    "result": .string(msg.content)
                ]
                parts.append(.functionResponse(FunctionResponse(name: toolName, response: response)))
            }

            for part in msg.parts {
                if case .image(let data, let mime) = part {
                    let base64 = data.base64EncodedString()
                    parts.append(.inlineData(InlineData(mimeType: mime, data: base64)))
                }
            }

            if parts.isEmpty { parts.append(.text("...")) }

            return Content(role: role, parts: parts)
        }
    }
}
