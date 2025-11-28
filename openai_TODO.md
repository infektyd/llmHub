//
//  OpenAIClient.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//

import Foundation

// MARK: - OpenAI Configuration

public struct OpenAIConfig {
    public let apiKey: String
    public let organizationID: String?
    public let baseURL: URL

    public init(
        apiKey: String,
        organizationID: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1/")!
    ) {
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.baseURL = baseURL
    }
}


// MARK: - OpenAI Model Enum

public enum OpenAIModel: String {
    // General / non-reasoning
    case gpt5_1        = "gpt-5.1"          // flagship general model
    case gpt4_1        = "gpt-4.1"
    case gpt4_1_mini   = "gpt-4.1-mini"
    case gpt4o         = "gpt-4o"
    case gpt4o_mini    = "gpt-4o-mini"

    // Reasoning (thinking models)
    case o3_mini       = "o3-mini"

    // Image models
    case gpt_image     = "gpt-image-1"      // or current “GPT Image” model

    // Audio models (if separate name is required in requests)
    case whisper       = "whisper-1"

    // Video
    case sora2_pro     = "sora-2-pro"       // video generation

    // Embeddings
    case textEmbedding = "text-embedding-3-large"
}


// MARK: - OpenAI Errors

public enum OpenAIError: Error {
    case httpError(Int, data: Data?)
    case decodingError(Error)
    case unknown(Error)
}


// MARK: - OpenAI Client

public final class OpenAIClient {
    private let config: OpenAIConfig
    private let urlSession: URLSession

    public init(config: OpenAIConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    private func makeRequest(
        path: String,
        method: String = "POST",
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        var url = config.baseURL.appendingPathComponent(path)
        if let queryItems = queryItems, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            url = components.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        if let orgId = config.organizationID {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        method: String = "POST",
        body: Request
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw OpenAIError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                data: data
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenAIError.decodingError(error)
        }
    }
}


// MARK: - Chat / Text / Tools

public extension OpenAIClient {
    struct ChatMessage: Encodable {
        public enum Role: String, Encodable {
            case system, user, assistant, tool
        }

        public let role: Role
        public let content: String

        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    struct ChatRequest: Encodable {
        public let model: String
        public let messages: [ChatMessage]

        // Optional params can be added here, e.g., temperature, max_tokens, tools, tool_choice, response_format, etc.
        public init(model: String, messages: [ChatMessage]) {
            self.model = model
            self.messages = messages
        }
    }

    struct ChatResponse: Decodable {
        public struct Choice: Decodable {
            public struct Message: Decodable {
                public let role: String
                public let content: String
            }
            public let index: Int
            public let message: Message
            public let finish_reason: String?
        }

        public struct Usage: Decodable {
            public let prompt_tokens: Int?
            public let completion_tokens: Int?
            public let total_tokens: Int?
        }

        public let id: String?
        public let object: String?
        public let created: Int?
        public let model: String?
        public let choices: [Choice]
        public let usage: Usage?
    }

    func chat(
        model: OpenAIModel = .gpt5_1,
        messages: [ChatMessage]
    ) async throws -> ChatResponse {
        let requestBody = ChatRequest(model: model.rawValue, messages: messages)
        return try await send(path: "chat/completions", body: requestBody)
    }
}


// MARK: - Reasoning Models

public extension OpenAIClient {
    func reason(
        model: OpenAIModel = .o3_mini,
        messages: [ChatMessage]
    ) async throws -> ChatResponse {
        let request = ChatRequest(model: model.rawValue, messages: messages)
        return try await send(path: "chat/completions", body: request)
    }
}


// MARK: - Vision Models

public extension OpenAIClient {

    enum ChatContent: Encodable {
        case text(String)
        case imageURL(URL)
        case imageBase64(String)

        enum CodingKeys: String, CodingKey {
            case type, image_url, image_base64, text
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(url.absoluteString, forKey: .image_url)
            case .imageBase64(let base64):
                try container.encode("image_base64", forKey: .type)
                try container.encode(base64, forKey: .image_base64)
            }
        }
    }

    struct VisionMessage: Encodable {
        public let role: ChatMessage.Role
        public let content: [ChatContent]

        public init(role: ChatMessage.Role, content: [ChatContent]) {
            self.role = role
            self.content = content
        }
    }

    struct VisionRequest: Encodable {
        public let model: String
        public let messages: [VisionMessage]

        public init(model: String, messages: [VisionMessage]) {
            self.model = model
            self.messages = messages
        }
    }

    func analyzeImage(
        model: OpenAIModel = .gpt4_1,
        messages: [VisionMessage]
    ) async throws -> ChatResponse {
        let body = VisionRequest(model: model.rawValue, messages: messages)
        return try await send(path: "chat/completions", body: body)
    }
}


// MARK: - Image Generation & Editing

public extension OpenAIClient {
    struct ImageGenerationRequest: Encodable {
        public let model: String
        public let prompt: String
        public let n: Int?
        public let size: String?

        public init(model: String, prompt: String, n: Int? = nil, size: String? = nil) {
            self.model = model
            self.prompt = prompt
            self.n = n
            self.size = size
        }
    }

    struct ImageGenerationResponse: Decodable {
        public struct DataItem: Decodable {
            public let url: String?
            public let b64_json: String?
        }
        public let created: Int?
        public let data: [DataItem]
    }

    func generateImage(
        model: OpenAIModel = .gpt_image,
        prompt: String,
        n: Int = 1,
        size: String = "1024x1024"
    ) async throws -> ImageGenerationResponse {
        let body = ImageGenerationRequest(
            model: model.rawValue,
            prompt: prompt,
            n: n,
            size: size
        )
        return try await send(path: "images/generations", body: body)
    }
}


// MARK: - Audio: Speech-to-Text & Text-to-Speech

public extension OpenAIClient {

    // Transcription Response
    struct AudioTranscriptionResponse: Decodable {
        public let text: String
    }

    // Transcription (file → text)
    func transcribeAudio(
        fileURL: URL,
        model: OpenAIModel = .whisper,
        language: String? = nil
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(path: "audio/transcriptions", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart/form-data body
        var body = Data()

        // Add model field
        body.append(string: "--\(boundary)\r\n")
        body.append(string: "Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append(string: "\(model.rawValue)\r\n")

        // Add language if present
        if let language = language {
            body.append(string: "--\(boundary)\r\n")
            body.append(string: "Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.append(string: "\(language)\r\n")
        }

        // Add file data
        let filename = fileURL.lastPathComponent
        let data = try Data(contentsOf: fileURL)
        let mimeType = "application/octet-stream" // or better detect mimeType if desired

        body.append(string: "--\(boundary)\r\n")
        body.append(string: "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append(string: "Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append(string: "\r\n")
        body.append(string: "--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw OpenAIError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                data: data
            )
        }

        do {
            let decoded = try JSONDecoder().decode(AudioTranscriptionResponse.self, from: data)
            return decoded.text
        } catch {
            throw OpenAIError.decodingError(error)
        }
    }

    // Text-to-Speech (text → audio)
    func synthesizeSpeech(
        text: String,
        model: String,
        voice: String,
        format: String
    ) async throws -> Data {
        struct SpeechRequest: Encodable {
            let text: String
            let model: String
            let voice: String
            let format: String
        }

        let body = SpeechRequest(text: text, model: model, voice: voice, format: format)

        var request = try makeRequest(path: "audio/speech", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw OpenAIError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                data: data
            )
        }

        return data
    }
}


// MARK: - Video Generation

public extension OpenAIClient {
    struct VideoGenerationRequest: Encodable {
        public let model: String
        public let prompt: String
        // Optional: duration, resolution, seed, reference image, reference video can be added here

        public init(model: String, prompt: String) {
            self.model = model
            self.prompt = prompt
        }
    }

    struct VideoGenerationResponse: Decodable {
        public let id: String?
        public let status: String?
        public let output: [String]? // URLs or file references
    }

    func generateVideo(
        model: OpenAIModel = .sora2_pro,
        prompt: String
    ) async throws -> VideoGenerationResponse {
        let body = VideoGenerationRequest(model: model.rawValue, prompt: prompt)
        return try await send(path: "videos", body: body)
    }

    func downloadFile(fileID: String) async throws -> Data {
        let path = "files/\(fileID)/content"
        var request = try makeRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw OpenAIError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                data: data
            )
        }

        return data
    }
}


// MARK: - Embeddings

public extension OpenAIClient {
    struct EmbeddingsRequest: Encodable {
        public let model: String
        public let input: [String]

        public init(model: String, input: [String]) {
            self.model = model
            self.input = input
        }
    }

    struct EmbeddingsResponse: Decodable {
        public struct Embedding: Decodable {
            public let embedding: [Double]
            public let index: Int?
        }
        public let data: [Embedding]
    }

    func createEmbeddings(
        model: OpenAIModel = .textEmbedding,
        input: [String]
    ) async throws -> EmbeddingsResponse {
        let body = EmbeddingsRequest(model: model.rawValue, input: input)
        return try await send(path: "embeddings", body: body)
    }
}


// MARK: - Streaming Chat Support (Text/Chat)

public extension OpenAIClient {
    func chatStream(
        model: OpenAIModel,
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void
    ) async throws {
        struct ChatStreamRequest: Encodable {
            let model: String
            let messages: [ChatMessage]
            let stream: Bool
        }

        let body = ChatStreamRequest(model: model.rawValue, messages: messages, stream: true)
        var request = try makeRequest(path: "chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (stream, response) = try await urlSession.bytes(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            // Read full data from stream to pass as error data
            var data = Data()
            for try await chunk in stream {
                data.append(contentsOf: chunk)
            }
            throw OpenAIError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1, data: data)
        }

        // Parse streaming chunks
        for try await line in stream.lines {
            // Streaming may send lines like: "data: {...json...}\n\n" or "data: [DONE]"
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed == "data: [DONE]" { break }
            if trimmed.hasPrefix("data: ") {
                let jsonString = String(trimmed.dropFirst("data: ".count))
                if let jsonData = jsonString.data(using: .utf8) {
                    struct StreamChunk: Decodable {
                        struct Choice: Decodable {
                            struct Delta: Decodable {
                                let content: String?
                            }
                            let delta: Delta
                        }
                        let choices: [Choice]
                    }
                    if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData) {
                        if let content = chunk.choices.first?.delta.content {
                            onDelta(content)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Data Extension for Multipart Form Data

fileprivate extension Data {
    mutating func append(string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
