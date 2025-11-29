import Foundation

struct AnthropicProvider: LLMProvider {
    let id: String = "anthropic"
    let name: String = "Anthropic (Claude)"

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
    
    var defaultHeaders: [String: String] {
        [:] // Handled by Manager
    }

    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest {
        guard let key = keychain.apiKey(for: .anthropic) else { throw LLMProviderError.authenticationMissing }
        
        let manager = AnthropicManager(apiKey: key)
        
        // Map messages
        let anthropicMessages: [AnthropicMessage] = messages.map { msg in
            var blocks: [AnthropicContentBlock] = []
            if !msg.content.isEmpty {
                blocks.append(.text(AnthropicTextBlock(text: msg.content)))
            }
            
            for part in msg.parts {
                switch part {
                case .text(let t):
                    if t != msg.content { blocks.append(.text(AnthropicTextBlock(text: t))) }
                case .image(let data, let mime):
                     blocks.append(.image(AnthropicImageSource(media_type: mime, data: data.base64EncodedString())))
                case .imageURL:
                     // Anthropic doesn't support image URLs directly, usually need base64.
                     // For now, ignore or implement downloading if needed.
                     break
                }
            }
            
            if blocks.isEmpty {
                blocks.append(.text(AnthropicTextBlock(text: msg.content))) // Fallback
            }
            
            return AnthropicMessage(role: msg.role == .user ? "user" : "assistant", content: blocks)
        }
        
        let maxTokens = min(availableModels.first?.maxOutputTokens ?? 4096, 64_000)
        
        return try manager.makeChatRequest(
            messages: anthropicMessages,
            model: model,
            maxTokens: maxTokens,
            stream: false
        )
    }

    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Modify for stream
                    var streamRequest = request
                    // Inject stream: true in body if possible, or just trust the caller set it up? 
                    // AnthropicManager's makeChatRequest sets stream based on param.
                    // But here we might be reusing a non-streaming request builder.
                    // Let's re-decode and re-encode if necessary, OR just assume LLMProvider flows:
                    // Usually buildRequest is called, then streamResponse.
                    // If buildRequest defaulted to stream=false, we need to flip it.
                    
                    if let bodyData = request.httpBody,
                       var json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                        json["stream"] = true
                        streamRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
                    }
                    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: streamRequest)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        // Error handling
                        continuation.yield(.error(.server(reason: "Stream failed")))
                        continuation.finish()
                        return
                    }
                    
                    let decoder = JSONDecoder()
                    var buffer = ""
                    var aggregated = ""
                    
                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))
                        while let range = buffer.range(of: "\n\n") {
                            let chunk = String(buffer[..<range.lowerBound])
                            buffer.removeSubrange(..<range.upperBound)
                            guard chunk.hasPrefix("data: ") else { continue }
                            let jsonStr = String(chunk.dropFirst(6))
                            if jsonStr == "[DONE]" { break }
                            
                            guard let data = jsonStr.data(using: .utf8) else { continue }
                            if let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) {
                                switch event.type {
                                case "content_block_delta":
                                    if let text = event.delta?.text {
                                        aggregated += text
                                        continuation.yield(.token(text: text))
                                    }
                                case "message_delta":
                                    if let usage = event.usage {
                                        continuation.yield(.usage(TokenUsage(
                                            inputTokens: usage.input_tokens,
                                            outputTokens: usage.output_tokens,
                                            cachedTokens: 0
                                        )))
                                    }
                                case "message_stop":
                                     let message = ChatMessage(
                                        id: UUID(),
                                        role: .assistant,
                                        content: aggregated,
                                        parts: [],
                                        createdAt: Date(),
                                        codeBlocks: [],
                                        tokenUsage: nil,
                                        costBreakdown: nil
                                    )
                                    continuation.yield(.completion(message: message))
                                default: break
                                }
                            }
                        }
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
