import Foundation

struct OpenAIProvider: LLMProvider {
    let id: String = "openai"
    let name: String = "OpenAI"
    
    private let keychain: KeychainStore
    private let config: ProvidersConfig.OpenAI
    
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
    
    var defaultHeaders: [String : String] {
        guard let key = keychain.apiKey(for: .openAI) else { return [:] }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
    }
    
    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0.005, outputPer1KUSD: 0.015, currency: "USD")
    }
    
    var isConfigured: Bool {
        keychain.apiKey(for: .openAI) != nil
    }
    
    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = keychain.apiKey(for: .openAI) else { return [] }
        let manager = OpenAIManager(apiKey: apiKey)
        
        do {
            let models = try await manager.listModels()
            return models.map { model in
                LLMModel(
                    id: model.id,
                    name: model.id,
                    maxOutputTokens: 4096 // Default as API doesn't return this
                )
            }
        } catch {
            return config.models // Fallback
        }
    }
    
    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        try buildRequest(messages: messages, model: model, jsonMode: false)
    }
    
    func buildRequest(messages: [ChatMessage], model: String, jsonMode: Bool) throws -> URLRequest {
        guard let apiKey = keychain.apiKey(for: .openAI) else {
            throw LLMProviderError.authenticationMissing
        }
        
        let manager = OpenAIManager(apiKey: apiKey)
        
        // Map messages
        let openAIMessages = messages.map { msg -> OpenAIChatMessage in
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
                    case .image(let data, _):
                        parts.append(.image(base64: data.base64EncodedString()))
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
        
        // Default to non-streaming request builder
        return try manager.makeChatRequest(
            messages: openAIMessages,
            model: model,
            stream: false,
            responseFormat: jsonMode ? OpenAIResponseFormat(type: "json_object") : nil
        )
    }
    
    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Modify request to enable streaming if not already
                    var streamRequest = request
                    // Ensure stream=true in body
                    if let bodyData = request.httpBody,
                       var json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    // 2. Execute
                    let (result, response) = try await URLSession.shared.bytes(for: streamRequest)
                    
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        continuation.yield(.error(.server(reason: errorText.isEmpty ? "Unknown stream error" : errorText)))
                        continuation.finish()
                        return
                    }
                    
                    var fullText = ""
                    
                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) {
                                
                                if let choice = chunk.choices.first, let content = choice.delta.content {
                                    fullText += content
                                    continuation.yield(.token(text: content))
                                }
                                
                                // Usage in final chunk (sometimes provided by OpenAI)
                                if let usage = chunk.usage {
                                    continuation.yield(.usage(TokenUsage(
                                        inputTokens: usage.promptTokens,
                                        outputTokens: usage.completionTokens,
                                        cachedTokens: 0
                                    )))
                                }
                            }
                        }
                    }
                    
                    // Final completion
                    let message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        parts: [], // Initialize with empty parts
                        createdAt: Date(),
                        codeBlocks: [],
                        tokenUsage: nil,
                        costBreakdown: nil
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
