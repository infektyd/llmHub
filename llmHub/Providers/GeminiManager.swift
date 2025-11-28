import Foundation

// MARK: - Gemini Manager
/// A clean, unified manager for Google's Gemini API (Text, Vision, Thinking, Imagen, Veo).
@available(iOS 15.0, macOS 12.0, *)
public class GeminiManager {
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - 1. Text, Vision, & Thinking (Gemini 2.5/3.0)
    
    /// Generates content (text/code) from prompts, images, or video files.
    /// - Parameters:
    ///   - prompt: The user's text input.
    ///   - files: Optional array of media data (images/video) with mime types.
    ///   - model: e.g., "gemini-1.5-pro", "gemini-2.0-flash-exp"
    ///   - thinkingLevel: Set to .high for Gemini 3 reasoning capabilities.
    ///   - history: Previous chat history for context.
    public func generateContent(
        prompt: String,
        files: [MediaFile] = [],
        model: String = "gemini-1.5-pro",
        thinkingLevel: ThinkingLevel = .off,
        history: [Content] = []
    ) async throws -> GenerationResponse {
        
        let endpoint = "\(baseURL)/models/\(model):generateContent?key=\(apiKey)"
        
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
        
        return try await performRequest(endpoint: endpoint, payload: payload)
    }

    // MARK: - 2. Image Generation (Imagen 3)
    
    /// Generates images using Imagen 3.
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
    public func generateVideo(
        prompt: String,
        model: String = "veo-2.0-generate-001"
    ) async throws -> String {
        let endpoint = "\(baseURL)/models/\(model):generateVideos?key=\(apiKey)" // Likely endpoint structure for Veo
        
        // Fallback to :predict if generateVideos is not available, but standard API uses specific verbs often.
        // For Veo, the structure often looks like this:
        let payload: [String: Any] = [
            "prompt": prompt,
            "video_length": "5s" // example param
        ]
        
        // Note: Veo integration often requires polling an Operation object.
        // This is a simplified "fire and forget" or synchronous wait depending on the specific model version.
        // If the API returns an "operation", you would need a polling mechanism.
        
        let data = try await performRawRequest(endpoint: endpoint, payload: payload)
        
        // Assuming direct return or operation name. 
        // Real-world Veo usage often involves: Response -> Operation -> Poll -> URL.
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let videoUri = json["videoUri"] as? String {
            return videoUri
        }
        
        throw GeminiError.custom("Video generation requires polling implementation or updated endpoint.")
    }

    // MARK: - Helpers
    
    private func performRequest<T: Encodable, U: Decodable>(endpoint: String, payload: T) async throws -> U {
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Gemini API Error: \(errorText)")
            }
            throw GeminiError.apiError
        }
        
        return try JSONDecoder().decode(U.self, from: data)
    }
    
    private func performRawRequest(endpoint: String, payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            print("API Error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw GeminiError.apiError
        }
        return data
    }
}

// MARK: - Data Models

public struct MediaFile {
    public let data: Data
    public let mimeType: String
    
    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public enum ThinkingLevel: String {
    case off = "OFF" // Not sent in config
    case low = "LOW"
    case high = "HIGH"
}

// MARK: - API Structs (Codable)

struct GenerateContentRequest: Codable {
    let contents: [Content]
    let generationConfig: GenerationConfig?
}

public struct Content: Codable {
    public let role: String
    public let parts: [Part]
    
    public init(role: String, parts: [Part]) {
        self.role = role
        self.parts = parts
    }
}

public enum Part: Codable {
    case text(String)
    case inlineData(InlineData)
    case functionCall(FunctionCall)
    case functionResponse(FunctionResponse)
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

public struct InlineData: Codable {
    public let mimeType: String
    public let data: String // Base64 encoded
}

struct GenerationConfig: Codable {
    var temperature: Float? = nil // Default 1.0 is best for Gemini 3
    var thinkingLevel: String?
    var responseModalities: [String]? // ["TEXT", "IMAGE"]
}

public struct GenerationResponse: Codable {
    public let candidates: [Candidate]?
    
    public var text: String? {
        candidates?.first?.content.parts.compactMap { part -> String? in
            if case .text(let t) = part { return t }
            return nil
        }.joined()
    }
    
    // Extracts thought signature to pass back for reasoning continuity
    public var thoughtSignature: String? {
        candidates?.first?.content.parts.compactMap { part -> String? in
            if case .thoughtSignature(let s) = part { return s }
            return nil
        }.first
    }
}

public struct Candidate: Codable {
    public let content: Content
    public let finishReason: String?
}

// Placeholders for Tool Use (optional expansion)
public struct FunctionCall: Codable {}
public struct FunctionResponse: Codable {}

enum GeminiError: Error {
    case invalidURL
    case apiError
    case parsingError
    case custom(String)
}
