import Foundation

/// A manager for Anthropic's Claude API, handling Chat, Streaming, and Files.
@available(iOS 26.1, macOS 26.1, *)
public class AnthropicManager {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private let version = "2023-06-01"
    
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    // MARK: - Chat
    
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
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
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
                            if let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) {
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
    
    public func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        // Typically POST /v1/files (Beta)
        // Note: Check if endpoint is strictly /v1/files or /v1/messages/files.
        // Assuming standard /v1/files for beta.
        let url = baseURL.appendingPathComponent("files") // Verify endpoint
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        // Beta headers
        request.setValue("files-2025-04-14", forHTTPHeaderField: "anthropic-beta") // Hypothetical beta header from previous code
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
             throw AnthropicError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        struct FileResp: Decodable { let id: String }
        return try JSONDecoder().decode(FileResp.self, from: responseData).id
    }
    
    // MARK: - Helpers
    
    public func makeChatRequest(
        messages: [AnthropicMessage],
        model: String,
        maxTokens: Int,
        stream: Bool,
        tools: [AnthropicTool]? = nil
    ) throws -> URLRequest {
        let payload = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            messages: messages,
            stream: stream,
            system: nil,
            tools: tools,
            thinking: nil
        )
        return try makeRequest(url: baseURL.appendingPathComponent("messages"), payload: payload)
    }
    
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

public enum AnthropicError: Error {
    case apiError(message: String)
    case networkError
    case serverError(statusCode: Int)
}

public struct AnthropicMessagesRequest: Encodable {
    public let model: String
    public let max_tokens: Int
    public let messages: [AnthropicMessage]
    public let stream: Bool
    public let system: String?
    public let tools: [AnthropicTool]?
    public let thinking: AnthropicThinkingConfig?
}

public struct AnthropicThinkingConfig: Encodable {
    public let type: String
    public let budget_tokens: Int
}

public struct AnthropicTool: Encodable {
    public let name: String
    public let description: String?
    public let input_schema: AnthropicJSONValue?
    
    public init(name: String, description: String?, inputSchema: [String: Any]?) {
        self.name = name
        self.description = description
        self.input_schema = inputSchema.map { AnthropicJSONValue.from($0) }
    }
}

// JSON value wrapper for Anthropic API (handles Any -> Encodable conversion)
public enum AnthropicJSONValue: Encodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnthropicJSONValue])
    case object([String: AnthropicJSONValue])
    
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
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let dict):
            try container.encode(dict)
        }
    }
}

public struct AnthropicMessage: Encodable {
    public let role: String
    public let content: [AnthropicContentBlock]
    
    public init(role: String, content: [AnthropicContentBlock]) {
        self.role = role
        self.content = content
    }
}

public enum AnthropicContentBlock: Encodable {
    case text(AnthropicTextBlock)
    case image(AnthropicImageSource)
    case toolUse(AnthropicToolUse)
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

public struct AnthropicToolUse: Encodable {
    public let type: String = "tool_use"
    public let id: String
    public let name: String
    public let input: AnthropicJSONValue
    
    public init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name
        self.input = .object(input.mapValues { AnthropicJSONValue.from($0) })
    }
}

public struct AnthropicToolResult: Encodable {
    public let tool_use_id: String
    public let content: String
    
    public init(tool_use_id: String, content: String) {
        self.tool_use_id = tool_use_id
        self.content = content
    }
}

public struct AnthropicTextBlock: Encodable {
    public let type: String = "text"
    public let text: String
    public let cache_control: AnthropicCacheControl?
    
    public init(text: String, cacheControl: AnthropicCacheControl? = nil) {
        self.text = text
        self.cache_control = cacheControl
    }
}

public struct AnthropicCacheControl: Encodable {
    public let type: String
    public init(type: String = "ephemeral") { self.type = type }
}

public struct AnthropicImageSource: Encodable {
    public let type: String // "base64"
    public let media_type: String
    public let data: String
    
    public init(type: String = "base64", media_type: String, data: String) {
        self.type = type
        self.media_type = media_type
        self.data = data
    }
}

public struct AnthropicMessageResponse: Decodable {
    public let id: String
    public let content: [AnthropicResponseContent]
    public let usage: Usage
    
    public struct Usage: Decodable {
        public let input_tokens: Int
        public let output_tokens: Int
    }
}

public enum AnthropicResponseContent: Decodable {
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

public struct AnthropicResponseText: Decodable {
    public let type: String
    public let text: String
}

// SSE Events
public struct AnthropicStreamEvent: Decodable {
    public let type: String
    public let delta: AnthropicStreamDelta?
    public let usage: AnthropicMessageResponse.Usage?
    public let content_block: AnthropicStreamContentBlock?
    public let index: Int?
}

public struct AnthropicStreamContentBlock: Decodable {
    public let type: String
    public let id: String?
    public let name: String?
}

public struct AnthropicStreamDelta: Decodable {
    public let type: String?
    public let text: String?
    public let thinking: String?
    public let partial_json: String?
}

