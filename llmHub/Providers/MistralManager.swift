import Foundation

/// A manager for Mistral AI's API, handling Chat, Vision, Audio, FIM, OCR, and Embeddings.
@available(iOS 26.1, macOS 26.1, *)
public class MistralManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The URLSession used for network requests.
    private let session: URLSession
    
    /// The primary base URL for Mistral API.
    private let primaryURL = URL(string: "https://api.mistral.ai/v1")!
    /// The base URL for Codestral API.
    private let codestralURL = URL(string: "https://codestral.mistral.ai/v1")!
    
    /// Initializes a new `MistralManager`.
    /// - Parameters:
    ///   - apiKey: The API key.
    ///   - session: The URLSession (default: `.shared`).
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    // MARK: - Chat Completions
    
    /// Sends a chat completion request to Mistral.
    /// - Parameters:
    ///   - messages: The conversation history.
    ///   - model: The model identifier.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - stream: Whether to stream responses (default: false).
    ///   - tools: Available tools (optional).
    ///   - toolChoice: Tool choice strategy (optional).
    ///   - responseFormat: The desired response format (optional).
    ///   - promptMode: Special prompt mode (e.g., "reasoning").
    /// - Returns: A `MistralChatResponse`.
    public func chatCompletion(
        messages: [MistralMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [MistralTool]? = nil,
        toolChoice: MistralToolChoice? = nil,
        responseFormat: MistralResponseFormat? = nil,
        promptMode: String? = nil // "reasoning" for Magistral
    ) async throws -> MistralChatResponse {
        let requestPayload = MistralChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: stream,
            tools: tools,
            toolChoice: toolChoice,
            responseFormat: responseFormat,
            promptMode: promptMode
        )
        
        let url = primaryURL.appendingPathComponent("chat/completions")
        let data = try await performRequest(url: url, payload: requestPayload)
        return try JSONDecoder().decode(MistralChatResponse.self, from: data)
    }
    
    /// Streams chat completion chunks from Mistral.
    /// - Parameters:
    ///   - messages: The conversation history.
    ///   - model: The model identifier.
    ///   - temperature: Sampling temperature (optional).
    ///   - maxTokens: Max tokens to generate (optional).
    ///   - tools: Available tools (optional).
    ///   - toolChoice: Tool choice strategy (optional).
    /// - Returns: An async throwing stream of `MistralStreamChunk`.
    public func streamChatCompletion(
        messages: [MistralMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        tools: [MistralTool]? = nil,
        toolChoice: MistralToolChoice? = nil
    ) -> AsyncThrowingStream<MistralStreamChunk, Error> {
        let requestPayload = MistralChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: true,
            tools: tools,
            toolChoice: toolChoice
        )
        
        let url = primaryURL.appendingPathComponent("chat/completions")
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = try makeRequest(url: url, payload: requestPayload)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        var errorText = ""
                        for try await line in bytes.lines { errorText += line }
                        throw MistralError.apiError(message: errorText)
                    }
                    
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let json = String(trimmed.dropFirst(6))
                            if json == "[DONE]" { break }
                            
                            if let data = json.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(MistralStreamChunk.self, from: data) {
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
    
    // MARK: - Models List
    
    /// Lists available models from Mistral.
    /// - Returns: A `MistralModelList` containing model details.
    public func listModels() async throws -> MistralModelList {
        let url = primaryURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MistralError.networkError
        }
        
        return try JSONDecoder().decode(MistralModelList.self, from: data)
    }
    
    // MARK: - Helper Request Builder
    
    /// Creates a chat request.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - model: Model ID.
    ///   - stream: Streaming flag.
    /// - Returns: A configured `URLRequest`.
    public func makeChatRequest(
        messages: [MistralMessage],
        model: String,
        stream: Bool
    ) throws -> URLRequest {
        let payload = MistralChatRequest(
            model: model,
            messages: messages,
            stream: stream
        )
        let url = primaryURL.appendingPathComponent("chat/completions")
        return try makeRequest(url: url, payload: payload)
    }
    
    // MARK: - FIM (Fill-in-the-Middle)
    
    /// Performs a Fill-In-the-Middle completion (Codestral).
    /// - Parameters:
    ///   - model: Model ID (default: "codestral-latest").
    ///   - prompt: The preceding code.
    ///   - suffix: The succeeding code (optional).
    ///   - temperature: Sampling temperature (optional).
    /// - Returns: A `MistralFIMResponse`.
    public func fimCompletion(
        model: String = "codestral-latest",
        prompt: String,
        suffix: String? = nil,
        temperature: Double? = nil
    ) async throws -> MistralFIMResponse {
        let payload = MistralFIMRequest(
            model: model,
            prompt: prompt,
            suffix: suffix,
            temperature: temperature
        )
        let url = codestralURL.appendingPathComponent("fim/completions")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(MistralFIMResponse.self, from: data)
    }
    
    // MARK: - OCR
    
    /// Performs Optical Character Recognition on a document.
    /// - Parameters:
    ///   - document: The document to process.
    ///   - model: Model ID (default: "mistral-ocr-latest").
    ///   - includeImageBase64: Whether to include base64 images in response (optional).
    /// - Returns: A `MistralOCRResponse`.
    public func ocr(
        document: MistralOCRDocument,
        model: String = "mistral-ocr-latest",
        includeImageBase64: Bool? = nil
    ) async throws -> MistralOCRResponse {
        let payload = MistralOCRRequest(
            model: model,
            document: document,
            includeImageBase64: includeImageBase64
        )
        let url = primaryURL.appendingPathComponent("ocr")
        let data = try await performRequest(url: url, payload: payload)
        return try JSONDecoder().decode(MistralOCRResponse.self, from: data)
    }
    
    // MARK: - Audio Transcription
    
    /// Transcribes an audio file.
    /// - Parameters:
    ///   - file: The audio file data.
    ///   - fileName: The name of the file.
    ///   - model: Model ID (default: "voxtral-mini-latest").
    ///   - language: Language code (optional).
    /// - Returns: A `MistralTranscriptionResponse`.
    public func transcribe(
        file: Data,
        fileName: String,
        model: String = "voxtral-mini-latest",
        language: String? = nil
    ) async throws -> MistralTranscriptionResponse {
        let url = primaryURL.appendingPathComponent("audio/transcriptions")
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField("model", model)
        if let lang = language { appendField("language", lang) }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(file)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MistralError.networkError }
        
        if !(200...299).contains(http.statusCode) {
            throw MistralError.serverError(statusCode: http.statusCode)
        }
        
        return try JSONDecoder().decode(MistralTranscriptionResponse.self, from: data)
    }
    
    // MARK: - Private Helpers
    
    /// Helper to create a generic JSON request.
    private func makeRequest<T: Encodable>(url: URL, payload: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
    
    /// Helper to perform a request and return data, handling errors.
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        let request = try makeRequest(url: url, payload: payload)
        let (data, response) = try await session.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw MistralError.networkError
        }
        
        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw MistralError.apiError(message: message)
            }
            throw MistralError.serverError(statusCode: http.statusCode)
        }
        
        return data
    }
}

// MARK: - Models

// --- Models List ---

/// A list of Mistral models.
public struct MistralModelList: Decodable {
    /// The array of models.
    public let data: [MistralModel]
}

/// Represents a Mistral model.
public struct MistralModel: Decodable {
    /// The model ID.
    public let id: String
    /// The object type (e.g., "model").
    public let object: String
}

/// Errors specific to Mistral API.
public enum MistralError: Error {
    /// API returned an error message.
    case apiError(message: String)
    /// Network connectivity error.
    case networkError
    /// Server returned a status code error.
    case serverError(statusCode: Int)
}

// --- Chat ---

/// Request payload for chat completions.
public struct MistralChatRequest: Encodable {
    /// The model ID.
    let model: String
    /// The conversation messages.
    let messages: [MistralMessage]
    /// Sampling temperature.
    var temperature: Double?
    /// Maximum tokens to generate.
    var maxTokens: Int?
    /// Whether to stream the response.
    var stream: Bool?
    /// Available tools.
    var tools: [MistralTool]?
    /// Tool choice configuration.
    var toolChoice: MistralToolChoice?
    /// Response format configuration.
    var responseFormat: MistralResponseFormat?
    /// Prompt mode (e.g., "reasoning").
    var promptMode: String? // "reasoning"
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case promptMode = "prompt_mode"
    }
}

/// Represents a chat message.
public struct MistralMessage: Encodable {
    /// The role of the sender.
    public let role: String
    /// The content of the message.
    public let content: MistralContent
    
    /// Initializes a new message.
    public init(role: String, content: MistralContent) {
        self.role = role
        self.content = content
    }
}

/// The content of a chat message.
public enum MistralContent: Encodable {
    /// Text content.
    case text(String)
    /// Multipart content (text + images).
    case parts([MistralContentPart])
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .parts(let p): try container.encode(p)
        }
    }
}

/// A part of a chat message content.
public struct MistralContentPart: Encodable {
    /// The type of the part (e.g., "text", "image_url").
    public let type: String
    /// The text content.
    public let text: String?
    /// The image URL information.
    public let imageUrl: MistralImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
    
    /// Creates a text part.
    public static func text(_ s: String) -> MistralContentPart {
        MistralContentPart(type: "text", text: s, imageUrl: nil)
    }
    
    /// Creates an image part from base64 data.
    public static func image(base64: String) -> MistralContentPart {
        MistralContentPart(type: "image_url", text: nil, imageUrl: MistralImageURL(url: "data:image/jpeg;base64,\(base64)"))
    }
}

/// Represents an image URL.
public struct MistralImageURL: Encodable {
    /// The URL string.
    let url: String
}

/// Represents a tool available to the model.
public struct MistralTool: Encodable {
    /// The type of tool (e.g., "function").
    let type: String
    /// The function definition.
    let function: MistralFunction
}

/// Defines a function for tool use.
public struct MistralFunction: Encodable {
    /// The name of the function.
    let name: String
    /// The description of the function.
    let description: String?
    /// The parameters schema.
    let parameters: [String: AnyEncodable]?
}

/// Specifies how tools should be chosen.
public enum MistralToolChoice: Encodable {
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
public struct MistralResponseFormat: Encodable {
    /// The response format type (e.g., "json_object").
    let type: String
}

/// The response from a chat completion request.
public struct MistralChatResponse: Decodable {
    /// The response ID.
    public let id: String
    /// The generated choices.
    public let choices: [Choice]
    /// Token usage statistics.
    public let usage: Usage?
    
    /// A single choice in the response.
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
        public let toolCalls: [ToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }
    
    /// A call to a tool.
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
public struct MistralStreamChunk: Decodable {
    /// The chunk ID.
    public let id: String
    /// The choices in this chunk.
    public let choices: [Choice]
    /// Usage statistics (optional, usually in last chunk).
    public let usage: MistralChatResponse.Usage?
    
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

// --- FIM ---

/// Request payload for FIM completion.
public struct MistralFIMRequest: Encodable {
    /// The model ID.
    let model: String
    /// The preceding code.
    let prompt: String
    /// The succeeding code.
    let suffix: String?
    /// Sampling temperature.
    let temperature: Double?
}

/// Response for FIM completion.
public struct MistralFIMResponse: Decodable {
    /// The response ID.
    public let id: String
    /// The generated choices.
    public let choices: [Choice]
    
    /// A choice in the response.
    public struct Choice: Decodable {
        /// The generated message.
        public let message: Message
    }
    /// The message in a choice.
    public struct Message: Decodable {
        /// The content string.
        public let content: String
    }
}

// --- OCR ---

/// Request payload for OCR.
public struct MistralOCRRequest: Encodable {
    /// The model ID.
    let model: String
    /// The document to process.
    let document: MistralOCRDocument
    /// Whether to include image base64.
    let includeImageBase64: Bool?
    
    enum CodingKeys: String, CodingKey {
        case model, document
        case includeImageBase64 = "include_image_base64"
    }
}

/// Represents a document for OCR.
public struct MistralOCRDocument: Encodable {
    /// The type of document source (e.g., "document_url").
    let type: String
    /// The document URL.
    let documentUrl: String?
    /// The image URL.
    let imageUrl: MistralImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type
        case documentUrl = "document_url"
        case imageUrl = "image_url"
    }
    
    /// Creates a document from a URL.
    public static func url(_ url: String) -> MistralOCRDocument {
        MistralOCRDocument(type: "document_url", documentUrl: url, imageUrl: nil)
    }
    
    /// Creates a document from an image URL.
    public static func imageUrl(_ url: String) -> MistralOCRDocument {
        MistralOCRDocument(type: "image_url", documentUrl: nil, imageUrl: MistralImageURL(url: url))
    }
    
    /// Creates a document from base64 image data.
    public static func imageBase64(_ base64: String) -> MistralOCRDocument {
        MistralOCRDocument(type: "image_url", documentUrl: nil, imageUrl: MistralImageURL(url: "data:image/jpeg;base64,\(base64)"))
    }
}

/// Response for OCR.
public struct MistralOCRResponse: Decodable {
    /// The processed pages.
    public let pages: [Page]
    
    /// A page in the document.
    public struct Page: Decodable {
        /// The page index.
        public let index: Int
        /// The markdown content of the page.
        public let markdown: String
        /// Extracted images.
        public let images: [Image]?
    }
    
    /// An extracted image.
    public struct Image: Decodable {
        /// The image ID.
        public let id: String
        /// The base64 data of the image.
        public let imageBase64: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case imageBase64 = "image_base64"
        }
    }
}

// --- Audio ---

/// Response for audio transcription.
public struct MistralTranscriptionResponse: Decodable {
    /// The transcribed text.
    public let text: String
}
