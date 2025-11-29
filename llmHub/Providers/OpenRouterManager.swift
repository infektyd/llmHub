import Foundation

/// A manager for OpenRouter API, handling Chat, Streaming, and Multimodal inputs.
@available(iOS 26.1, macOS 26.1, *)
public class OpenRouterManager {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    
    // Optional app headers for OpenRouter
    private let appURL: String?
    private let appName: String?
    
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
    
    public func makeChatRequest(
        messages: [ORMessage],
        model: String,
        stream: Bool
    ) throws -> URLRequest {
        let payload = ORChatRequest(
            model: model,
            messages: messages,
            stream: stream
        )
        let url = baseURL.appendingPathComponent("chat/completions")
        return try makeRequest(url: url, payload: payload)
    }
    
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

public enum OpenRouterError: Error {
    case apiError(message: String)
    case networkError
    case serverError(statusCode: Int)
}

// --- Requests ---

public struct ORChatRequest: Encodable {
    let model: String
    let messages: [ORMessage]
    var temperature: Double? = nil
    var maxTokens: Int? = nil
    var stream: Bool? = nil
    var transforms: [String]? = nil
    var route: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, transforms, route
        case maxTokens = "max_tokens"
    }
}

public struct ORMessage: Encodable {
    public let role: String
    public let content: ORContent
    
    public init(role: String, content: ORContent) {
        self.role = role
        self.content = content
    }
}

public enum ORContent: Encodable {
    case text(String)
    case parts([ORContentPart])
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .parts(let p): try container.encode(p)
        }
    }
}

public struct ORContentPart: Encodable {
    public let type: String
    public let text: String?
    public let imageUrl: ORImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
    
    public static func text(_ s: String) -> ORContentPart {
        ORContentPart(type: "text", text: s, imageUrl: nil)
    }
    
    public static func image(url: String) -> ORContentPart {
        ORContentPart(type: "image_url", text: nil, imageUrl: ORImageURL(url: url))
    }
    
    public static func image(base64: String, mimeType: String = "image/jpeg") -> ORContentPart {
        ORContentPart(type: "image_url", text: nil, imageUrl: ORImageURL(url: "data:\(mimeType);base64,\(base64)"))
    }
}

public struct ORImageURL: Encodable {
    let url: String
}

// --- Responses ---

public struct ORChatResponse: Decodable {
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

public struct ORStreamChunk: Decodable {
    public let id: String
    public let choices: [Choice]
    public let usage: ORChatResponse.Usage? // Sometimes available in stream
    
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

// --- Models List ---

public struct ORModelInfo: Decodable {
    public let id: String
    public let name: String
    public let pricing: Pricing?
    
    public struct Pricing: Decodable {
        public let prompt: String
        public let completion: String
    }
}

