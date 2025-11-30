import Foundation
import OSLog

/// A manager for xAI's Grok API, handling text, vision, and image generation.
/// xAI is largely OpenAI-compatible.
@available(iOS 26.1, macOS 26.1, *)
public class XAIManager {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.x.ai/v1")!
    private let logger = Logger(subsystem: "com.llmhub", category: "XAIManager")
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Chat & Vision
    
    /// Generates a chat completion (text or vision).
    public func chatCompletion(
        messages: [XAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [XAITool]? = nil
    ) async throws -> XAIChatResponse {
        let request = try makeChatRequest(
            messages: messages,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: stream,
            tools: tools
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw XAIError.networkError
        }
        
        if !(200...299).contains(http.statusCode) {
             if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw XAIError.apiError(message: message)
            }
            throw XAIError.serverError(statusCode: http.statusCode)
        }
        
        return try JSONDecoder().decode(XAIChatResponse.self, from: data)
    }
    
    /// Creates a URLRequest for chat completion.
    public func makeChatRequest(
        messages: [XAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [XAITool]? = nil
    ) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        
        let payload = XAIChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            stream: stream,
            tools: tools
        )
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let bodyData = try encoder.encode(payload)
        request.httpBody = bodyData
        
        // Debug: Log the actual request body being sent
        if let bodyString = String(data: bodyData, encoding: .utf8) {
            logger.debug("XAI Request Body:\n\(bodyString)")
        }
        
        return request
    }

    /// Streams chat completion chunks.
    public func streamChatCompletion(
        messages: [XAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<XAIChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try makeChatRequest(
                        messages: messages,
                        model: model,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        stream: true,
                        tools: nil
                    )
                    
                    let (result, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        throw XAIError.apiError(message: errorText)
                    }
                    
                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let json = String(trimmed.dropFirst(6))
                            if json == "[DONE]" { break }
                            
                            if let data = json.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(XAIChatStreamChunk.self, from: data) {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    
    // MARK: - Helpers
    
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw XAIError.networkError
        }
        
        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw XAIError.apiError(message: message)
            }
            throw XAIError.serverError(statusCode: http.statusCode)
        }
        
        return data
    }
}

// MARK: - Models

public enum XAIError: Error {
    case apiError(message: String)
    case networkError
    case serverError(statusCode: Int)
}

// Request Models

struct XAIChatRequest: Encodable {
    let model: String
    let messages: [XAIChatMessage]
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool?
    let tools: [XAITool]?
}

public struct XAIChatMessage: Encodable {
    public let role: String
    public let content: Content
    
    public enum Content: Encodable {
        case text(String)
        case parts([Part])
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let s): try container.encode(s)
            case .parts(let p): try container.encode(p)
            }
        }
    }
    
    public struct Part: Encodable {
        public let type: String
        public let text: String?
        public let image_url: ImageURL?
        
        public static func text(_ s: String) -> Part {
            Part(type: "text", text: s, image_url: nil)
        }
        
        public static func image(base64: String) -> Part {
            Part(type: "image_url", text: nil, image_url: ImageURL(url: "data:image/jpeg;base64,\(base64)"))
        }
    }
    
    public struct ImageURL: Encodable {
        public let url: String
        public init(url: String) { self.url = url }
    }
    
    public init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }
    
    public init(role: String, parts: [Part]) {
        self.role = role
        self.content = .parts(parts)
    }
}

public struct XAITool: Encodable {
    let type: String
    let function: XAIFunction
}

public struct XAIFunction: Encodable {
    let name: String
    let description: String?
    let parameters: [String: AnyEncodable]? // Simplified
}

// Response Models

public struct XAIChatResponse: Decodable {
    public let id: String
    public let choices: [Choice]
    public let usage: Usage?
    
    public struct Choice: Decodable {
        public let message: Message
        public let finish_reason: String?
    }
    
    public struct Message: Decodable {
        public let role: String?
        public let content: String?
        public let tool_calls: [ToolCall]?
    }
    
    public struct ToolCall: Decodable {
        public let id: String
        public let type: String
        public let function: FunctionCall
    }
    
    public struct FunctionCall: Decodable {
        public let name: String
        public let arguments: String
    }
    
    public struct Usage: Decodable {
        public let prompt_tokens: Int
        public let completion_tokens: Int
        public let total_tokens: Int
    }
}

public struct XAIChatStreamChunk: Decodable {
    public let id: String?
    public let model: String?  // Capture which model xAI says it used
    public let choices: [Choice]
    
    public struct Choice: Decodable {
        public let delta: Delta
        public let finish_reason: String?
    }
    
    public struct Delta: Decodable {
        public let content: String?
        public let role: String?
    }
}

// Utility

public struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    public init<T: Encodable>(_ value: T) {
        self.encodeFunc = value.encode
    }
    public func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
