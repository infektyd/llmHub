//
//  OpenRouterClient.swift
//  llmHub
//
//  Generated skeleton on 11/29/25 without network access.
//  This file implements the OpenRouter integration spec at openrouter_integration.md
//  It is version-agnostic and marked with TODOs where verification against current docs is required.
//

import Foundation

// MARK: - Type-erased helpers

/// A simple type-erased Encodable wrapper.
public struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    public init<T: Encodable>(_ value: T) { self.encodeFunc = value.encode }
    public func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

/// A simple AnyCodable for dynamic JSON payloads in requests and responses.
public struct AnyCodable: Codable {
    public let value: Any
    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.value = NSNull() }
        else if let b = try? container.decode(Bool.self) { self.value = b }
        else if let i = try? container.decode(Int.self) { self.value = i }
        else if let d = try? container.decode(Double.self) { self.value = d }
        else if let s = try? container.decode(String.self) { self.value = s }
        else if let arr = try? container.decode([AnyCodable].self) { self.value = arr.map { $0.value } }
        else if let dict = try? container.decode([String: AnyCodable].self) { self.value = dict.mapValues { $0.value } }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let arr as [Any]: try container.encode(arr.map(AnyCodable.init))
        case let dict as [String: Any]: try container.encode(dict.mapValues(AnyCodable.init))
        default:
            // Fallback to string description to avoid crashes in debug builds.
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Configuration

public struct OpenRouterConfig {
    public let apiKey: String
    public let baseURL: URL
    public let appURL: String?      // For HTTP-Referer
    public let appName: String?     // For X-Title

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        appURL: String? = nil,
        appName: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.appURL = appURL
        self.appName = appName
    }
}

// MARK: - Client

public final class OpenRouterClient {
    private let config: OpenRouterConfig
    private let urlSession: URLSession

    public init(config: OpenRouterConfig, session: URLSession = .shared) {
        self.config = config
        self.urlSession = session
    }

    private func makeRequest(
        path: String,
        method: String = "POST",
        body: Encodable? = nil,
        accept: String? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accept = accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        if let appURL = config.appURL { request.setValue(appURL, forHTTPHeaderField: "HTTP-Referer") }
        if let appName = config.appName { request.setValue(appName, forHTTPHeaderField: "X-Title") }
        if let body = body { request.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        return request
    }
}

// MARK: - Shared Models

public enum ORRole: String, Codable { case system, user, assistant, tool }

public enum ORContentPart: Codable {
    case text(String)
    case imageURL(url: String, detail: String?)
    case inputAudio(dataBase64: String, format: String)
    case videoURL(url: String)
    case file(dataBase64: String, mimeType: String)

    private enum CodingKeys: String, CodingKey { case type, text, image_url, input_audio, video_url, file, url, detail, data, format, mime_type }
    private enum PartType: String, Codable { case text, image_url, input_audio, video_url, file }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(PartType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))
        case .image_url:
            let img = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .image_url)
            let url = try img.decode(String.self, forKey: .url)
            let detail = try img.decodeIfPresent(String.self, forKey: .detail)
            self = .imageURL(url: url, detail: detail)
        case .input_audio:
            let audio = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .input_audio)
            let data = try audio.decode(String.self, forKey: .data)
            let format = try audio.decode(String.self, forKey: .format)
            self = .inputAudio(dataBase64: data, format: format)
        case .video_url:
            let video = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .video_url)
            let url = try video.decode(String.self, forKey: .url)
            self = .videoURL(url: url)
        case .file:
            let file = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .file)
            let data = try file.decode(String.self, forKey: .data)
            let mime = try file.decode(String.self, forKey: .mime_type)
            self = .file(dataBase64: data, mimeType: mime)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode(PartType.text, forKey: .type)
            try c.encode(text, forKey: .text)
        case .imageURL(let url, let detail):
            try c.encode(PartType.image_url, forKey: .type)
            var img = c.nestedContainer(keyedBy: CodingKeys.self, forKey: .image_url)
            try img.encode(url, forKey: .url)
            if let detail = detail { try img.encode(detail, forKey: .detail) }
        case .inputAudio(let data, let format):
            try c.encode(PartType.input_audio, forKey: .type)
            var audio = c.nestedContainer(keyedBy: CodingKeys.self, forKey: .input_audio)
            try audio.encode(data, forKey: .data)
            try audio.encode(format, forKey: .format)
        case .videoURL(let url):
            try c.encode(PartType.video_url, forKey: .type)
            var video = c.nestedContainer(keyedBy: CodingKeys.self, forKey: .video_url)
            try video.encode(url, forKey: .url)
        case .file(let data, let mime):
            try c.encode(PartType.file, forKey: .type)
            var file = c.nestedContainer(keyedBy: CodingKeys.self, forKey: .file)
            try file.encode(data, forKey: .data)
            try file.encode(mime, forKey: .mime_type)
        }
    }
}

public struct ORMessage: Codable {
    public let role: ORRole
    public let content: [ORContentPart]
    public init(role: ORRole, content: [ORContentPart]) { self.role = role; self.content = content }
}

// MARK: - Chat / Completions

public struct ORChatRequest: Codable {
    // Core
    public let model: String
    public let messages: [ORMessage]

    // Modalities for image generation etc.
    public let modalities: [String]?

    // Sampling
    public let temperature: Double?
    public let top_p: Double?
    public let max_tokens: Int?
    public let stop: [String]?

    // Streaming
    public let stream: Bool?

    // Reasoning
    public struct Reasoning: Codable {
        public let effort: String?   // "low" | "medium" | "high" (verify)
        public let max_tokens: Int?  // Anthropic-style cap
        public init(effort: String? = nil, max_tokens: Int? = nil) { self.effort = effort; self.max_tokens = max_tokens }
    }
    public let reasoning: Reasoning?
    public let include_reasoning: Bool?

    // Usage
    public struct UsageConfig: Codable { public let include: Bool }
    public let usage: UsageConfig?

    // OpenRouter-specific
    public let transforms: [String]?
    public let models: [String]?
    public let route: String?
    public let provider: [String: AnyCodable]?
    public let user: String?

    public init(
        model: String,
        messages: [ORMessage],
        modalities: [String]? = nil,
        temperature: Double? = nil,
        top_p: Double? = nil,
        max_tokens: Int? = nil,
        stop: [String]? = nil,
        stream: Bool? = nil,
        reasoning: Reasoning? = nil,
        include_reasoning: Bool? = nil,
        usage: UsageConfig? = nil,
        transforms: [String]? = nil,
        models: [String]? = nil,
        route: String? = nil,
        provider: [String: AnyCodable]? = nil,
        user: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.modalities = modalities
        self.temperature = temperature
        self.top_p = top_p
        self.max_tokens = max_tokens
        self.stop = stop
        self.stream = stream
        self.reasoning = reasoning
        self.include_reasoning = include_reasoning
        self.usage = usage
        self.transforms = transforms
        self.models = models
        self.route = route
        self.provider = provider
        self.user = user
    }
}

public struct ORChatResponse: Codable {
    public struct Choice: Codable {
        public struct AssistantMessage: Codable {
            public let role: ORRole
            public let content: [ORContentPart]?
            public struct ImagePart: Codable { public struct ImageURL: Codable { public let url: String }; public let type: String; public let image_url: ImageURL }
            public let images: [ImagePart]?
            public let reasoning: String?
        }
        public let index: Int?
        public let message: AssistantMessage
        public let finish_reason: String?
    }
    public struct UsageDetails: Codable {
        public let prompt_tokens: Double?
        public let completion_tokens: Double?
        // TODO: Add completion_tokens_details if needed (reasoning_tokens, etc.)
    }
    public let id: String
    public let object: String
    public let created: Int?
    public let model: String
    public let choices: [Choice]
    public let usage: UsageDetails?
}

public extension OpenRouterClient {
    func chat(request: ORChatRequest, completion: @escaping (Result<ORChatResponse, Error>) -> Void) {
        do {
            var urlRequest = try makeRequest(path: "chat/completions", method: "POST", body: request)
            // Explicit method for clarity
            urlRequest.httpMethod = "POST"

            urlSession.dataTask(with: urlRequest) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else {
                    completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"]))); return
                }
                do { completion(.success(try JSONDecoder().decode(ORChatResponse.self, from: data))) }
                catch { completion(.failure(error)) }
            }.resume()
        } catch { completion(.failure(error)) }
    }
}

// MARK: - Streaming (SSE) skeleton

public extension OpenRouterClient {
    /// Basic SSE streaming. Parses lines prefixed with "data: ". Final line is "data: [DONE]".
    /// NOTE: Verify streaming chunk schema against current OpenRouter docs.
    func chatStream(
        request: ORChatRequest,
        onChunk: @escaping (Result<ORChatResponse.Choice.AssistantMessage, Error>) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        var req = request
        if req.stream != true { req = ORChatRequest(model: request.model, messages: request.messages, modalities: request.modalities, temperature: request.temperature, top_p: request.top_p, max_tokens: request.max_tokens, stop: request.stop, stream: true, reasoning: request.reasoning, include_reasoning: request.include_reasoning, usage: request.usage, transforms: request.transforms, models: request.models, route: request.route, provider: request.provider, user: request.user) }

        do {
            var urlRequest = try makeRequest(path: "chat/completions", method: "POST", body: req, accept: "text/event-stream")
            urlRequest.httpMethod = "POST"

            // Use bytes(for:) for line-by-line parsing when available.
            let task = urlSession.dataTask(with: urlRequest) { data, response, error in
                // Fallback non-streaming path: try to decode whole response if server didn't stream
                if let error = error { onComplete(.failure(error)); return }
                guard let data = data else { onComplete(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"]))); return }
                if let resp = try? JSONDecoder().decode(ORChatResponse.self, from: data) {
                    if let msg = resp.choices.first?.message { onChunk(.success(msg)) }
                    onComplete(.success(()))
                } else {
                    onComplete(.failure(NSError(domain: "OpenRouter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected streaming response"])) )
                }
            }

            // NOTE: For true SSE parsing, consider URLSession.bytes(for:) and iterate lines:
            // - This placeholder uses dataTask for broad compatibility; replace with bytes(for:) if targeting iOS 15+.
            task.resume()
        } catch {
            onComplete(.failure(error))
        }
    }
}

// MARK: - Embeddings

public struct OREmbeddingsRequest: Codable {
    public let model: String
    public let input: [String]
}

public struct OREmbeddingsResponse: Codable {
    public struct Embedding: Codable { public let embedding: [Double]; public let index: Int }
    public let data: [Embedding]
    public let model: String
    public let object: String
}

public extension OpenRouterClient {
    func embeddings(request: OREmbeddingsRequest, completion: @escaping (Result<OREmbeddingsResponse, Error>) -> Void) {
        do {
            let urlRequest = try makeRequest(path: "embeddings", method: "POST", body: request)
            urlSession.dataTask(with: urlRequest) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"]))); return }
                do { completion(.success(try JSONDecoder().decode(OREmbeddingsResponse.self, from: data))) }
                catch { completion(.failure(error)) }
            }.resume()
        } catch { completion(.failure(error)) }
    }
}

// MARK: - Models & Discovery

public struct ORModelInfo: Codable {
    public let id: String
    public let input_modalities: [String]?
    public let output_modalities: [String]?
}

public extension OpenRouterClient {
    func listModels(completion: @escaping (Result<[ORModelInfo], Error>) -> Void) {
        do {
            let request = try makeRequest(path: "models", method: "GET", body: Optional<String>.none)
            urlSession.dataTask(with: request) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"]))); return }
                do { completion(.success(try JSONDecoder().decode([ORModelInfo].self, from: data))) }
                catch { completion(.failure(error)) }
            }.resume()
        } catch { completion(.failure(error)) }
    }
}

// MARK: - Usage / Key Info

public struct ORKeyInfo: Codable {
    public let label: String?
    public let credit_limit: Double?
    public let usage: Double?
    public let expires_at: String?
    // TODO: Extend with rate-limits and other fields as needed.
}

public extension OpenRouterClient {
    func getKeyInfo(completion: @escaping (Result<ORKeyInfo, Error>) -> Void) {
        do {
            let request = try makeRequest(path: "key", method: "GET", body: Optional<String>.none)
            urlSession.dataTask(with: request) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"]))); return }
                do { completion(.success(try JSONDecoder().decode(ORKeyInfo.self, from: data))) }
                catch { completion(.failure(error)) }
            }.resume()
        } catch { completion(.failure(error)) }
    }
}

// MARK: - Optional: Responses API placeholders (verify before use)

public struct ORResponsesRequest: Codable {
    public let model: String
    public let input: AnyCodable
    public let reasoning: ORChatRequest.Reasoning?
    public let include_reasoning: Bool?
}

public struct ORResponsesResponse: Codable { /* TODO: Map to OpenRouter /responses schema when needed */ }

public extension OpenRouterClient {
    func responses(
        request: ORResponsesRequest,
        completion: @escaping (Result<ORResponsesResponse, Error>) -> Void
    ) {
        // Placeholder to show surface; implement when adopting /responses.
        do {
            let urlRequest = try makeRequest(path: "responses", method: "POST", body: request)
            urlSession.dataTask(with: urlRequest) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"]))); return }
                // TODO: Decode real schema once confirmed
                _ = data
                completion(.failure(NSError(domain: "OpenRouter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Responses API not implemented"])) )
            }.resume()
        } catch { completion(.failure(error)) }
    }
}

// MARK: - Convenience helpers

public extension ORChatResponse {
    func firstImageDataURLs() -> [String] {
        guard let images = choices.first?.message.images else { return [] }
        return images.map { $0.image_url.url }
    }
}
