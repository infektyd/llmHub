import Foundation

// MARK: - Gemini Manager
/// A clean, unified manager for Google's Gemini API (Text, Vision, Thinking, Imagen, Veo).
@available(iOS 26.1, macOS 26.1, *)
public class GeminiManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The base URL for the Gemini API.
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    
    /// Initializes a new `GeminiManager`.
    /// - Parameter apiKey: The API key for Gemini.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - 1. Text, Vision, & Thinking (Gemini 2.5/3.0)
    
    /// Generates content (text/code) from prompts, images, or video files.
    /// - Parameters:
    ///   - prompt: The user's text input.
    ///   - files: Optional array of media data (images/video) with mime types.
    ///   - model: e.g., "gemini-1.5-pro", "gemini-2.0-flash-exp" (default: "gemini-1.5-pro").
    ///   - thinkingLevel: Set to .high for Gemini 3 reasoning capabilities (default: .off).
    ///   - history: Previous chat history for context.
    /// - Returns: A `GenerationResponse` containing the model's output.
    public func generateContent(
        prompt: String,
        files: [MediaFile] = [],
        model: String = "gemini-1.5-pro",
        thinkingLevel: ThinkingLevel = .off,
        history: [Content] = []
    ) async throws -> GenerationResponse {
        let request = try makeGenerateContentRequest(
            prompt: prompt,
            files: files,
            model: model,
            thinkingLevel: thinkingLevel,
            history: history,
            stream: false
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Gemini API Error: \(errorText)")
            }
            throw GeminiError.apiError
        }
        
        return try JSONDecoder().decode(GenerationResponse.self, from: data)
    }

    /// Generates content with streaming response.
    /// - Parameters:
    ///   - prompt: The user's text input.
    ///   - files: Optional array of media data (images/video) with mime types.
    ///   - model: e.g., "gemini-1.5-pro" (default: "gemini-1.5-pro").
    ///   - thinkingLevel: Set to .high for Gemini 3 reasoning capabilities (default: .off).
    ///   - history: Previous chat history for context.
    /// - Returns: An async throwing stream of `GenerationResponse` chunks.
    public func streamGenerateContent(
        prompt: String,
        files: [MediaFile] = [],
        model: String = "gemini-1.5-pro",
        thinkingLevel: ThinkingLevel = .off,
        history: [Content] = []
    ) -> AsyncThrowingStream<GenerationResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try makeGenerateContentRequest(
                        prompt: prompt,
                        files: files,
                        model: model,
                        thinkingLevel: thinkingLevel,
                        history: history,
                        stream: true
                    )
                    
                    let (result, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        // Read error body if possible
                        var errorText = ""
                        for try await line in result.lines {
                            errorText += line
                        }
                        print("Gemini Streaming Error: \(errorText)")
                        throw GeminiError.apiError
                    }
                    
                    for try await line in result.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data: ") {
                            let json = String(trimmed.dropFirst(6)) // Remove "data: "
                            if json == "[DONE]" { break }
                            
                            if let data = json.data(using: .utf8) {
                                let chunk = try JSONDecoder().decode(GenerationResponse.self, from: data)
                                continuation.yield(chunk)
                            }
                        } else if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
                            // Some endpoints might return raw JSON array elements without "data: " prefix
                            // Depending on exact API version. 
                            // Standard SSE uses "data: ".
                            // If it's a raw JSON stream (not SSE), we might need different parsing.
                            // For v1beta/models/...:streamGenerateContent it is often a JSON array stream where each chunk is an object.
                            // However, URLSession.bytes.lines handles line-delimited.
                            // Let's assume standard JSON stream for now, but handle potential raw JSON object parsing if needed.
                            
                            // Attempt to decode line as direct JSON if not SSE
                            if let data = trimmed.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(GenerationResponse.self, from: data) {
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

    /// Creates a URLRequest for generating content.
    /// - Parameters:
    ///   - prompt: The user input.
    ///   - files: Attached media files.
    ///   - model: The model identifier.
    ///   - thinkingLevel: The reasoning level.
    ///   - history: Chat history.
    ///   - stream: Whether to request streaming.
    /// - Returns: A configured `URLRequest`.
    public func makeGenerateContentRequest(
        prompt: String,
        files: [MediaFile] = [],
        model: String = "gemini-1.5-pro",
        thinkingLevel: ThinkingLevel = .off,
        history: [Content] = [],
        stream: Bool = false
    ) throws -> URLRequest {
        let action = stream ? "streamGenerateContent" : "generateContent"
        var endpoint = "\(baseURL)/models/\(model):\(action)?key=\(apiKey)"
        if stream {
             endpoint += "&alt=sse" // Request SSE format
        }
        
        // Construct Request Parts
        var parts: [Part] = [.text(prompt)]
        
        // Add Media (Images/Video)
        for file in files {
            parts.append(.inlineData(InlineData(mimeType: file.mimeType, data: file.data.base64EncodedString())))
        }
        
        // Construct Message
        let userContent = Content(role: "user", parts: parts)
        var contents = history
        contents.append(userContent)
        
        // Config
        var config = GenerationConfig()
        if thinkingLevel != .off {
            config.thinkingLevel = thinkingLevel.rawValue
        }
        
        let payload = GenerateContentRequest(contents: contents, generationConfig: config)
        
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        return request
    }

    // MARK: - 2. Image Generation (Imagen 3)
    
    /// Generates images using Imagen 3.
    /// - Parameters:
    ///   - prompt: The image description.
    ///   - aspectRatio: The aspect ratio (e.g., "1:1").
    ///   - model: The model identifier (default: "imagen-3.0-generate-001").
    /// - Returns: The raw image data (PNG/JPEG).
    public func generateImage(
        prompt: String,
        aspectRatio: String = "1:1",
        model: String = "imagen-3.0-generate-001"
    ) async throws -> Data {
        let endpoint = "\(baseURL)/models/\(model):predict?key=\(apiKey)"
        
        let payload: [String: Any] = [
            "instances": [
                ["prompt": prompt]
            ],
            "parameters": [
                "aspectRatio": aspectRatio,
                "sampleCount": 1
            ]
        ]
        
        let data = try await performRawRequest(endpoint: endpoint, payload: payload)
        
        // Parse unique Imagen response structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let predictions = json["predictions"] as? [[String: Any]],
              let firstPred = predictions.first,
              let bytesBase64 = firstPred["bytesBase64Encoded"] as? String,
              let imageData = Data(base64Encoded: bytesBase64) else {
            throw GeminiError.parsingError
        }
        
        return imageData
    }
    
    // MARK: - 3. Video Generation (Veo)
    
    /// Generates video using Veo models.
    /// Note: This endpoint is subject to availability/preview status.
    /// - Parameters:
    ///   - prompt: The video description.
    ///   - model: The model identifier (default: "veo-2.0-generate-001").
    /// - Returns: The URI of the generated video.
    public func generateVideo(
        prompt: String,
        model: String = "veo-2.0-generate-001"
    ) async throws -> String {
        let endpoint = "\(baseURL)/models/\(model):predict?key=\(apiKey)" // Using predict as generic entry point often used for Veo alpha
        
        let payload: [String: Any] = [
            "instances": [
                [
                    "prompt": prompt,
                    "video_length": "5s" 
                ]
            ],
            "parameters": [
                "sampleCount": 1
            ]
        ]
        
        let data = try await performRawRequest(endpoint: endpoint, payload: payload)
        
        // 1. Check for immediate result
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let predictions = json["predictions"] as? [[String: Any]],
           let first = predictions.first,
           let videoUri = first["videoUri"] as? String {
            return videoUri
        }
        
        // 2. Check for Operation (long running)
        // If the API returns an "name" field indicating an operation
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let operationName = json["name"] as? String {
            return try await pollOperation(name: operationName)
        }

        throw GeminiError.custom("Video generation response could not be parsed or requires implementation update.")
    }

    /// Polls a long-running operation until completion.
    /// - Parameter name: The operation name.
    /// - Returns: The result URI.
    private func pollOperation(name: String) async throws -> String {
        let pollEndpoint = "\(baseURL)/\(name)?key=\(apiKey)"
        
        // Poll for up to 60 seconds? Video gen can be slow.
        let maxAttempts = 30
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 2 * 1_000_000_000) // 2 seconds
            
            guard let url = URL(string: pollEndpoint) else { throw GeminiError.invalidURL }
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                continue
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if done
                if let done = json["done"] as? Bool, done == true {
                    if let error = json["error"] as? [String: Any] {
                        let msg = error["message"] as? String ?? "Unknown operation error"
                        throw GeminiError.custom(msg)
                    }
                    
                    if let response = json["response"] as? [String: Any],
                       let videoUri = response["videoUri"] as? String { // Schema varies; adjust based on real response
                        return videoUri
                    }
                    
                    // Fallback: sometimes result is in metadata or result field
                    if let result = json["result"] as? [String: Any],
                       let videoUri = result["videoUri"] as? String {
                        return videoUri
                    }
                }
            }
        }
        
        throw GeminiError.custom("Operation timed out")
    }


    // MARK: - Helpers
    
    /// Performs a strongly-typed API request.
    private func performRequest<T: Encodable, U: Decodable>(endpoint: String, payload: T) async throws -> U {
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw GeminiError.apiError
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            // Try to parse detailed error
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                
                print("Gemini API Error: \(message)")
                
                if httpResponse.statusCode == 429 {
                    throw GeminiError.rateLimited
                }
                if message.contains("quota") {
                    throw GeminiError.quotaExceeded
                }
                
                throw GeminiError.custom(message)
            }
            
            if httpResponse.statusCode == 429 { throw GeminiError.rateLimited }
            if httpResponse.statusCode >= 500 { throw GeminiError.serverError(httpResponse.statusCode) }
            
            throw GeminiError.apiError
        }
        
        return try JSONDecoder().decode(U.self, from: data)
    }
    
    /// Performs a raw API request.
    private func performRawRequest(endpoint: String, payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.apiError
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
             if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                print("Gemini Raw API Error: \(message)")
                if httpResponse.statusCode == 429 { throw GeminiError.rateLimited }
                if message.contains("quota") { throw GeminiError.quotaExceeded }
                throw GeminiError.custom(message)
            }
            print("API Error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw GeminiError.apiError
        }
        return data
    }
}

// MARK: - Data Models

/// Represents a media file to be sent to Gemini.
public struct MediaFile {
    /// The raw data of the file.
    public let data: Data
    /// The MIME type of the file.
    public let mimeType: String
    
    /// Initializes a new `MediaFile`.
    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Defines the reasoning level for the model.
public enum ThinkingLevel: String {
    /// No thinking/reasoning.
    case off = "OFF" // Not sent in config
    /// Low level reasoning.
    case low = "LOW"
    /// High level reasoning (for complex tasks).
    case high = "HIGH"
}

// MARK: - API Structs (Codable)

/// The request payload for content generation.
struct GenerateContentRequest: Codable {
    /// The content history and new message.
    let contents: [Content]
    /// Configuration for generation.
    let generationConfig: GenerationConfig?
}

/// Represents a message content.
public struct Content: Codable {
    /// The role of the message sender.
    public let role: String
    /// The parts of the message.
    public let parts: [Part]
    
    /// Initializes a new `Content` object.
    public init(role: String, parts: [Part]) {
        self.role = role
        self.parts = parts
    }
}

/// A part of the message content.
public enum Part: Codable {
    /// Text content.
    case text(String)
    /// Inline media data.
    case inlineData(InlineData)
    /// Function call request.
    case functionCall(FunctionCall)
    /// Function response.
    case functionResponse(FunctionResponse)
    /// Thought signature (internal reasoning).
    case thoughtSignature(String) // Important for Gemini 3 reasoning chains
    
    enum CodingKeys: String, CodingKey {
        case text, inlineData, functionCall, functionResponse, thoughtSignature
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s): try container.encode(s, forKey: .text)
        case .inlineData(let d): try container.encode(d, forKey: .inlineData)
        case .functionCall(let f): try container.encode(f, forKey: .functionCall)
        case .functionResponse(let r): try container.encode(r, forKey: .functionResponse)
        case .thoughtSignature(let t): try container.encode(t, forKey: .thoughtSignature)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try? container.decode(String.self, forKey: .text) { self = .text(t) }
        else if let d = try? container.decode(InlineData.self, forKey: .inlineData) { self = .inlineData(d) }
        else if let fc = try? container.decode(FunctionCall.self, forKey: .functionCall) { self = .functionCall(fc) }
        else if let ts = try? container.decode(String.self, forKey: .thoughtSignature) { self = .thoughtSignature(ts) }
        else { throw GeminiError.parsingError }
    }
}

/// Inline media data structure.
public struct InlineData: Codable {
    /// The MIME type.
    public let mimeType: String
    /// The base64 encoded data.
    public let data: String // Base64 encoded
}

/// Configuration for generation parameters.
struct GenerationConfig: Codable {
    /// Sampling temperature (0.0 - 2.0).
    var temperature: Float? = nil // Default 1.0 is best for Gemini 3
    /// Thinking level setting.
    var thinkingLevel: String?
    /// Response modalities (e.g., TEXT, IMAGE).
    var responseModalities: [String]? // ["TEXT", "IMAGE"]
}

/// The response from a generation request.
public struct GenerationResponse: Codable {
    /// The generated candidates.
    public let candidates: [Candidate]?
    
    /// Convenience property to get the text from the first candidate.
    public var text: String? {
        candidates?.first?.content.parts.compactMap { part -> String? in
            if case .text(let t) = part { return t }
            return nil
        }.joined()
    }
    
    // Extracts thought signature to pass back for reasoning continuity
    /// The thought signature from the model's reasoning process.
    public var thoughtSignature: String? {
        candidates?.first?.content.parts.compactMap { part -> String? in
            if case .thoughtSignature(let s) = part { return s }
            return nil
        }.first
    }
}

/// A generation candidate.
public struct Candidate: Codable {
    /// The content of the candidate.
    public let content: Content
    /// The reason why generation finished.
    public let finishReason: String?
}

// Placeholders for Tool Use (optional expansion)
/// Represents a function call.
public struct FunctionCall: Codable {}
/// Represents a function response.
public struct FunctionResponse: Codable {}

/// Errors specific to the Gemini API.
enum GeminiError: Error {
    /// The URL was invalid.
    case invalidURL
    /// A general API error.
    case apiError
    /// Failed to parse the response.
    case parsingError
    /// A custom error message.
    case custom(String)
    /// Rate limit exceeded.
    case rateLimited
    /// Quota exceeded.
    case quotaExceeded
    /// Server error with status code.
    case serverError(Int)
}
