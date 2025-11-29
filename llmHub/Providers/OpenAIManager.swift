import Foundation

/// A manager for OpenAI's API, handling Chat (Completions & Responses), Streaming, Vision, Audio, Images, Video, and Embeddings.
/// Designed for maximum flexibility and feature parity.
@available(iOS 26.1, macOS 26.1, *)
public class OpenAIManager {
    private let apiKey: String
    private let organizationID: String?
    private let session: URLSession
    
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    
    public init(apiKey: String, organizationID: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.session = session
    }
    
    // MARK: - Chat Completions
    
    public func chatCompletion(
        messages: [OpenAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [OpenAITool]? = nil,
        toolChoice: OpenAIToolChoice? = nil,
        responseFormat: OpenAIResponseFormat? = nil,
        reasoningEffort: String? = nil // "low", "medium", "high" for o-series
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
            Task {
                do {
                    var request = try makeRequest(url: url, payload: payload)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
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
                               let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) {
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
    
    // MARK: - Request Helper
    
    public func makeChatRequest(
        messages: [OpenAIChatMessage],
        model: String,
        stream: Bool,
        responseFormat: OpenAIResponseFormat? = nil
    ) throws -> URLRequest {
        let payload = OpenAIChatRequest(
            model: model,
            messages: messages,
            stream: stream,
            responseFormat: responseFormat
        )
        let url = baseURL.appendingPathComponent("chat/completions")
        return try makeRequest(url: url, payload: payload)
    }
    
    // MARK: - Images
    
    public func generateImage(
        prompt: String,
        model: String = "dall-e-3",
        n: Int = 1,
        size: String = "1024x1024",
        responseFormat: String = "url" // "url" or "b64_json"
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
    
    private func addHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let org = organizationID {
            request.setValue(org, forHTTPHeaderField: "OpenAI-Organization")
        }
    }
    
    private func makeRequest<T: Encodable>(url: URL, payload: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
    
    private func performRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        let request = try makeRequest(url: url, payload: payload)
        let (data, response) = try await session.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.networkError
        }
        
        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw OpenAIError.apiError(message: message)
            }
            throw OpenAIError.serverError(statusCode: http.statusCode)
        }
        
        return data
    }
}

// MARK: - Models

public enum OpenAIError: Error {
    case apiError(message: String)
    case networkError
    case serverError(statusCode: Int)
}

// --- Chat ---

public struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    var temperature: Double? = nil
    var maxTokens: Int? = nil
    var stream: Bool? = nil
    var tools: [OpenAITool]? = nil
    var toolChoice: OpenAIToolChoice? = nil
    var responseFormat: OpenAIResponseFormat? = nil
    var reasoningEffort: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case reasoningEffort = "reasoning_effort"
    }
}

public struct OpenAIChatMessage: Encodable {
    public let role: String
    public let content: OpenAIContent
    public let toolCalls: [OpenAIToolCall]?
    public let toolCallId: String?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
    
    public init(role: String, content: OpenAIContent, toolCalls: [OpenAIToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

public enum OpenAIContent: Encodable {
    case text(String)
    case parts([OpenAIContentPart])
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .parts(let p): try container.encode(p)
        }
    }
}

public struct OpenAIContentPart: Encodable {
    public let type: String
    public let text: String?
    public let imageUrl: OpenAIImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
    
    public static func text(_ s: String) -> OpenAIContentPart {
        OpenAIContentPart(type: "text", text: s, imageUrl: nil)
    }
    
    public static func image(url: String, detail: String? = "auto") -> OpenAIContentPart {
        OpenAIContentPart(type: "image_url", text: nil, imageUrl: OpenAIImageURL(url: url, detail: detail))
    }
    
    public static func image(base64: String, detail: String? = "auto") -> OpenAIContentPart {
        OpenAIContentPart(type: "image_url", text: nil, imageUrl: OpenAIImageURL(url: "data:image/jpeg;base64,\(base64)", detail: detail))
    }
}

public struct OpenAIImageURL: Encodable {
    let url: String
    var detail: String? = "auto"
}

public struct OpenAITool: Encodable {
    let type: String
    let function: OpenAIFunction
}

public struct OpenAIFunction: Encodable {
    let name: String
    let description: String?
    let parameters: [String: AnyEncodable]?
}

public enum OpenAIToolChoice: Encodable {
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

public struct OpenAIResponseFormat: Encodable {
    let type: String // "text" or "json_object"
}

public struct OpenAIChatResponse: Decodable {
    public let id: String
    public let choices: [Choice]
    public let usage: Usage?
    
    public struct Choice: Decodable {
        public let message: Message
        public let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    
    public struct Message: Decodable {
        public let role: String?
        public let content: String?
        public let toolCalls: [OpenAIToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }
    
    public struct Usage: Decodable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

public struct OpenAIToolCall: Codable {
    public let id: String
    public let type: String
    public let function: FunctionCall
    
    public struct FunctionCall: Codable {
        public let name: String
        public let arguments: String
    }
}

// --- Streaming ---

public struct OpenAIStreamChunk: Decodable {
    public let id: String?
    public let choices: [Choice]
    public let usage: OpenAIChatResponse.Usage? // Sometimes in final chunk
    
    public struct Choice: Decodable {
        public let delta: Delta
        public let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    
    public struct Delta: Decodable {
        public let role: String?
        public let content: String?
        public let toolCalls: [StreamToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }
    
    public struct StreamToolCall: Decodable {
        public let index: Int
        public let id: String?
        public let function: StreamFunction?
    }
    
    public struct StreamFunction: Decodable {
        public let name: String?
        public let arguments: String?
    }
}

// --- Images ---

public struct OpenAIImageRequest: Encodable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
    let responseFormat: String
    
    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size
        case responseFormat = "response_format"
    }
}

public struct OpenAIImageResponse: Decodable {
    public let created: Int
    public let data: [DataItem]
    
    public struct DataItem: Decodable {
        public let url: String?
        public let b64_json: String?
    }
}

// --- Audio ---

public struct OpenAISpeechRequest: Encodable {
    let model: String
    let input: String
    let voice: String
    let responseFormat: String
    
    enum CodingKeys: String, CodingKey {
        case model, input, voice
        case responseFormat = "response_format"
    }
}

public struct OpenAITranscriptionResponse: Decodable {
    public let text: String
}

// --- Embeddings ---

public struct OpenAIEmbeddingsRequest: Encodable {
    let input: [String]
    let model: String
    let dimensions: Int?
}

public struct OpenAIEmbeddingsResponse: Decodable {
    public let data: [Embedding]
    public let usage: OpenAIChatResponse.Usage
    
    public struct Embedding: Decodable {
        public let embedding: [Double]
        public let index: Int
    }
}

