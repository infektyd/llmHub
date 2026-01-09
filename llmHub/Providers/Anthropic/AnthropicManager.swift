import Foundation

/// A manager for Anthropic's Claude API, handling Chat, Streaming, and Files.
@available(iOS 26.1, macOS 26.1, *)
public class AnthropicManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The URLSession used for network requests.
    private let session: URLSession
    /// The base URL for the Anthropic API.
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!
    /// The API version string.
    private let version = "2023-06-01"

    /// Initializes a new `AnthropicManager`.
    /// - Parameters:
    ///   - apiKey: The API key for Anthropic.
    ///   - session: The `URLSession` to use (default: `.shared`).
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Chat

    /// Sends a chat completion request to the Anthropic API.
    /// - Parameters:
    ///   - messages: The conversation history.
    ///   - model: The model identifier to use.
    ///   - maxTokens: The maximum number of tokens to generate.
    ///   - temperature: The sampling temperature (optional).
    ///   - system: System instructions (optional).
    ///   - tools: List of tools available to the model (optional).
    /// - Returns: An `AnthropicMessageResponse` containing the model's reply.
    public func chatCompletion(
        messages: [AnthropicMessage],
        model: String,
        maxTokens: Int,
        temperature: Double? = nil,
        system: String? = nil,
        tools: [AnthropicTool]? = nil
    ) async throws -> AnthropicMessageResponse {
        let payload = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            messages: messages,
            stream: false,
            system: system,
            tools: tools,
            thinking: nil
        )
        let url = baseURL.appendingPathComponent("messages")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
    }

    /// Streams a chat completion response from the Anthropic API.
    /// - Parameters:
    ///   - messages: The conversation history.
    ///   - model: The model identifier to use.
    ///   - maxTokens: The maximum number of tokens to generate.
    ///   - temperature: The sampling temperature (optional).
    ///   - system: System instructions (optional).
    ///   - tools: List of tools available to the model (optional).
    /// - Returns: An async throwing stream of `AnthropicStreamEvent`.
    public func streamChatCompletion(
        messages: [AnthropicMessage],
        model: String,
        maxTokens: Int,
        temperature: Double? = nil,
        system: String? = nil,
        tools: [AnthropicTool]? = nil
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        let payload = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            messages: messages,
            stream: true,
            system: system,
            tools: tools,
            thinking: nil
        )
        let url = baseURL.appendingPathComponent("messages")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = try makeRequest(url: url, payload: payload)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        var errorText = ""
                        for try await line in bytes.lines { errorText += line }
                        throw AnthropicError.apiError(message: errorText)
                    }

                    let decoder = JSONDecoder()
                    var buffer = ""

                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))
                        while let range = buffer.range(of: "\n\n") {
                            let chunk = String(buffer[..<range.lowerBound])
                            buffer.removeSubrange(..<range.upperBound)
                            guard chunk.hasPrefix("data: ") else { continue }
                            let jsonStr = String(chunk.dropFirst(6))
                            if jsonStr == "[DONE]" { break }

                            guard let data = jsonStr.data(using: .utf8) else { continue }
                            if let event = try? decoder.decode(
                                AnthropicStreamEvent.self, from: data) {
                                continuation.yield(event)
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

    // MARK: - Files & Analysis

    /// Uploads a file to Anthropic for use in requests.
    /// - Parameters:
    ///   - data: The raw file data.
    ///   - filename: The name of the file.
    ///   - mimeType: The MIME type of the file.
    /// - Returns: The ID of the uploaded file.
    public func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        // Typically POST /v1/files (Beta)
        // Note: Check if endpoint is strictly /v1/files for beta.
        let url = baseURL.appendingPathComponent("files")  // Verify endpoint

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        // Beta headers
        request.setValue("files-2025-04-14", forHTTPHeaderField: "anthropic-beta")  // Hypothetical beta header from previous code

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(
                using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AnthropicError.serverError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct FileResp: Decodable { let id: String }
        return try JSONDecoder().decode(FileResp.self, from: responseData).id
    }

    // MARK: - Helpers

    /// Creates a URLRequest for a chat message.
    /// - Parameters:
    ///   - messages: The conversation history.
    ///   - model: The model identifier.
    ///   - maxTokens: The maximum tokens.
    ///   - stream: Whether to stream the response.
    ///   - tools: Optional tools.
    /// - Returns: A configured `URLRequest`.
    public func makeChatRequest(
        messages: [AnthropicMessage],
        model: String,
        maxTokens: Int,
        stream: Bool,
        system: String? = nil,
        tools: [AnthropicTool]? = nil
    ) throws -> URLRequest {
        let payload = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            messages: messages,
            stream: stream,
            system: system,
            tools: tools,
            thinking: nil
        )
        return try makeRequest(url: baseURL.appendingPathComponent("messages"), payload: payload)
    }

    /// Helper to create a generic request with standard headers.
    private func makeRequest<T: Encodable>(url: URL, payload: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add beta headers
        let betas = [
            "files-api-2025-04-14",
            "interleaved-thinking-2025-05-14",
            "structured-outputs-2025-11-13",
            "effort-2025-11-24",
            "prompt-caching-2024-07-31"
        ]
        request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    /// Helper to perform a request and return data, handling errors.
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        let request = try makeRequest(url: url, payload: payload)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.networkError
        }

        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorObj = json["error"] as? [String: Any],
                let message = errorObj["message"] as? String {
                throw AnthropicError.apiError(message: message)
            }
            throw AnthropicError.serverError(statusCode: http.statusCode)
        }

        return data
    }
}

// MARK: - Models

/// Errors specific to the Anthropic API.
public enum AnthropicError: Error {
    /// An error returned by the API with a message.
    case apiError(message: String)
    /// A network connectivity error.
    case networkError
    /// A server-side error with a status code.
    case serverError(statusCode: Int)
}

/// The structure of a request to the /messages endpoint.
public struct AnthropicMessagesRequest: Encodable {
    /// The model to use.
    public let model: String
    /// The maximum number of tokens to generate.
    public let max_tokens: Int
    /// The list of messages in the conversation.
    public let messages: [AnthropicMessage]
    /// Whether to stream the response.
    public let stream: Bool
    /// System instructions.
    public let system: String?
    /// Available tools.
    public let tools: [AnthropicTool]?
    /// Thinking configuration.
    public let thinking: AnthropicThinkingConfig?
}

/// Configuration for the "thinking" capability of the model.
public struct AnthropicThinkingConfig: Encodable {
    /// The type of thinking config.
    public let type: String
    /// The token budget for thinking.
    public let budget_tokens: Int
}

/// Definition of a tool that can be used by the model.
public struct AnthropicTool: Encodable {
    /// The name of the tool.
    public let name: String
    /// A description of the tool.
    public let description: String?
    /// The input schema for the tool.
    public let input_schema: AnthropicJSONValue?

    /// Initializes a new `AnthropicTool`.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description (optional).
    ///   - inputSchema: The JSON schema for inputs (optional).
    public init(name: String, description: String?, inputSchema: [String: Any]?) {
        self.name = name
        self.description = description
        self.input_schema = inputSchema.map { AnthropicJSONValue.from($0) }
    }
}

// JSON value wrapper for Anthropic API (handles Any -> Encodable conversion)
/// A wrapper enum to handle untyped JSON values in a strongly typed way for Encodable conformance.
public enum AnthropicJSONValue: Encodable {
    /// Null value.
    case null
    /// Boolean value.
    case bool(Bool)
    /// Integer value.
    case int(Int)
    /// Double value.
    case double(Double)
    /// String value.
    case string(String)
    /// Array of values.
    case array([AnthropicJSONValue])
    /// Object (dictionary) of values.
    case object([String: AnthropicJSONValue])

    /// Converts an `Any` value to `AnthropicJSONValue`.
    public static func from(_ value: Any) -> AnthropicJSONValue {
        switch value {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let d as Double:
            return .double(d)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        default:
            return .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            // Guard against non-finite values (NaN, Infinity) which are not valid JSON
            try container.encode(d.isFinite ? d : 0.0)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let dict):
            try container.encode(dict)
        }
    }
}

/// Represents a single message in an Anthropic conversation.
public struct AnthropicMessage: Encodable {
    /// The role of the message sender.
    public let role: String
    /// The content of the message.
    public let content: [AnthropicContentBlock]

    /// Initializes a new `AnthropicMessage`.
    public init(role: String, content: [AnthropicContentBlock]) {
        self.role = role
        self.content = content
    }
}

/// A block of content within a message.
public enum AnthropicContentBlock: Encodable {
    /// Text content.
    case text(AnthropicTextBlock)
    /// Image content.
    case image(AnthropicImageSource)
    /// Tool use request.
    case toolUse(AnthropicToolUse)
    /// Tool result.
    case toolResult(AnthropicToolResult)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try t.encode(to: encoder)
        case .image(let i):
            try container.encode("image", forKey: .type)
            try container.encode(i, forKey: .source)
        case .toolUse(let tu):
            try tu.encode(to: encoder)
        case .toolResult(let tr):
            try container.encode("tool_result", forKey: .type)
            try container.encode(tr.tool_use_id, forKey: .tool_use_id)
            try container.encode(tr.content, forKey: .content)
        }
    }

    enum CodingKeys: String, CodingKey { case type, source, id, name, input, tool_use_id, content }
}

/// Represents a request to use a tool.
public struct AnthropicToolUse: Encodable {
    /// The type of block (always "tool_use").
    public let type: String = "tool_use"
    /// The unique ID of the tool use.
    public let id: String
    /// The name of the tool.
    public let name: String
    /// The input arguments for the tool.
    public let input: AnthropicJSONValue

    /// Initializes a new `AnthropicToolUse`.
    public init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name
        self.input = .object(input.mapValues { AnthropicJSONValue.from($0) })
    }
}

/// Represents the result of a tool execution.
public struct AnthropicToolResult: Encodable {
    /// The ID of the tool use this result corresponds to.
    public let tool_use_id: String
    /// The result content.
    public let content: String

    /// Initializes a new `AnthropicToolResult`.
    public init(tool_use_id: String, content: String) {
        self.tool_use_id = tool_use_id
        self.content = content
    }
}

/// A block of text content.
public struct AnthropicTextBlock: Encodable {
    /// The type of block (always "text").
    public let type: String = "text"
    /// The text content.
    public let text: String
    /// Cache control settings.
    public let cache_control: AnthropicCacheControl?

    /// Initializes a new `AnthropicTextBlock`.
    public init(text: String, cacheControl: AnthropicCacheControl? = nil) {
        self.text = text
        self.cache_control = cacheControl
    }
}

/// Cache control configuration for prompt caching.
public struct AnthropicCacheControl: Encodable {
    /// The type of cache control.
    public let type: String
    /// Initializes a new `AnthropicCacheControl` (default: "ephemeral").
    public init(type: String = "ephemeral") { self.type = type }
}

/// Represents an image source for multimodal input.
public struct AnthropicImageSource: Encodable {
    /// The encoding type (e.g., "base64").
    public let type: String  // "base64"
    /// The media type (e.g., "image/jpeg").
    public let media_type: String
    /// The encoded data.
    public let data: String

    /// Initializes a new `AnthropicImageSource`.
    public init(type: String = "base64", media_type: String, data: String) {
        self.type = type
        self.media_type = media_type
        self.data = data
    }
}

/// The response from the /messages endpoint.
public struct AnthropicMessageResponse: Decodable {
    /// The ID of the response message.
    public let id: String
    /// The content of the response.
    public let content: [AnthropicResponseContent]
    /// Token usage statistics.
    public let usage: Usage

    /// Token usage statistics structure.
    public struct Usage: Decodable {
        /// Input tokens used.
        public let input_tokens: Int
        /// Output tokens generated.
        public let output_tokens: Int
    }
}

/// Content returned in the response.
public enum AnthropicResponseContent: Decodable {
    /// Text content.
    case text(AnthropicResponseText)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        if type == "text" {
            self = .text(try AnthropicResponseText(from: decoder))
        } else {
            // Fallback for tools etc.
            self = .text(AnthropicResponseText(type: "text", text: ""))
        }
    }

    enum CodingKeys: String, CodingKey { case type }
}

/// Text content in a response.
public struct AnthropicResponseText: Decodable {
    /// The type of content.
    public let type: String
    /// The text content.
    public let text: String
}

// SSE Events
/// An event received during a streaming response.
/// An event received during a streaming response.
public struct AnthropicStreamEvent: Decodable {
    /// The type of event.
    public let type: String
    /// The data delta.
    public let delta: AnthropicStreamDelta?
    /// Usage information (if applicable).
    public let usage: AnthropicMessageResponse.Usage?
    /// Content block information.
    public let content_block: AnthropicStreamContentBlock?
    /// The index of the content block.
    public let index: Int?
    /// Message information (for message_start/delta).
    public let message: AnthropicMessageResponse?
}

/// Content block information in a stream event.
public struct AnthropicStreamContentBlock: Decodable {
    /// The type of content block.
    public let type: String
    /// The ID of the content block.
    public let id: String?
    /// The name of the content block.
    public let name: String?
    /// The text content (for text blocks in start event).
    public let text: String?
}

/// The delta data in a stream event.
public struct AnthropicStreamDelta: Decodable {
    /// The type of delta.
    public let type: String?
    /// The text content delta.
    public let text: String?
    /// Thinking content delta.
    public let thinking: String?
    /// Partial JSON delta (for tool calls).
    public let partial_json: String?
    /// Stop reason for message delta.
    public let stop_reason: String?
    /// Stop sequence for message delta.
    public let stop_sequence: String?
}
