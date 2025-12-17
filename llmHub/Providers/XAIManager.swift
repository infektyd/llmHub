import Foundation
import OSLog

/// A manager for xAI's Grok API, handling text, vision, and image generation.
/// xAI is largely OpenAI-compatible.
@available(iOS 26.1, macOS 26.1, *)
public class XAIManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The base URL for the xAI API.
    private let baseURL = URL(string: "https://api.x.ai/v1")!
    /// Logger instance.
    private let logger = Logger(subsystem: "com.llmhub", category: "XAIManager")
    
    /// Initializes a new `XAIManager`.
    /// - Parameter apiKey: The API key.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Chat & Vision
    
    /// Generates a chat completion (text or vision).
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - stream: Whether to stream (default: false).
    ///   - tools: Available tools (optional).
    /// - Returns: An `XAIChatResponse`.
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
        
        let (data, response) = try await LLMURLSession.shared.data(for: request)
        
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
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature.
    ///   - maxTokens: Max tokens.
    ///   - stream: Streaming flag.
    ///   - tools: Available tools.
    /// - Returns: A configured `URLRequest`.
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
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature.
    ///   - maxTokens: Max tokens.
    /// - Returns: An async throwing stream of `XAIChatStreamChunk`.
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
                    
                    let (result, response) = try await LLMURLSession.shared.bytes(for: request)
                    
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
    
    /// Helper to perform a request.
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await LLMURLSession.shared.data(for: request)
        
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

/// Errors specific to xAI API.
public enum XAIError: Error {
    /// API returned an error message.
    case apiError(message: String)
    /// Network connectivity error.
    case networkError
    /// Server returned a status code error.
    case serverError(statusCode: Int)
}

// Request Models

/// Request payload for chat completion.
struct XAIChatRequest: Encodable {
    /// Model ID.
    let model: String
    /// Conversation messages.
    let messages: [XAIChatMessage]
    /// Sampling temperature.
    let temperature: Double?
    /// Maximum tokens.
    let max_tokens: Int?
    /// Streaming flag.
    let stream: Bool?
    /// Available tools.
    let tools: [XAITool]?
}

/// Represents a chat message.
public struct XAIChatMessage: Encodable {
    /// The role of the sender.
    public let role: String
    /// The content of the message.
    public let content: Content
    
    /// The content of a chat message.
    public enum Content: Encodable {
        /// Text content.
        case text(String)
        /// Multipart content.
        case parts([Part])
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let s): try container.encode(s)
            case .parts(let p): try container.encode(p)
            }
        }
    }
    
    /// A part of the message content.
    public struct Part: Encodable {
        /// The type of part (e.g., "text", "image_url").
        public let type: String
        /// The text content.
        public let text: String?
        /// The image URL information.
        public let image_url: ImageURL?
        
        /// Creates a text part.
        public static func text(_ s: String) -> Part {
            Part(type: "text", text: s, image_url: nil)
        }
        
        /// Creates an image part from base64 data.
        public static func image(base64: String) -> Part {
            Part(type: "image_url", text: nil, image_url: ImageURL(url: "data:image/jpeg;base64,\(base64)"))
        }
    }
    
    /// Represents an image URL.
    public struct ImageURL: Encodable {
        /// The URL string.
        public let url: String
        public init(url: String) { self.url = url }
    }
    
    /// Initializes a text message.
    public init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }
    
    /// Initializes a multipart message.
    public init(role: String, parts: [Part]) {
        self.role = role
        self.content = .parts(parts)
    }
}

/// Represents a tool available to the model.
public struct XAITool: Encodable {
    /// The type of tool (e.g., "function").
    let type: String
    /// The function definition.
    let function: XAIFunction
}

/// Defines a function for tool use.
public struct XAIFunction: Encodable {
    /// The function name.
    let name: String
    /// The function description.
    let description: String?
    /// The parameters schema.
    let parameters: [String: AnyEncodable]? // Simplified
}

// Response Models

/// The response from a chat completion.
public struct XAIChatResponse: Decodable {
    /// The response ID.
    public let id: String
    /// The generated choices.
    public let choices: [Choice]
    /// Token usage statistics.
    public let usage: Usage?
    
    /// A choice in the response.
    public struct Choice: Decodable {
        /// The generated message.
        public let message: Message
        /// The finish reason.
        public let finish_reason: String?
    }
    
    /// The message in a choice.
    public struct Message: Decodable {
        /// The role of the sender.
        public let role: String?
        /// The content of the message.
        public let content: String?
        /// Tool calls made by the model.
        public let tool_calls: [ToolCall]?
    }
    
    /// A tool call.
    public struct ToolCall: Decodable {
        /// The tool call ID.
        public let id: String
        /// The type of tool.
        public let type: String
        /// The function call details.
        public let function: FunctionCall
    }
    
    /// The function call details.
    public struct FunctionCall: Decodable {
        /// The function name.
        public let name: String
        /// The arguments string.
        public let arguments: String
    }
    
    /// Token usage statistics.
    public struct Usage: Decodable {
        /// Prompt tokens used.
        public let prompt_tokens: Int
        /// Completion tokens used.
        public let completion_tokens: Int
        /// Total tokens used.
        public let total_tokens: Int
    }
}

/// A chunk of a streamed response.
public nonisolated struct XAIChatStreamChunk: Decodable, Sendable {
    /// The chunk ID.
    public let id: String?
    /// The model used.
    public let model: String?  // Capture which model xAI says it used
    /// Optional citations/references (provider-specific).
    public let citations: [String]?
    /// The choices in this chunk.
    public let choices: [Choice]
    
    /// A choice in the stream chunk.
    public struct Choice: Decodable, Sendable {
        /// The delta update.
        public let delta: Delta
        /// The finish reason.
        public let finish_reason: String?
    }
    
    /// The delta update.
    public struct Delta: Decodable, Sendable {
        /// The content update.
        public let content: String?
        /// Optional reasoning content (provider-specific).
        public let reasoning_content: String?
        /// The role update.
        public let role: String?
        /// The tool calls update.
        public let tool_calls: [ToolCall]?
        
        public struct ToolCall: Decodable, Sendable {
            public let index: Int
            public let id: String?
            public let function: FunctionCall?
        }
        
        public struct FunctionCall: Decodable, Sendable {
            public let name: String?
            public let arguments: String?
        }
    }
}

// Utility

/// A type-erased encodable wrapper.
public struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    /// Initializes a new `AnyEncodable`.
    public init<T: Encodable>(_ value: T) {
        self.encodeFunc = value.encode
    }
    public func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
