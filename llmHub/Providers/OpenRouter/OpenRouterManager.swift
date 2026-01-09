import Foundation

/// A manager for OpenRouter API, handling Chat, Streaming, and Multimodal inputs.
@available(iOS 26.1, macOS 26.1, *)
public class OpenRouterManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The URLSession used for network requests.
    private let session: URLSession
    /// The base URL for the OpenRouter API.
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    // Optional app headers for OpenRouter
    /// The app URL for HTTP-Referer header (optional).
    private let appURL: String?
    /// The app name for X-Title header (optional).
    private let appName: String?

    /// Initializes a new `OpenRouterManager`.
    /// - Parameters:
    ///   - apiKey: The API key.
    ///   - appURL: The application URL (for rankings).
    ///   - appName: The application name (for rankings).
    ///   - session: The URLSession (default: `.shared`).
    public init(
        apiKey: String,
        appURL: String? = nil,
        appName: String? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.appURL = appURL
        self.appName = appName
        self.session = session
    }

    // MARK: - Chat Completions

    /// Sends a chat completion request to OpenRouter.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - stream: Whether to stream (default: false).
    ///   - transforms: Transforms to apply (optional).
    ///   - route: Route preference (optional).
    /// - Returns: An `ORChatResponse`.
    public func chatCompletion(
        messages: [ORMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        transforms: [String]? = nil,
        route: String? = nil
    ) async throws -> ORChatResponse {
        let payload = ORChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: stream,
            transforms: transforms,
            route: route
        )
        let url = baseURL.appendingPathComponent("chat/completions")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(ORChatResponse.self, from: data)
    }

    /// Streams chat completion chunks from OpenRouter.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - transforms: Transforms to apply (optional).
    ///   - route: Route preference (optional).
    /// - Returns: An async throwing stream of `ORStreamChunk`.
    public func streamChatCompletion(
        messages: [ORMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        transforms: [String]? = nil,
        route: String? = nil
    ) -> AsyncThrowingStream<ORStreamChunk, Error> {
        let payload = ORChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: true,
            transforms: transforms,
            route: route
        )
        let url = baseURL.appendingPathComponent("chat/completions")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = try makeRequest(url: url, payload: payload)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        var errorText = ""
                        for try await line in bytes.lines { errorText += line }
                        throw OpenRouterError.apiError(message: errorText)
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let json = String(trimmed.dropFirst(6))
                            if json == "[DONE]" { break }

                            if let data = json.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(ORStreamChunk.self, from: data) {
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

    // MARK: - Models

    /// Lists available models on OpenRouter.
    /// - Returns: An array of `ORModelInfo`.
    public func listModels() async throws -> [ORModelInfo] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenRouterError.networkError
        }

        // OpenRouter returns wrapped data object: { "data": [...] }
        struct Wrapper: Decodable { let data: [ORModelInfo] }
        return try JSONDecoder().decode(Wrapper.self, from: data).data
    }

    // MARK: - Helpers

    /// Creates a chat request object.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - stream: Streaming flag.
    /// - Returns: A configured `URLRequest`.
    public func makeChatRequest(
        messages: [ORMessage],
        model: String,
        stream: Bool,
        tools: [ORTool]? = nil,
        toolChoice: ORToolChoice? = nil,
        parallelToolCalls: Bool? = nil
    ) throws -> URLRequest {
        let payload = ORChatRequest(
            model: model,
            messages: messages,
            stream: stream,
            tools: tools,
            toolChoice: toolChoice,
            parallelToolCalls: parallelToolCalls
        )
        let url = baseURL.appendingPathComponent("chat/completions")
        return try makeRequest(url: url, payload: payload)
    }

    /// Helper to create a generic JSON request.
    private func makeRequest<T: Encodable>(url: URL, payload: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let referer = appURL { request.setValue(referer, forHTTPHeaderField: "HTTP-Referer") }
        if let title = appName { request.setValue(title, forHTTPHeaderField: "X-Title") }

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    /// Helper to perform a request and return data, handling errors.
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        let request = try makeRequest(url: url, payload: payload)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.networkError
        }

        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw OpenRouterError.apiError(message: message)
            }
            throw OpenRouterError.serverError(statusCode: http.statusCode)
        }

        return data
    }
}

// MARK: - Models

/// Errors specific to OpenRouter API.
public enum OpenRouterError: Error {
    /// API returned an error message.
    case apiError(message: String)
    /// Network connectivity error.
    case networkError
    /// Server returned a status code error.
    case serverError(statusCode: Int)
}

// --- Requests ---

/// Request payload for chat completions.
public struct ORChatRequest: Encodable {
    /// The model ID.
    let model: String
    /// The conversation messages.
    let messages: [ORMessage]
    /// Sampling temperature.
    var temperature: Double?
    /// Maximum tokens to generate.
    var maxTokens: Int?
    /// Streaming flag.
    var stream: Bool?
    /// Available tools (OpenAI-compatible).
    var tools: [ORTool]?
    /// Tool choice configuration (OpenAI-compatible).
    var toolChoice: ORToolChoice?
    /// Enable parallel tool calls where supported.
    var parallelToolCalls: Bool?
    /// List of transforms.
    var transforms: [String]?
    /// Route preference.
    var route: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools, transforms, route
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
    }
}

// --- Tools (OpenAI-compatible) ---

public struct ORTool: Encodable {
    let type: String
    let function: ORFunction
}

public struct ORFunction: Encodable {
    let name: String
    let description: String?
    let parameters: [String: OpenAIJSONValue]?
}

public enum ORToolChoice: Encodable {
    case auto
    case none
    case required

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .required: try container.encode("required")
        }
    }
}

/// Represents a chat message.
public struct ORMessage: Encodable {
    /// The role of the sender.
    public let role: String
    /// The content of the message.
    public let content: ORContent

    /// Initializes a new message.
    public init(role: String, content: ORContent) {
        self.role = role
        self.content = content
    }
}

/// The content of a chat message.
public enum ORContent: Encodable {
    /// Text content.
    case text(String)
    /// Multipart content.
    case parts([ORContentPart])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .parts(let p): try container.encode(p)
        }
    }
}

/// A part of the message content.
public struct ORContentPart: Encodable {
    /// The type of part (e.g., "text", "image_url").
    public let type: String
    /// The text content.
    public let text: String?
    /// The image URL information.
    public let imageUrl: ORImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    /// Creates a text part.
    public static func text(_ s: String) -> ORContentPart {
        ORContentPart(type: "text", text: s, imageUrl: nil)
    }

    /// Creates an image part from a URL.
    public static func image(url: String) -> ORContentPart {
        ORContentPart(type: "image_url", text: nil, imageUrl: ORImageURL(url: url))
    }

    /// Creates an image part from base64 data.
    public static func image(base64: String, mimeType: String = "image/jpeg") -> ORContentPart {
        ORContentPart(type: "image_url", text: nil, imageUrl: ORImageURL(url: "data:\(mimeType);base64,\(base64)"))
    }
}

/// Represents an image URL.
public struct ORImageURL: Encodable {
    /// The URL string.
    let url: String
}

// --- Responses ---

/// The response from a chat completion request.
public struct ORChatResponse: Decodable {
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
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    /// The message in a choice.
    public struct Message: Decodable {
        /// The role of the sender.
        public let role: String?
        /// The content of the message.
        public let content: String?
    }

    /// Token usage statistics.
    public struct Usage: Decodable {
        /// Prompt tokens used.
        public let promptTokens: Int
        /// Completion tokens used.
        public let completionTokens: Int
        /// Total tokens used.
        public let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// --- Streaming ---

/// A chunk of a streamed response.
public struct ORStreamChunk: Decodable {
    /// The chunk ID.
    public let id: String
    /// The choices in this chunk.
    public let choices: [Choice]
    /// Usage statistics (optional).
    public let usage: ORChatResponse.Usage? // Sometimes available in stream

    /// A choice in the stream chunk.
    public struct Choice: Decodable {
        /// The delta update.
        public let delta: Delta
        /// The finish reason.
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    /// The delta update.
    public struct Delta: Decodable {
        /// The role update.
        public let role: String?
        /// The content update.
        public let content: String?
        /// The tool calls update.
        public let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }

        public struct ToolCall: Decodable {
            public let index: Int
            public let id: String?
            public let function: FunctionCall?
        }

        public struct FunctionCall: Decodable {
            public let name: String?
            public let arguments: String?
        }
    }
}

// --- Models List ---

/// Information about a model on OpenRouter.
public struct ORModelInfo: Decodable {
    /// The model ID.
    public let id: String
    /// The model name.
    public let name: String
    /// Pricing information.
    public let pricing: Pricing?

    /// Pricing details.
    public struct Pricing: Decodable {
        /// Cost per prompt token.
        public let prompt: String
        /// Cost per completion token.
        public let completion: String
    }

    /// Context length of the model.
    public let context_length: Int
}
