import Foundation

/// A manager for OpenAI's API, handling Chat (Completions & Responses), Streaming, Vision, Audio, Images, Video, and Embeddings.
/// Designed for maximum flexibility and feature parity.
@available(iOS 26.1, macOS 26.1, *)
public class OpenAIManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The organization ID (optional).
    private let organizationID: String?
    /// The URLSession used for network requests.
    private let session: URLSession

    /// The base URL for the OpenAI API.
    private let baseURL = URL(string: "https://api.openai.com/v1")!

    /// Initializes a new `OpenAIManager`.
    /// - Parameters:
    ///   - apiKey: The API key.
    ///   - organizationID: The organization ID (optional).
    ///   - session: The URLSession (default: `.shared`).
    public init(apiKey: String, organizationID: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.session = session
    }

    // MARK: - Chat Completions

    /// Sends a chat completion request.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - stream: Whether to stream responses (default: false).
    ///   - tools: Available tools (optional).
    ///   - toolChoice: Tool choice strategy (optional).
    ///   - responseFormat: The desired response format (optional).
    ///   - reasoningEffort: Reasoning effort for o-series models (optional).
    /// - Returns: An `OpenAIChatResponse`.
    public func chatCompletion(
        messages: [OpenAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [OpenAITool]? = nil,
        toolChoice: OpenAIToolChoice? = nil,
        responseFormat: OpenAIResponseFormat? = nil,
        reasoningEffort: String? = nil  // "low", "medium", "high" for o-series
    ) async throws -> OpenAIChatResponse {
        let payload = OpenAIChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: stream,
            tools: tools,
            toolChoice: toolChoice,
            responseFormat: responseFormat,
            reasoningEffort: reasoningEffort
        )
        let url = baseURL.appendingPathComponent("chat/completions")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
    }

    /// Streams chat completion chunks.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - tools: Available tools (optional).
    ///   - toolChoice: Tool choice strategy (optional).
    /// - Returns: An async throwing stream of `OpenAIStreamChunk`.
    public func streamChatCompletion(
        messages: [OpenAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        tools: [OpenAITool]? = nil,
        toolChoice: OpenAIToolChoice? = nil
    ) -> AsyncThrowingStream<OpenAIStreamChunk, Error> {
        let payload = OpenAIChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: true,
            tools: tools,
            toolChoice: toolChoice,
            responseFormat: nil,
            reasoningEffort: nil
        )
        let url = baseURL.appendingPathComponent("chat/completions")

        return AsyncThrowingStream { continuation in
            // Capture session weakly to prevent retain cycle
            let localSession = self.session
            
            let task = Task {
                do {
                    var request = try makeRequest(url: url, payload: payload)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await localSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        var errorText = ""
                        for try await line in bytes.lines { errorText += line }
                        throw OpenAIError.apiError(message: errorText)
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let json = String(trimmed.dropFirst(6))
                            if json == "[DONE]" { break }

                            if let data = json.data(using: .utf8),
                                let chunk = try? JSONDecoder().decode(
                                    OpenAIStreamChunk.self, from: data)
                            {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Models

    /// Lists available OpenAI models.
    /// - Returns: An array of `OpenAIModel`.
    public func listModels() async throws -> [OpenAIModel] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenAIError.networkError
        }

        return try JSONDecoder().decode(OpenAIModelList.self, from: data).data
    }

    // MARK: - Request Helper

    /// Creates a chat request.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - stream: Streaming flag.
    ///   - tools: Available tools.
    ///   - toolChoice: Tool choice strategy.
    ///   - responseFormat: Response format.
    /// - Returns: A configured `URLRequest`.
    public func makeChatRequest(
        messages: [OpenAIChatMessage],
        model: String,
        stream: Bool,
        tools: [OpenAITool]? = nil,
        toolChoice: OpenAIToolChoice? = nil,
        responseFormat: OpenAIResponseFormat? = nil
    ) throws -> URLRequest {
        let payload = OpenAIChatRequest(
            model: model,
            messages: messages,
            stream: stream,
            tools: tools,
            toolChoice: toolChoice,
            responseFormat: responseFormat
        )
        let url = baseURL.appendingPathComponent("chat/completions")
        return try makeRequest(url: url, payload: payload)
    }

    // MARK: - Responses API (gpt-4.1 / gpt-5 family)

    public func makeResponsesRequest(
        messages: [OpenAIChatMessage],
        model: String,
        tools: [OpenAITool]? = nil,
        jsonMode: Bool = false,
        reasoningSummary: String? = nil
    ) throws -> URLRequest {
        let inputs: [OpenAIResponseInput] = messages.map { msg in
            let role = MessageRole(rawValue: msg.role) ?? .assistant
            let parts: [OpenAIResponseContent]
            switch msg.content {
            case .text(let text):
                parts = [.text(.init(text: text, role: role))]
            case .parts(let contentParts):
                parts = contentParts.compactMap { part in
                    if part.type == "text", let text = part.text {
                        return .text(.init(text: text, role: role))
                    }
                    if let image = part.imageUrl?.url, let url = URL(string: image) {
                        return .imageURL(.init(url: url))
                    }
                    return nil
                }
            }
            return OpenAIResponseInput(role: role, content: parts)
        }

        #if DEBUG
            // Guardrail: Fail fast if invalid content type appears in Responses payload
            for input in inputs {
                for content in input.content {
                    if case .text(let t) = content {
                        assert(
                            t.type == "input_text" || t.type == "output_text",
                            "Invalid Responses content type: \(t.type). Expected 'input_text' or 'output_text'."
                        )
                    }
                }
            }
        #endif

        // Convert tools to Responses API format (flattened structure)
        let responsesTools: [OpenAIResponsesTool]? = tools?.map { OpenAIResponsesTool(from: $0) }

        let payload = OpenAIResponsesRequest(
            model: model,
            input: inputs,
            tools: responsesTools,
            reasoning: reasoningSummary.map { OpenAIResponsesReasoning(summary: $0) },
            stream: false,
            responseFormat: jsonMode ? OpenAIResponseFormat(type: "json_object") : nil
        )
        let url = baseURL.appendingPathComponent("responses")
        return try makeRequest(url: url, payload: payload)
    }

    // MARK: - Images

    /// Generates images with DALL-E.
    /// - Parameters:
    ///   - prompt: The image description.
    ///   - model: Model ID (default: "dall-e-3").
    ///   - n: Number of images (default: 1).
    ///   - size: Image size (default: "1024x1024").
    ///   - responseFormat: Response format (default: "url").
    /// - Returns: An `OpenAIImageResponse`.
    public func generateImage(
        prompt: String,
        model: String = "dall-e-3",
        n: Int = 1,
        size: String = "1024x1024",
        responseFormat: String = "url"  // "url" or "b64_json"
    ) async throws -> OpenAIImageResponse {
        let payload = OpenAIImageRequest(
            model: model,
            prompt: prompt,
            n: n,
            size: size,
            responseFormat: responseFormat
        )
        let url = baseURL.appendingPathComponent("images/generations")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(OpenAIImageResponse.self, from: data)
    }

    // MARK: - Audio

    /// Generates speech from text.
    /// - Parameters:
    ///   - model: Model ID (default: "tts-1").
    ///   - input: Text to speak.
    ///   - voice: Voice ID (default: "alloy").
    ///   - responseFormat: Audio format (default: "mp3").
    /// - Returns: The raw audio data.
    public func createSpeech(
        model: String = "tts-1",
        input: String,
        voice: String = "alloy",
        responseFormat: String = "mp3"
    ) async throws -> Data {
        let payload = OpenAISpeechRequest(
            model: model,
            input: input,
            voice: voice,
            responseFormat: responseFormat
        )
        let url = baseURL.appendingPathComponent("audio/speech")
        return try await performRequest(url: url, payload: payload)
    }

    /// Transcribes audio to text.
    /// - Parameters:
    ///   - fileData: Audio file data.
    ///   - fileName: Audio file name.
    ///   - model: Model ID (default: "whisper-1").
    ///   - language: Language code (optional).
    /// - Returns: An `OpenAITranscriptionResponse`.
    public func transcribeAudio(
        fileData: Data,
        fileName: String,
        model: String = "whisper-1",
        language: String? = nil
    ) async throws -> OpenAITranscriptionResponse {
        let url = baseURL.appendingPathComponent("audio/transcriptions")
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        if let lang = language { appendField("language", lang) }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(
                using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.networkError }
        if !(200...299).contains(http.statusCode) {
            throw OpenAIError.serverError(statusCode: http.statusCode)
        }

        return try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
    }

    // MARK: - Embeddings

    /// Creates embeddings for text input.
    /// - Parameters:
    ///   - input: Array of text strings.
    ///   - model: Model ID (default: "text-embedding-3-small").
    ///   - dimensions: Embedding dimensions (optional).
    /// - Returns: An `OpenAIEmbeddingsResponse`.
    public func createEmbeddings(
        input: [String],
        model: String = "text-embedding-3-small",
        dimensions: Int? = nil
    ) async throws -> OpenAIEmbeddingsResponse {
        let payload = OpenAIEmbeddingsRequest(
            input: input,
            model: model,
            dimensions: dimensions
        )
        let url = baseURL.appendingPathComponent("embeddings")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(OpenAIEmbeddingsResponse.self, from: data)
    }

    // MARK: - Private Helpers

    /// Adds authentication and organization headers to the request.
    private func addHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let org = organizationID {
            request.setValue(org, forHTTPHeaderField: "OpenAI-Organization")
        }
    }

    /// Creates a generic JSON request.
    private func makeRequest<T: Encodable>(url: URL, payload: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    /// Performs a request and returns data, handling errors.
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        let request = try makeRequest(url: url, payload: payload)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.networkError
        }

        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorObj = json["error"] as? [String: Any],
                let message = errorObj["message"] as? String
            {
                throw OpenAIError.apiError(message: message)
            }
            throw OpenAIError.serverError(statusCode: http.statusCode)
        }

        return data
    }
}

// MARK: - Responses DTOs

struct OpenAIResponsesRequest: Encodable {
    let model: String
    let input: [OpenAIResponseInput]
    let tools: [OpenAIResponsesTool]?
    let reasoning: OpenAIResponsesReasoning?
    let stream: Bool?
    let responseFormat: OpenAIResponseFormat?
}

/// Reasoning configuration for the Responses API.
struct OpenAIResponsesReasoning: Encodable {
    let summary: String?
}

/// Tool format for the Responses API (flattened structure with name at top level)
struct OpenAIResponsesTool: Encodable {
    let type: String
    let name: String
    let description: String?
    let parameters: [String: OpenAIJSONValue]?

    /// Convert from OpenAITool (Chat Completions format) to Responses format
    init(from tool: OpenAITool) {
        self.type = tool.type  // "function"
        self.name = tool.function.name
        self.description = tool.function.description
        self.parameters = tool.function.parameters
    }
}

struct OpenAIResponseInput: Encodable {
    let role: MessageRole
    let content: [OpenAIResponseContent]
}

enum OpenAIResponseContent: Encodable {
    case text(Text)
    case image(Image)
    case imageURL(ImageURL)

    struct Text: Codable {
        let type: String
        let text: String

        /// Creates a text content part with the correct type for the Responses API.
        /// - Parameters:
        ///   - text: The text content.
        ///   - role: The message role, determines whether type is `input_text` or `output_text`.
        init(text: String, role: MessageRole) {
            self.text = text
            switch role {
            case .user, .system, .tool:
                self.type = "input_text"
            case .assistant:
                self.type = "output_text"
            }
        }
    }

    struct Image: Codable {
        var type = "input_image"
        let base64: String
        let mimeType: String
    }

    struct ImageURL: Codable {
        var type = "input_image_url"
        let url: URL
    }

    enum CodingKeys: String, CodingKey { case type, text, base64, mimeType, url }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let payload):
            try container.encode(payload.type, forKey: .type)
            try container.encode(payload.text, forKey: .text)
        case .image(let payload):
            try container.encode(payload.type, forKey: .type)
            try container.encode(payload.base64, forKey: .base64)
            try container.encode(payload.mimeType, forKey: .mimeType)
        case .imageURL(let payload):
            try container.encode(payload.type, forKey: .type)
            try container.encode(payload.url, forKey: .url)
        }
    }
}

struct OpenAIResponseEnvelope: Codable {
    struct Output: Codable {
        let type: String?
        let text: String?
        let content: [ContentBlock]?

        var contentText: String? {
            content?.compactMap { $0.text }.joined(separator: "\n")
        }
    }

    struct ContentBlock: Codable {
        let type: String?
        let text: String?
    }

    let output: [Output]?
}

// MARK: - Models

// --- Models ---

/// A list of OpenAI models.
public struct OpenAIModelList: Decodable {
    /// The array of models.
    public let data: [OpenAIModel]
}

/// Represents an OpenAI model.
public struct OpenAIModel: Decodable, Identifiable {
    /// The model ID.
    public let id: String
    /// The object type (e.g., "model").
    public let object: String
    /// The creation timestamp.
    public let created: Int
    /// The owner of the model.
    public let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

/// Errors specific to OpenAI API.
public enum OpenAIError: Error {
    /// API returned an error message.
    case apiError(message: String)
    /// Network connectivity error.
    case networkError
    /// Server returned a status code error.
    case serverError(statusCode: Int)
}

// --- Chat ---

/// Request payload for chat completions.
public struct OpenAIChatRequest: Encodable {
    /// The model ID.
    let model: String
    /// The conversation messages.
    let messages: [OpenAIChatMessage]
    /// Sampling temperature.
    var temperature: Double? = nil
    /// Maximum tokens to generate.
    var maxTokens: Int? = nil
    /// Whether to stream the response.
    var stream: Bool? = nil
    /// Available tools.
    var tools: [OpenAITool]? = nil
    /// Tool choice configuration.
    var toolChoice: OpenAIToolChoice? = nil
    /// Response format configuration.
    var responseFormat: OpenAIResponseFormat? = nil
    /// Reasoning effort for o-series models.
    var reasoningEffort: String? = nil

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case reasoningEffort = "reasoning_effort"
    }
}

/// Represents a chat message.
public struct OpenAIChatMessage: Encodable {
    /// The role of the sender.
    public let role: String
    /// The content of the message.
    public let content: OpenAIContent
    /// Tool calls made by the model.
    public let toolCalls: [OpenAIToolCall]?
    /// The ID of the tool call this message responds to.
    public let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    /// Initializes a new message.
    public init(
        role: String, content: OpenAIContent, toolCalls: [OpenAIToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// The content of a chat message.
public enum OpenAIContent: Encodable {
    /// Text content.
    case text(String)
    /// Multipart content (text + images).
    case parts([OpenAIContentPart])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .parts(let p): try container.encode(p)
        }
    }
}

/// A part of a chat message content.
public struct OpenAIContentPart: Encodable {
    /// The type of part (e.g., "text", "image_url").
    public let type: String
    /// The text content.
    public let text: String?
    /// The image URL information.
    public let imageUrl: OpenAIImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    /// Creates a text part.
    public static func text(_ s: String) -> OpenAIContentPart {
        OpenAIContentPart(type: "text", text: s, imageUrl: nil)
    }

    /// Creates an image part from a URL.
    public static func image(url: String, detail: String? = "auto") -> OpenAIContentPart {
        OpenAIContentPart(
            type: "image_url", text: nil, imageUrl: OpenAIImageURL(url: url, detail: detail))
    }

    /// Creates an image part from base64 data.
    public static func image(base64: String, detail: String? = "auto") -> OpenAIContentPart {
        OpenAIContentPart(
            type: "image_url", text: nil,
            imageUrl: OpenAIImageURL(url: "data:image/jpeg;base64,\(base64)", detail: detail))
    }

    /// Creates an image part from base64 data with specific mime type.
    public static func image(base64: String, mimeType: String, detail: String? = "auto")
        -> OpenAIContentPart
    {
        OpenAIContentPart(
            type: "image_url", text: nil,
            imageUrl: OpenAIImageURL(url: "data:\(mimeType);base64,\(base64)", detail: detail))
    }
}

/// Represents an image URL.
public struct OpenAIImageURL: Encodable {
    /// The URL string.
    let url: String
    /// Detail level (e.g., "auto", "low", "high").
    var detail: String? = "auto"
}

/// Represents a tool available to the model.
public struct OpenAITool: Encodable {
    /// The type of tool (e.g., "function").
    let type: String
    /// The function definition.
    let function: OpenAIFunction
}

/// Defines a function for tool use.
public struct OpenAIFunction: Encodable {
    /// The name of the function.
    let name: String
    /// The description of the function.
    let description: String?
    /// The parameters schema.
    let parameters: [String: OpenAIJSONValue]?
}

// JSON value wrapper for OpenAI API (handles Any -> Encodable conversion)
/// A wrapper enum to handle untyped JSON values in a strongly typed way for Encodable conformance.
public enum OpenAIJSONValue: Encodable, Sendable {
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
    case array([OpenAIJSONValue])
    /// Object (dictionary) of values.
    case object([String: OpenAIJSONValue])

    /// Converts an `Any` value to `OpenAIJSONValue`.
    public static func from(_ value: Any) -> OpenAIJSONValue {
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

/// Specifies how tools should be chosen.
public enum OpenAIToolChoice: Encodable {
    /// Automatically choose tools.
    case auto
    /// Do not use any tools.
    case none
    /// Force tool use.
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

/// Specifies the format of the response.
public struct OpenAIResponseFormat: Encodable {
    /// The response format type (e.g., "text", "json_object").
    let type: String  // "text" or "json_object"
}

/// The response from a chat completion request.
public struct OpenAIChatResponse: Decodable {
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
        /// The reason for finishing.
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
        /// Tool calls made by the model.
        public let toolCalls: [OpenAIToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
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

/// A tool call within a response.
public struct OpenAIToolCall: Codable {
    /// The tool call ID.
    public let id: String
    /// The type of tool.
    public let type: String
    /// The function call details.
    public let function: FunctionCall

    /// The function call details.
    public struct FunctionCall: Codable {
        /// The function name.
        public let name: String
        /// The arguments string.
        public let arguments: String
    }
}

// --- Streaming ---

/// A chunk of a streamed response.
public struct OpenAIStreamChunk: Decodable {
    /// The chunk ID.
    public let id: String?
    /// The choices in this chunk.
    public let choices: [Choice]
    /// Usage statistics (optional, usually in last chunk).
    public let usage: OpenAIChatResponse.Usage?  // Sometimes in final chunk

    /// A choice in the stream chunk.
    public struct Choice: Decodable {
        /// The delta update for the message.
        public let delta: Delta
        /// The finish reason (if finished).
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
        public let toolCalls: [StreamToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    /// A tool call update in a stream.
    public struct StreamToolCall: Decodable {
        /// The index of the tool call.
        public let index: Int
        /// The ID of the tool call.
        public let id: String?
        /// The function update.
        public let function: StreamFunction?
    }

    /// A function update in a stream.
    public struct StreamFunction: Decodable {
        /// The name update.
        public let name: String?
        /// The arguments update.
        public let arguments: String?
    }
}

// --- Images ---

/// Request payload for image generation.
public struct OpenAIImageRequest: Encodable {
    /// The model ID.
    let model: String
    /// The image description.
    let prompt: String
    /// Number of images.
    let n: Int
    /// Image size.
    let size: String
    /// Response format.
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size
        case responseFormat = "response_format"
    }
}

/// Response for image generation.
public struct OpenAIImageResponse: Decodable {
    /// Creation timestamp.
    public let created: Int
    /// Array of generated data.
    public let data: [DataItem]

    /// Generated data item.
    public struct DataItem: Decodable {
        /// Image URL.
        public let url: String?
        /// Base64 JSON string.
        public let b64_json: String?
    }
}

// --- Audio ---

/// Request payload for speech generation.
public struct OpenAISpeechRequest: Encodable {
    /// The model ID.
    let model: String
    /// Text input.
    let input: String
    /// Voice ID.
    let voice: String
    /// Response format.
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model, input, voice
        case responseFormat = "response_format"
    }
}

/// Response for audio transcription.
public struct OpenAITranscriptionResponse: Decodable {
    /// Transcribed text.
    public let text: String
}

// --- Embeddings ---

/// Request payload for embeddings.
public struct OpenAIEmbeddingsRequest: Encodable {
    /// Input text array.
    let input: [String]
    /// Model ID.
    let model: String
    /// Embedding dimensions.
    let dimensions: Int?
}

/// Response for embeddings.
public struct OpenAIEmbeddingsResponse: Decodable {
    /// The embedding data.
    public let data: [Embedding]
    /// Usage statistics.
    public let usage: OpenAIChatResponse.Usage

    /// An embedding object.
    public struct Embedding: Decodable {
        /// The embedding vector.
        public let embedding: [Double]
        /// The index of the embedding.
        public let index: Int
    }
}
