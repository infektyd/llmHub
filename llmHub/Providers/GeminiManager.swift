import Foundation

// MARK: - Gemini Manager
/// A clean, unified manager for Google's Gemini API (Text, Vision, Thinking, Imagen, Veo).
@available(iOS 26.1, macOS 26.1, *)
public class GeminiManager {
    /// The API key for authentication.
    private let apiKey: String
    /// The base URL for the Gemini Developer API (v1beta).
    private let baseURL: URL

    /// Initializes a new `GeminiManager`.
    /// - Parameter apiKey: The API key for Gemini.
    /// - Parameter baseURL: Override for Gemini API base URL (Developer API only).
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
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
        // Bridge legacy API to the new thinkingConfig-based request options.
        // Rationale: Gemini Developer API uses generationConfig.thinkingConfig, and thinking is model-family specific.
        let options = LLMRequestOptions(
            thinkingPreference: thinkingLevel == .off ? .off : .on,
            thinkingBudgetTokens: nil,
            thinkingLevelHint: thinkingLevel == .off ? nil : thinkingLevel.rawValue
        )
        let request = try makeGenerateContentRequest(
            prompt: prompt,
            files: files,
            model: model,
            options: options,
            history: history,
            stream: false
        )

        let (data, response) = try await LLMURLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
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
                    let options = LLMRequestOptions(
                        thinkingPreference: thinkingLevel == .off ? .off : .on,
                        thinkingBudgetTokens: nil,
                        thinkingLevelHint: thinkingLevel == .off ? nil : thinkingLevel.rawValue
                    )
                    let request = try makeGenerateContentRequest(
                        prompt: prompt,
                        files: files,
                        model: model,
                        options: options,
                        history: history,
                        stream: true
                    )

                    let (result, response) = try await LLMURLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    else {
                        var errorText = ""
                        for try await line in result.lines { errorText += line }
                        print("Gemini Streaming Error: \(errorText)")
                        throw GeminiError.apiError
                    }

                    var sse = SSEEventParser()
                    let decoder = JSONDecoder()

                    for try await byte in result {
                        for payload in sse.append(byte: byte) {
                            if payload == "[DONE]" { break }

                            guard let data = payload.data(using: .utf8) else { continue }

                            do {
                                let chunk = try decoder.decode(GenerationResponse.self, from: data)

                                // SAFETY CHECK: Malformed tool calls
                                if let candidate = chunk.candidates?.first {
                                    if candidate.finishReason == "MALFORMED_FUNCTION_CALL" {
                                        print(
                                            "GeminiManager: Detected MALFORMED_FUNCTION_CALL. Stopping stream safely."
                                        )
                                        continuation.finish()
                                        return
                                    }
                                }

                                continuation.yield(chunk)

                            } catch {
                                #if DEBUG
                                    print("GeminiManager: JSON Decode Failure: \(error)")
                                #endif
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
    func makeGenerateContentRequest(
        prompt: String,
        files: [MediaFile] = [],
        model: String = "gemini-1.5-pro",
        options: LLMRequestOptions = .default,
        history: [Content] = [],
        tools: [ToolDefinition]? = nil,
        maxOutputTokens: Int? = nil,
        stream: Bool = false
    ) throws -> URLRequest {
        let action = stream ? "streamGenerateContent" : "generateContent"
        // NOTE: We intentionally build the URL string (instead of URLComponents + appendingPathComponent)
        // because the Gemini REST path includes `:<method>` (e.g. `:generateContent`) and we must preserve
        // the literal colon in the path.
        var endpoint = "\(baseURL.absoluteString)/models/\(model):\(action)?key=\(apiKey)"
        if stream {
            endpoint += "&alt=sse"
        }
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }

        // Construct Request Parts
        var parts: [Part] = [.text(prompt)]

        // Add Media (Images/Video)
        for file in files {
            parts.append(
                .inlineData(
                    InlineData(mimeType: file.mimeType, data: file.data.base64EncodedString())))
        }

        // Construct Message
        let userContent = Content(role: "user", parts: parts)
        var contents = history
        contents.append(userContent)

        // Config
        var config = GenerationConfig()
        config.maxOutputTokens = maxOutputTokens ?? 8192  // Ensure responses aren't cut off
        config.thinkingConfig = try Self.buildThinkingConfig(model: model, options: options)
        if let thinkingConfig = config.thinkingConfig {
            try Self.validateThinkingConfig(thinkingConfig)
        }

        let geminiTools: [GeminiTool]? = {
            guard let tools, !tools.isEmpty else { return nil }
            let declarations = tools.map { toolDef in
                GeminiFunctionDeclaration(
                    name: toolDef.name,
                    description: toolDef.description,
                    parameters: GeminiJSONValue.from(toolDef.inputSchema)
                )
            }
            return [GeminiTool(functionDeclarations: declarations)]
        }()

        let payload = GenerateContentRequest(
            contents: contents,
            generationConfig: config,
            tools: geminiTools
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        // Rationale: Gemini Developer API expects camelCase keys. Do not snake_case encode this payload.
        request.httpBody = try encoder.encode(payload)

        return request
    }

    // MARK: - ThinkingConfig (Gemini Developer API)

    /// Builds a Gemini Developer API `thinkingConfig` according to model-family rules.
    ///
    /// - Model rules (per current Gemini docs):
    ///   - `gemini-3-*` uses `thinkingLevel`
    ///   - `gemini-2.5-*` uses `thinkingBudget`
    ///   - Other models omit thinking config unless explicitly supported
    ///
    /// Mutual exclusivity is enforced: `thinkingLevel` and `thinkingBudget` must never coexist.
    internal static func buildThinkingConfig(model: String, options: LLMRequestOptions) throws
        -> ThinkingConfig?
    {
        guard options.thinkingPreference != .off else { return nil }

        let lower = model.lowercased()
        if lower.hasPrefix("gemini-3-") {
            let requested = options.thinkingLevelHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = (requested?.lowercased()).flatMap { $0.isEmpty ? nil : $0 }
            let level = GeminiThinkingLevel(rawValue: normalized ?? "high")
            try validateGemini3ThinkingLevel(level, model: lower)
            let config = ThinkingConfig(
                includeThoughts: nil,
                thinkingBudget: nil,
                thinkingLevel: level
            )
            try validateThinkingConfig(config)
            return config
        }

        if lower.hasPrefix("gemini-2.5-") {
            if let hint = options.thinkingLevelHint,
                !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw GeminiError.custom(
                    "Invalid thinking config: thinkingLevel is not supported for Gemini 2.5 models; use thinkingBudget."
                )
            }
            // Docs: -1 enables dynamic thinking; 0 disables thinking.
            let budget = options.thinkingBudgetTokens ?? -1
            let config = ThinkingConfig(
                includeThoughts: nil,
                thinkingBudget: budget,
                thinkingLevel: nil
            )
            try validateThinkingConfig(config)
            return config
        }

        return nil
    }

    internal static func validateGemini3ThinkingLevel(_ level: GeminiThinkingLevel, model: String) throws {
        let value = level.rawValue.lowercased()

        if model.contains("-pro") {
            if value != "low" && value != "high" {
                throw GeminiError.custom(
                    "Invalid thinkingLevel '\(level.rawValue)' for Gemini 3 Pro. Allowed: low, high."
                )
            }
            return
        }

        if model.contains("-flash") {
            if value != "minimal" && value != "low" && value != "medium" && value != "high" {
                throw GeminiError.custom(
                    "Invalid thinkingLevel '\(level.rawValue)' for Gemini 3 Flash. Allowed: minimal, low, medium, high."
                )
            }
            return
        }
    }

    /// Validates mutual exclusivity of `thinkingLevel` vs `thinkingBudget`.
    internal static func validateThinkingConfig(_ config: ThinkingConfig) throws {
        if config.thinkingLevel != nil && config.thinkingBudget != nil {
            throw GeminiError.custom(
                "Invalid thinkingConfig: thinkingLevel and thinkingBudget are mutually exclusive.")
        }
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
        let endpoint = "\(baseURL.absoluteString)/models/\(model):predict?key=\(apiKey)"

        let payload: [String: Any] = [
            "instances": [
                ["prompt": prompt]
            ],
            "parameters": [
                "aspectRatio": aspectRatio,
                "sampleCount": 1,
            ],
        ]

        let data = try await performRawRequest(endpoint: endpoint, payload: payload)

        // Parse unique Imagen response structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let predictions = json["predictions"] as? [[String: Any]],
            let firstPred = predictions.first,
            let bytesBase64 = firstPred["bytesBase64Encoded"] as? String,
            let imageData = Data(base64Encoded: bytesBase64)
        else {
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
        let endpoint = "\(baseURL.absoluteString)/models/\(model):predict?key=\(apiKey)"  // Using predict as generic entry point often used for Veo alpha

        let payload: [String: Any] = [
            "instances": [
                [
                    "prompt": prompt,
                    "video_length": "5s",
                ]
            ],
            "parameters": [
                "sampleCount": 1
            ],
        ]

        let data = try await performRawRequest(endpoint: endpoint, payload: payload)

        // 1. Check for immediate result
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let predictions = json["predictions"] as? [[String: Any]],
            let first = predictions.first,
            let videoUri = first["videoUri"] as? String
        {
            return videoUri
        }

        // 2. Check for Operation (long running)
        // If the API returns an "name" field indicating an operation
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let operationName = json["name"] as? String
        {
            return try await pollOperation(name: operationName)
        }

        throw GeminiError.custom(
            "Video generation response could not be parsed or requires implementation update.")
    }

    /// Polls a long-running operation until completion.
    /// - Parameter name: The operation name.
    /// - Returns: The result URI.
    private func pollOperation(name: String) async throws -> String {
        let pollEndpoint = "\(baseURL.absoluteString)/\(name)?key=\(apiKey)"

        // Poll for up to 60 seconds? Video gen can be slow.
        let maxAttempts = 30
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 2 * 1_000_000_000)  // 2 seconds

            guard let url = URL(string: pollEndpoint) else { throw GeminiError.invalidURL }
            let (data, response) = try await LLMURLSession.shared.data(from: url)

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
                        let videoUri = response["videoUri"] as? String
                    {  // Schema varies; adjust based on real response
                        return videoUri
                    }

                    // Fallback: sometimes result is in metadata or result field
                    if let result = json["result"] as? [String: Any],
                        let videoUri = result["videoUri"] as? String
                    {
                        return videoUri
                    }
                }
            }
        }

        throw GeminiError.custom("Operation timed out")
    }

    // MARK: - Helpers

    /// Performs a strongly-typed API request.
    private func performRequest<T: Encodable, U: Decodable>(endpoint: String, payload: T)
        async throws -> U
    {
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await LLMURLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.apiError
        }

        if !(200...299).contains(httpResponse.statusCode) {
            // Try to parse detailed error
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorObj = errorJson["error"] as? [String: Any],
                let message = errorObj["message"] as? String
            {

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
            if httpResponse.statusCode >= 500 {
                throw GeminiError.serverError(httpResponse.statusCode)
            }

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

        let (data, response) = try await LLMURLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.apiError
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorObj = errorJson["error"] as? [String: Any],
                let message = errorObj["message"] as? String
            {
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

/// Legacy thinking level control for the public `GeminiManager` API.
/// New code should prefer `LLMRequestOptions` + `GenerationConfig.thinkingConfig`.
public enum ThinkingLevel: String, Codable {
    case off = "OFF"  // Not sent in config
    case low = "low"
    case high = "high"
}

/// A forward-compatible thinking-level wrapper for Gemini 3 models.
public struct GeminiThinkingLevel: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(stringLiteral value: StringLiteralType) { self.rawValue = value }

    public static let minimal: Self = "minimal"
    public static let low: Self = "low"
    public static let medium: Self = "medium"
    public static let high: Self = "high"
}

// MARK: - API Structs (Codable)

/// The request payload for content generation.
struct GenerateContentRequest: Codable {
    /// The content history and new message.
    let contents: [Content]
    /// Configuration for generation.
    let generationConfig: GenerationConfig?
    /// Optional tool/function declarations for native tool calling.
    let tools: [GeminiTool]?

    // Explicit coding keys to prevent accidental snake_case encoding.
    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig
        case tools
    }
}

/// A Gemini tool container (function declarations).
struct GeminiTool: Codable {
    let functionDeclarations: [GeminiFunctionDeclaration]

    enum CodingKeys: String, CodingKey {
        case functionDeclarations
    }
}

/// A Gemini function declaration.
struct GeminiFunctionDeclaration: Codable {
    let name: String
    let description: String?
    let parameters: GeminiJSONValue?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parameters
    }
}

/// Represents a message content.
public nonisolated struct Content: Codable, Sendable {
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

/// A single Gemini `Part`.
///
/// Thought signatures can be present alongside other part payloads (for example, attached to a
/// `functionCall` part). We model them as an optional field rather than as a separate sum-type case.
public nonisolated struct Part: Codable, Sendable {
    public var text: String?
    public var inlineData: InlineData?
    public var functionCall: FunctionCall?
    public var functionResponse: FunctionResponse?
    public var thoughtSignature: String?

    public init(
        text: String? = nil,
        inlineData: InlineData? = nil,
        functionCall: FunctionCall? = nil,
        functionResponse: FunctionResponse? = nil,
        thoughtSignature: String? = nil
    ) {
        self.text = text
        self.inlineData = inlineData
        self.functionCall = functionCall
        self.functionResponse = functionResponse
        self.thoughtSignature = thoughtSignature
    }

    public static func text(_ value: String, thoughtSignature: String? = nil) -> Part {
        Part(text: value, thoughtSignature: thoughtSignature)
    }

    public static func inlineData(_ value: InlineData, thoughtSignature: String? = nil) -> Part {
        Part(inlineData: value, thoughtSignature: thoughtSignature)
    }

    public static func functionCall(_ value: FunctionCall, thoughtSignature: String? = nil) -> Part {
        Part(functionCall: value, thoughtSignature: thoughtSignature)
    }

    public static func functionResponse(_ value: FunctionResponse, thoughtSignature: String? = nil) -> Part {
        Part(functionResponse: value, thoughtSignature: thoughtSignature)
    }
}

/// Inline media data structure.
public nonisolated struct InlineData: Codable, Sendable {
    /// The MIME type.
    public let mimeType: String
    /// The base64 encoded data.
    public let data: String  // Base64 encoded
}

/// Configuration for generation parameters.
struct GenerationConfig: Codable {
    /// Sampling temperature (0.0 - 2.0).
    var temperature: Float? = nil  // Default 1.0 is best for Gemini 3
    /// Model thinking configuration (Gemini Developer API).
    var thinkingConfig: ThinkingConfig?
    /// Response modalities (e.g., TEXT, IMAGE).
    var responseModalities: [String]?  // ["TEXT", "IMAGE"]
    /// Maximum number of output tokens.
    var maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case thinkingConfig
        case responseModalities
        case maxOutputTokens
    }
}

/// Configuration for model thinking/reasoning behavior.
///
/// NOTE: `thinkingLevel` and `thinkingBudget` are mutually exclusive depending on model family.
struct ThinkingConfig: Codable {
    /// If true, include thought summaries when available.
    let includeThoughts: Bool?
    /// Thinking token budget (Gemini 2.5). -1 enables dynamic thinking; 0 disables thinking.
    let thinkingBudget: Int?
    /// Thinking level (Gemini 3).
    let thinkingLevel: GeminiThinkingLevel?

    enum CodingKeys: String, CodingKey {
        case includeThoughts
        case thinkingBudget
        case thinkingLevel
    }
}

/// The response from a generation request.
public nonisolated struct GenerationResponse: Codable, Sendable {
    /// The generated candidates.
    public let candidates: [Candidate]?

    /// Convenience property to get the text from the first candidate.
    public var text: String? {
        candidates?.first?.content.parts.compactMap { $0.text }.joined()
    }

    /// Assembles text by concatenating *all* text parts for a specific candidate.
    public func assembledText(candidateIndex: Int = 0) -> String {
        guard let candidates, candidates.indices.contains(candidateIndex) else { return "" }
        return candidates[candidateIndex].content.parts.compactMap { $0.text }.joined()
    }

    /// Candidate count convenience for logging/diagnostics.
    public var candidateCount: Int { candidates?.count ?? 0 }

    /// Part counts per candidate convenience for logging/diagnostics.
    public var partCountsByCandidate: [Int] {
        (candidates ?? []).map { $0.content.parts.count }
    }

    // Extracts thought signature to pass back for reasoning continuity
    /// The thought signature from the model's reasoning process.
    public var thoughtSignature: String? {
        candidates?.first?.content.parts.compactMap { $0.thoughtSignature }.first
    }

    /// Usage metadata for the generation.
    public let usageMetadata: UsageMetadata?
}

/// Token usage metadata.
public nonisolated struct UsageMetadata: Codable, Sendable {
    public let promptTokenCount: Int?
    public let candidatesTokenCount: Int?
    public let totalTokenCount: Int?
}

/// A generation candidate.
public nonisolated struct Candidate: Codable, Sendable {
    /// The content of the candidate.
    public let content: Content
    /// The reason why generation finished.
    public let finishReason: String?
}

// Placeholders for Tool Use (optional expansion)
/// Represents a function call.
public nonisolated struct FunctionCall: Codable, Sendable {
    public let name: String
    public let args: [String: GeminiJSONValue]?
}
/// Represents a function response.
public nonisolated struct FunctionResponse: Codable, Sendable {
    public let name: String
    public let response: [String: GeminiJSONValue]
}

/// A type-safe wrapper for JSON values in Gemini API.
public nonisolated enum GeminiJSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([GeminiJSONValue])
    case object([String: GeminiJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([GeminiJSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: GeminiJSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v):
            // Guard against non-finite values (NaN, Infinity) which are not valid JSON
            try container.encode(v.isFinite ? v : 0.0)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    /// Converts an `Any` value to `GeminiJSONValue`.
    public static func from(_ value: Any) -> GeminiJSONValue {
        switch value {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .number(Double(i))
        case let d as Double:
            return .number(d)
        case let n as NSNumber:
            return .number(n.doubleValue)
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
}

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
