import Foundation

/// A manager for Mistral AI's API, handling Chat, Vision, Audio, FIM, OCR, and Embeddings.
@available(iOS 26.1, macOS 26.1, *)
public class MistralManager {
    private let apiKey: String
    private let session: URLSession
    
    private let primaryURL = URL(string: "https://api.mistral.ai/v1")!
    private let codestralURL = URL(string: "https://codestral.mistral.ai/v1")!
    
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    // MARK: - Chat Completions
    
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
    
    // MARK: - Helper Request Builder
    
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
    
    private func makeRequest<T: Encodable>(url: URL, payload: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
    
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

public enum MistralError: Error {
    case apiError(message: String)
    case networkError
    case serverError(statusCode: Int)
}

// --- Chat ---

public struct MistralChatRequest: Encodable {
    let model: String
    let messages: [MistralMessage]
    var temperature: Double?
    var maxTokens: Int?
    var stream: Bool?
    var tools: [MistralTool]?
    var toolChoice: MistralToolChoice?
    var responseFormat: MistralResponseFormat?
    var promptMode: String? // "reasoning"
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case promptMode = "prompt_mode"
    }
}

public struct MistralMessage: Encodable {
    public let role: String
    public let content: MistralContent
    
    public init(role: String, content: MistralContent) {
        self.role = role
        self.content = content
    }
}

public enum MistralContent: Encodable {
    case text(String)
    case parts([MistralContentPart])
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .parts(let p): try container.encode(p)
        }
    }
}

public struct MistralContentPart: Encodable {
    public let type: String
    public let text: String?
    public let imageUrl: MistralImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
    
    public static func text(_ s: String) -> MistralContentPart {
        MistralContentPart(type: "text", text: s, imageUrl: nil)
    }
    
    public static func image(base64: String) -> MistralContentPart {
        MistralContentPart(type: "image_url", text: nil, imageUrl: MistralImageURL(url: "data:image/jpeg;base64,\(base64)"))
    }
}

public struct MistralImageURL: Encodable {
    let url: String
}

public struct MistralTool: Encodable {
    let type: String
    let function: MistralFunction
}

public struct MistralFunction: Encodable {
    let name: String
    let description: String?
    let parameters: [String: AnyEncodable]?
}

public enum MistralToolChoice: Encodable {
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

public struct MistralResponseFormat: Encodable {
    let type: String
}

public struct MistralChatResponse: Decodable {
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
        public let toolCalls: [ToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
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

// --- Streaming ---

public struct MistralStreamChunk: Decodable {
    public let id: String
    public let choices: [Choice]
    public let usage: MistralChatResponse.Usage?
    
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
    }
}

// --- FIM ---

public struct MistralFIMRequest: Encodable {
    let model: String
    let prompt: String
    let suffix: String?
    let temperature: Double?
}

public struct MistralFIMResponse: Decodable {
    public let id: String
    public let choices: [Choice]
    
    public struct Choice: Decodable {
        public let message: Message
    }
    public struct Message: Decodable {
        public let content: String
    }
}

// --- OCR ---

public struct MistralOCRRequest: Encodable {
    let model: String
    let document: MistralOCRDocument
    let includeImageBase64: Bool?
    
    enum CodingKeys: String, CodingKey {
        case model, document
        case includeImageBase64 = "include_image_base64"
    }
}

public struct MistralOCRDocument: Encodable {
    let type: String
    let documentUrl: String?
    let imageUrl: MistralImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type
        case documentUrl = "document_url"
        case imageUrl = "image_url"
    }
    
    public static func url(_ url: String) -> MistralOCRDocument {
        MistralOCRDocument(type: "document_url", documentUrl: url, imageUrl: nil)
    }
    
    public static func imageUrl(_ url: String) -> MistralOCRDocument {
        MistralOCRDocument(type: "image_url", documentUrl: nil, imageUrl: MistralImageURL(url: url))
    }
    
    public static func imageBase64(_ base64: String) -> MistralOCRDocument {
        MistralOCRDocument(type: "image_url", documentUrl: nil, imageUrl: MistralImageURL(url: "data:image/jpeg;base64,\(base64)"))
    }
}

public struct MistralOCRResponse: Decodable {
    public let pages: [Page]
    
    public struct Page: Decodable {
        public let index: Int
        public let markdown: String
        public let images: [Image]?
    }
    
    public struct Image: Decodable {
        public let id: String
        public let imageBase64: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case imageBase64 = "image_base64"
        }
    }
}

// --- Audio ---

public struct MistralTranscriptionResponse: Decodable {
    public let text: String
}

