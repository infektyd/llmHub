import Foundation
import OSLog

struct XAIProvider: LLMProvider {
    private let logger = Logger(subsystem: "com.llmhub", category: "XAIProvider")
    let id: String = "xai"
    let name: String = "xAI (Grok)"

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

    var defaultHeaders: [String : String] {
        guard let key = keychain.apiKey(for: .xai) else { return [:] }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
    }

    var pricing: PricingMetadata {
        config.pricing ?? PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD")
    }
    
    var isConfigured: Bool {
        keychain.apiKey(for: .xai) != nil
    }
    
    func fetchModels() async throws -> [LLMModel] {

        // xAI does not provide a public /models endpoint; using static config list

        return config.models

    }
    
    @available(iOS 26.1, macOS 26.1, *)
    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        try buildRequest(messages: messages, model: model, jsonMode: false)
    }

    @available(iOS 26.1, macOS 26.1, *)
    func buildRequest(messages: [ChatMessage], model: String, jsonMode: Bool) throws -> URLRequest {
        guard let apiKey = keychain.apiKey(for: .xai) else {
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
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Modify request to enable streaming
                    var streamRequest = request
                    if let bodyData = request.httpBody,
                       var json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    
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
                    
                    var isFirstChunk = true
                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let jsonStr = String(trimmed.dropFirst(6))
                            if jsonStr == "[DONE]" { break }
                            
                            // Log the first chunk to see what model xAI reports
                            if isFirstChunk {
                                Logger(subsystem: "com.llmhub", category: "XAIProvider").debug("XAI First Stream Chunk: \(jsonStr)")
                                isFirstChunk = false
                            }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(XAIChatStreamChunk.self, from: data) {
                                
                                if let choice = chunk.choices.first, let content = choice.delta.content {
                                    fullText += content
                                    continuation.yield(.token(text: content))
                                }
                            }
                        }
                    }
                    
                    // Final completion
                    let message = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: fullText,
                        thoughtProcess: nil,
                        parts: [],
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
