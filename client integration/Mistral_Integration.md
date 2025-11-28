//
//  Mistral_Integration.md
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//
# Mistral API Complete Integration Reference for Swift
**Last Updated: November 2025**

---

## 📡 Base Configuration

### API Base URLs
```
Primary API:        https://api.mistral.ai/v1
Codestral (IDE):    https://codestral.mistral.ai/v1
```

### Authentication
```
Header: Authorization: Bearer YOUR_API_KEY
Content-Type: application/json
```

---

## 🔌 API Endpoints Overview

| Endpoint | Path | Purpose |
|----------|------|---------|
| Chat Completions | `/v1/chat/completions` | Text, Vision, Audio chat |
| FIM (Fill-in-Middle) | `/v1/fim/completions` | Code completion |
| Embeddings | `/v1/embeddings` | Text/Code embeddings |
| Audio Transcription | `/v1/audio/transcriptions` | Speech-to-text |
| OCR | `/v1/ocr` | Document parsing |
| Models | `/v1/models` | List available models |
| Files | `/v1/files` | Upload/download files |
| Agents | `/v1/agents` | Create agents |
| Conversations | `/v1/conversations` | Agent conversations |

---

## 🤖 Model Identifiers (November 2025)

### Premier Models (Closed Weights)
```swift
// Flagship Models
"mistral-medium-latest"      // → mistral-medium-2508 (Aug 2025) - Multimodal frontier
"mistral-large-latest"       // → mistral-medium-2508 (points to medium now)
"pixtral-large-latest"       // → pixtral-large-2411 - 124B multimodal

// Reasoning (Magistral)
"magistral-medium-latest"    // → magistral-medium-2509 - Frontier reasoning + vision
"magistral-small-latest"     // → magistral-small-2509 - Small reasoning + vision

// Coding
"codestral-latest"           // → codestral-2508 - Code generation & FIM
"devstral-small-latest"      // → devstral-small-2507 - Agentic coding
"devstral-medium-latest"     // → devstral-medium-2507 - Agentic coding

// Audio
"voxtral-small-latest"       // → voxtral-small-2507 (24B) - Audio chat
"voxtral-mini-latest"        // → voxtral-mini-2507 (3B) - Audio chat + transcription

// Edge Models
"ministral-3b-latest"        // → ministral-3b-2410 - Edge 3B
"ministral-8b-latest"        // → ministral-8b-2410 - Edge 8B

// Specialized
"mistral-ocr-latest"         // → mistral-ocr-2505 - Document OCR
"mistral-embed"              // Text embeddings (1024 dim)
"codestral-embed"            // Code embeddings (up to 3072 dim)
"mistral-moderation-latest"  // → mistral-moderation-2411 - Content moderation
```

### Open Models (Apache 2.0)
```swift
"mistral-small-latest"       // → mistral-small-2506 (June 2025) - Multimodal small
"mistral-small-2503"         // Mistral Small 3.1
"open-mistral-nemo"          // → open-mistral-nemo-2407 - Open 12B
"pixtral-12b-2409"           // Open vision model
```

### Dated Versions (Recommended for Production)
```swift
// Use dated versions to prevent breaking changes
"mistral-medium-2508"
"magistral-medium-2509"
"magistral-small-2509"
"mistral-small-2506"
"codestral-2508"
"voxtral-small-2507"
"voxtral-mini-2507"
"devstral-small-2507"
"devstral-medium-2507"
"mistral-ocr-2505"
```

---

## 📋 Swift Data Structures

### Core Request/Response Types

```swift
import Foundation

// MARK: - Chat Completions

struct MistralChatRequest: Codable {
    let model: String
    let messages: [MistralMessage]
    var temperature: Double? = nil           // 0.0-0.7 recommended
    var topP: Double? = nil                  // 0.0-1.0, don't use with temperature
    var maxTokens: Int? = nil
    var stream: Bool? = nil
    var safePrompt: Bool? = nil              // Inject safety prompt
    var randomSeed: Int? = nil               // Deterministic output
    var responseFormat: ResponseFormat? = nil
    var tools: [Tool]? = nil
    var toolChoice: ToolChoice? = nil
    var parallelToolCalls: Bool? = nil
    var frequencyPenalty: Double? = nil      // 0.0-2.0
    var presencePenalty: Double? = nil       // 0.0-2.0
    var prediction: Prediction? = nil        // Predicted outputs
    var promptMode: String? = nil            // "reasoning" for Magistral
    var stop: [String]? = nil
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools, stop
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case safePrompt = "safe_prompt"
        case randomSeed = "random_seed"
        case responseFormat = "response_format"
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case prediction
        case promptMode = "prompt_mode"
    }
}

struct MistralMessage: Codable {
    let role: String                         // "system", "user", "assistant", "tool"
    let content: MessageContent
    var name: String? = nil                  // For tool messages
    var toolCalls: [ToolCall]? = nil         // For assistant with tool calls
    var toolCallId: String? = nil            // For tool response messages
    
    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

// Content can be string or array (for multimodal)
enum MessageContent: Codable {
    case text(String)
    case multimodal([ContentPart])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .multimodal(try container.decode([ContentPart].self))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .multimodal(let parts):
            try container.encode(parts)
        }
    }
}

struct ContentPart: Codable {
    let type: String                         // "text", "image_url", "input_audio"
    var text: String? = nil
    var imageUrl: ImageURL? = nil
    var inputAudio: String? = nil            // Base64 encoded audio
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
        case inputAudio = "input_audio"
    }
}

struct ImageURL: Codable {
    let url: String                          // URL or base64 data URI
}

struct ResponseFormat: Codable {
    let type: String                         // "text", "json_object", "json_schema"
    var jsonSchema: JSONSchema? = nil
    
    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

struct JSONSchema: Codable {
    let name: String
    let schema: [String: AnyCodable]
    var strict: Bool? = nil
}

struct Prediction: Codable {
    let type: String                         // "content"
    let content: String
}

struct MistralChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
}

struct Choice: Codable {
    let index: Int
    let message: AssistantMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct AssistantMessage: Codable {
    let role: String
    let content: String?
    var toolCalls: [ToolCall]? = nil
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

struct Usage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
```

### Tool/Function Calling

```swift
struct Tool: Codable {
    let type: String                         // "function"
    let function: FunctionDefinition
}

struct FunctionDefinition: Codable {
    let name: String
    let description: String?
    let parameters: [String: AnyCodable]
}

enum ToolChoice: Codable {
    case auto
    case none
    case any
    case required
    case specific(ToolChoiceSpecific)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            switch string {
            case "auto": self = .auto
            case "none": self = .none
            case "any": self = .any
            case "required": self = .required
            default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown tool choice"))
            }
        } else {
            self = .specific(try container.decode(ToolChoiceSpecific.self))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .any: try container.encode("any")
        case .required: try container.encode("required")
        case .specific(let choice): try container.encode(choice)
        }
    }
}

struct ToolChoiceSpecific: Codable {
    let type: String                         // "function"
    let function: ToolChoiceFunction
}

struct ToolChoiceFunction: Codable {
    let name: String
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable {
    let name: String
    let arguments: String                    // JSON string
}
```

### FIM (Fill-in-Middle) for Code

```swift
struct MistralFIMRequest: Codable {
    let model: String                        // "codestral-latest"
    let prompt: String                       // Code before cursor
    var suffix: String? = nil                // Code after cursor
    var temperature: Double? = nil
    var topP: Double? = nil
    var maxTokens: Int? = nil
    var minTokens: Int? = nil                // Enforce minimum output
    var stream: Bool? = nil
    var randomSeed: Int? = nil
    var stop: [String]? = nil
    
    enum CodingKeys: String, CodingKey {
        case model, prompt, suffix, temperature, stream, stop
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case minTokens = "min_tokens"
        case randomSeed = "random_seed"
    }
}

struct MistralFIMResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [FIMChoice]
    let usage: Usage?
}

struct FIMChoice: Codable {
    let index: Int
    let message: FIMMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct FIMMessage: Codable {
    let content: String
}
```

### Embeddings

```swift
struct MistralEmbeddingsRequest: Codable {
    let model: String                        // "mistral-embed" or "codestral-embed"
    let inputs: [String]                     // Text/code to embed (renamed from 'input')
    var outputDtype: String? = nil           // "float", "int8", "binary", "ubinary"
    var outputDimension: Int? = nil          // Max 3072 for codestral-embed, 1024 for mistral-embed
    
    enum CodingKeys: String, CodingKey {
        case model, inputs
        case outputDtype = "output_dtype"
        case outputDimension = "output_dimension"
    }
}

struct MistralEmbeddingsResponse: Codable {
    let id: String
    let object: String
    let data: [EmbeddingData]
    let model: String
    let usage: EmbeddingUsage
}

struct EmbeddingData: Codable {
    let object: String
    let embedding: [Double]
    let index: Int
}

struct EmbeddingUsage: Codable {
    let promptTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case totalTokens = "total_tokens"
    }
}
```

### Audio Transcription

```swift
// Note: Uses multipart/form-data, not JSON
struct MistralTranscriptionRequest {
    let model: String                        // "voxtral-mini-latest"
    let file: Data                           // Audio file data
    let fileName: String                     // e.g., "audio.mp3"
    var language: String? = nil              // ISO language code
    var timestampGranularities: [String]? = nil  // ["segment"]
}

struct MistralTranscriptionResponse: Codable {
    let text: String
    var segments: [TranscriptionSegment]? = nil
}

struct TranscriptionSegment: Codable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}
```

### OCR (Document AI)

```swift
struct MistralOCRRequest: Codable {
    let model: String                        // "mistral-ocr-latest"
    let document: OCRDocument
    var pages: String? = nil                 // "0-2" or "3" or specific pages
    var includeImageBase64: Bool? = nil
    var imageLimit: Int? = nil
    var imageMinSize: Int? = nil
    
    enum CodingKeys: String, CodingKey {
        case model, document, pages
        case includeImageBase64 = "include_image_base64"
        case imageLimit = "image_limit"
        case imageMinSize = "image_min_size"
    }
}

struct OCRDocument: Codable {
    let type: String                         // "document_url" or "image_url" or "base64"
    var documentUrl: String? = nil
    var imageUrl: String? = nil
    var data: String? = nil                  // Base64 encoded
    
    enum CodingKeys: String, CodingKey {
        case type
        case documentUrl = "document_url"
        case imageUrl = "image_url"
        case data
    }
}

struct MistralOCRResponse: Codable {
    let pages: [OCRPage]
    let model: String
    let usageInfo: OCRUsage
    
    enum CodingKeys: String, CodingKey {
        case pages, model
        case usageInfo = "usage_info"
    }
}

struct OCRPage: Codable {
    let index: Int
    let markdown: String
    var images: [OCRImage]? = nil
    let dimensions: OCRDimensions
}

struct OCRImage: Codable {
    let id: String
    let topLeftX: Int
    let topLeftY: Int
    let bottomRightX: Int
    let bottomRightY: Int
    var imageBase64: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case id
        case topLeftX = "top_left_x"
        case topLeftY = "top_left_y"
        case bottomRightX = "bottom_right_x"
        case bottomRightY = "bottom_right_y"
        case imageBase64 = "image_base64"
    }
}

struct OCRDimensions: Codable {
    let dpi: Int
    let height: Int
    let width: Int
}

struct OCRUsage: Codable {
    let pagesProcessed: Int
    let docSizeBytes: Int
    
    enum CodingKeys: String, CodingKey {
        case pagesProcessed = "pages_processed"
        case docSizeBytes = "doc_size_bytes"
    }
}
```

### Agents API

```swift
struct MistralAgentCreateRequest: Codable {
    var model: String? = nil                 // Defaults to mistral-medium-latest
    var name: String? = nil
    var description: String? = nil
    var instructions: String? = nil          // System prompt
    var tools: [AgentTool]? = nil
    
    // Completion parameters
    var temperature: Double? = nil
    var topP: Double? = nil
    var maxTokens: Int? = nil
}

struct AgentTool: Codable {
    let type: String                         // "code_execution", "image_generation", 
                                             // "web_search", "document_library", "function"
    var function: FunctionDefinition? = nil  // Only for type "function"
}

struct MistralAgentResponse: Codable {
    let id: String
    let object: String
    let name: String?
    let description: String?
    let model: String
    let instructions: String?
    let tools: [AgentTool]?
}

// Conversations API (for agents)
struct MistralConversationStartRequest: Codable {
    var agentId: String? = nil               // Use agent
    var model: String? = nil                 // Or direct model access
    let inputs: String                       // User message
    var stream: Bool? = nil
    
    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case model, inputs, stream
    }
}

struct MistralConversationResponse: Codable {
    let id: String
    let outputs: [ConversationOutput]
}

struct ConversationOutput: Codable {
    let type: String                         // "message.output", "tool.execution"
    var content: [ConversationContent]? = nil
}

struct ConversationContent: Codable {
    let type: String                         // "text", "tool_file"
    var text: String? = nil
    var fileId: String? = nil                // For generated images
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case fileId = "file_id"
    }
}
```

### Models List

```swift
struct MistralModelsResponse: Codable {
    let object: String
    let data: [MistralModel]
}

struct MistralModel: Codable {
    let id: String
    let object: String
    let created: Int?
    let ownedBy: String?
    var capabilities: ModelCapabilities? = nil
    var maxContextLength: Int? = nil
    var defaultModelTemperature: Double? = nil
    
    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
        case capabilities
        case maxContextLength = "max_context_length"
        case defaultModelTemperature = "default_model_temperature"
    }
}

struct ModelCapabilities: Codable {
    var completionChat: Bool? = nil
    var completionFim: Bool? = nil
    var functionCalling: Bool? = nil
    var fineTuning: Bool? = nil
    var vision: Bool? = nil
    
    enum CodingKeys: String, CodingKey {
        case completionChat = "completion_chat"
        case completionFim = "completion_fim"
        case functionCalling = "function_calling"
        case fineTuning = "fine_tuning"
        case vision
    }
}
```

---

## 🛠️ Swift Service Implementation

```swift
import Foundation

actor MistralAPIService {
    
    // MARK: - Configuration
    
    enum Endpoint: String {
        case primary = "https://api.mistral.ai/v1"
        case codestral = "https://codestral.mistral.ai/v1"
    }
    
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }
    
    // MARK: - Chat Completions
    
    func chatCompletion(_ request: MistralChatRequest) async throws -> MistralChatResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/chat/completions")!
        return try await post(url: url, body: request)
    }
    
    func chatCompletionStream(_ request: MistralChatRequest) -> AsyncThrowingStream<MistralStreamChunk, Error> {
        var streamRequest = request
        streamRequest.stream = true
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(Endpoint.primary.rawValue)/chat/completions")!
                    var urlRequest = try self.makeRequest(url: url, body: streamRequest)
                    
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse,
                          200...299 ~= httpResponse.statusCode else {
                        throw MistralError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            if data == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let jsonData = data.data(using: .utf8),
                               let chunk = try? self.decoder.decode(MistralStreamChunk.self, from: jsonData) {
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
    
    // MARK: - Vision (use with chat completions)
    
    func visionChat(model: String = "mistral-small-latest", 
                    prompt: String, 
                    imageUrl: String) async throws -> MistralChatResponse {
        let request = MistralChatRequest(
            model: model,
            messages: [
                MistralMessage(
                    role: "user",
                    content: .multimodal([
                        ContentPart(type: "text", text: prompt),
                        ContentPart(type: "image_url", imageUrl: ImageURL(url: imageUrl))
                    ])
                )
            ]
        )
        return try await chatCompletion(request)
    }
    
    func visionChatWithBase64(model: String = "mistral-small-latest",
                               prompt: String,
                               imageData: Data,
                               mimeType: String = "image/jpeg") async throws -> MistralChatResponse {
        let base64 = imageData.base64EncodedString()
        let dataUri = "data:\(mimeType);base64,\(base64)"
        return try await visionChat(model: model, prompt: prompt, imageUrl: dataUri)
    }
    
    // MARK: - Audio Chat (Voxtral)
    
    func audioChat(model: String = "voxtral-mini-latest",
                   audioData: Data,
                   textPrompt: String? = nil) async throws -> MistralChatResponse {
        let base64Audio = audioData.base64EncodedString()
        
        var contentParts: [ContentPart] = [
            ContentPart(type: "input_audio", inputAudio: base64Audio)
        ]
        
        if let text = textPrompt {
            contentParts.append(ContentPart(type: "text", text: text))
        }
        
        let request = MistralChatRequest(
            model: model,
            messages: [
                MistralMessage(role: "user", content: .multimodal(contentParts))
            ]
        )
        return try await chatCompletion(request)
    }
    
    // MARK: - Transcription
    
    func transcribe(audioData: Data,
                    fileName: String,
                    model: String = "voxtral-mini-latest",
                    language: String? = nil) async throws -> MistralTranscriptionResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/audio/transcriptions")!
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        
        // Language field (optional)
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse
        }
        guard 200...299 ~= httpResponse.statusCode else {
            throw MistralError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        return try decoder.decode(MistralTranscriptionResponse.self, from: data)
    }
    
    // MARK: - FIM (Code Completion)
    
    func fillInMiddle(_ request: MistralFIMRequest, 
                      useCodestralEndpoint: Bool = true) async throws -> MistralFIMResponse {
        let baseUrl = useCodestralEndpoint ? Endpoint.codestral.rawValue : Endpoint.primary.rawValue
        let url = URL(string: "\(baseUrl)/fim/completions")!
        return try await post(url: url, body: request)
    }
    
    // MARK: - Embeddings
    
    func embeddings(_ request: MistralEmbeddingsRequest) async throws -> MistralEmbeddingsResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/embeddings")!
        return try await post(url: url, body: request)
    }
    
    func embedText(_ texts: [String], model: String = "mistral-embed") async throws -> [[Double]] {
        let request = MistralEmbeddingsRequest(model: model, inputs: texts)
        let response = try await embeddings(request)
        return response.data.sorted(by: { $0.index < $1.index }).map { $0.embedding }
    }
    
    func embedCode(_ code: [String], 
                   model: String = "codestral-embed",
                   dimension: Int? = nil) async throws -> [[Double]] {
        var request = MistralEmbeddingsRequest(model: model, inputs: code)
        request.outputDimension = dimension
        let response = try await embeddings(request)
        return response.data.sorted(by: { $0.index < $1.index }).map { $0.embedding }
    }
    
    // MARK: - OCR
    
    func ocr(_ request: MistralOCRRequest) async throws -> MistralOCRResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/ocr")!
        return try await post(url: url, body: request)
    }
    
    func ocrFromURL(_ documentUrl: String, 
                    includeImages: Bool = false) async throws -> MistralOCRResponse {
        let request = MistralOCRRequest(
            model: "mistral-ocr-latest",
            document: OCRDocument(type: "document_url", documentUrl: documentUrl),
            includeImageBase64: includeImages
        )
        return try await ocr(request)
    }
    
    func ocrFromBase64(_ data: Data, 
                       isImage: Bool = false,
                       includeImages: Bool = false) async throws -> MistralOCRResponse {
        let base64 = data.base64EncodedString()
        let request = MistralOCRRequest(
            model: "mistral-ocr-latest",
            document: OCRDocument(type: "base64", data: base64),
            includeImageBase64: includeImages
        )
        return try await ocr(request)
    }
    
    // MARK: - Reasoning (Magistral)
    
    func reasoningChat(prompt: String,
                       model: String = "magistral-medium-latest",
                       systemPrompt: String? = nil) async throws -> MistralChatResponse {
        var messages: [MistralMessage] = []
        
        if let system = systemPrompt {
            messages.append(MistralMessage(role: "system", content: .text(system)))
        }
        messages.append(MistralMessage(role: "user", content: .text(prompt)))
        
        var request = MistralChatRequest(model: model, messages: messages)
        request.promptMode = "reasoning"  // Enable reasoning mode
        
        return try await chatCompletion(request)
    }
    
    // MARK: - Agents
    
    func createAgent(_ request: MistralAgentCreateRequest) async throws -> MistralAgentResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/agents")!
        return try await post(url: url, body: request)
    }
    
    func startConversation(_ request: MistralConversationStartRequest) async throws -> MistralConversationResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/conversations")!
        return try await post(url: url, body: request)
    }
    
    // MARK: - Models
    
    func listModels() async throws -> MistralModelsResponse {
        let url = URL(string: "\(Endpoint.primary.rawValue)/models")!
        return try await get(url: url)
    }
    
    // MARK: - Files
    
    func downloadFile(fileId: String) async throws -> Data {
        let url = URL(string: "\(Endpoint.primary.rawValue)/files/\(fileId)/content")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw MistralError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return data
    }
    
    // MARK: - Private Helpers
    
    private func makeRequest<T: Encodable>(url: URL, body: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }
    
    private func post<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        let request = try makeRequest(url: url, body: body)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8)
            throw MistralError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        return try decoder.decode(R.self, from: data)
    }
    
    private func get<R: Decodable>(url: URL) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw MistralError.httpError(httpResponse.statusCode)
        }
        
        return try decoder.decode(R.self, from: data)
    }
}

// MARK: - Streaming Types

struct MistralStreamChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [StreamChoice]
}

struct StreamChoice: Codable {
    let index: Int
    let delta: StreamDelta
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

struct StreamDelta: Codable {
    var role: String? = nil
    var content: String? = nil
    var toolCalls: [ToolCall]? = nil
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

// MARK: - Errors

enum MistralError: Error {
    case invalidResponse
    case httpError(Int, String? = nil)
    case decodingError(Error)
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}
```

---

## 📚 Usage Examples

### Basic Chat
```swift
let mistral = MistralAPIService(apiKey: "your-api-key")

let request = MistralChatRequest(
    model: "mistral-small-latest",
    messages: [
        MistralMessage(role: "user", content: .text("Explain quantum computing"))
    ]
)
let response = try await mistral.chatCompletion(request)
print(response.choices.first?.message.content ?? "")
```

### Vision
```swift
let response = try await mistral.visionChat(
    model: "pixtral-large-latest",
    prompt: "Describe this image in detail",
    imageUrl: "https://example.com/image.jpg"
)
```

### Audio Chat
```swift
let audioData = try Data(contentsOf: audioFileURL)
let response = try await mistral.audioChat(
    model: "voxtral-small-latest",
    audioData: audioData,
    textPrompt: "Summarize what was said"
)
```

### Transcription
```swift
let response = try await mistral.transcribe(
    audioData: audioData,
    fileName: "meeting.mp3",
    language: "en"
)
print(response.text)
```

### Code Completion (FIM)
```swift
let request = MistralFIMRequest(
    model: "codestral-latest",
    prompt: "def fibonacci(n):\n    if n <= 1:\n        return n\n    ",
    suffix: "\n\nprint(fibonacci(10))"
)
let response = try await mistral.fillInMiddle(request)
```

### Reasoning
```swift
let response = try await mistral.reasoningChat(
    prompt: "Solve: If all bloops are razzles, and all razzles are lazzles, are all bloops lazzles?",
    model: "magistral-medium-latest"
)
```

### OCR
```swift
let response = try await mistral.ocrFromURL(
    "https://example.com/document.pdf",
    includeImages: true
)
for page in response.pages {
    print(page.markdown)
}
```

### Embeddings
```swift
let embeddings = try await mistral.embedText(["Hello world", "Goodbye world"])
let codeEmbeddings = try await mistral.embedCode(["def hello(): pass"], dimension: 1024)
```

### Streaming
```swift
var request = MistralChatRequest(
    model: "mistral-small-latest",
    messages: [MistralMessage(role: "user", content: .text("Write a poem"))]
)

for try await chunk in mistral.chatCompletionStream(request) {
    if let content = chunk.choices.first?.delta.content {
        print(content, terminator: "")
    }
}
```

### Function Calling
```swift
let request = MistralChatRequest(
    model: "mistral-small-latest",
    messages: [
        MistralMessage(role: "user", content: .text("What's the weather in Paris?"))
    ],
    tools: [
        Tool(type: "function", function: FunctionDefinition(
            name: "get_weather",
            description: "Get weather for a location",
            parameters: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "location": ["type": "string", "description": "City name"]
                ]),
                "required": AnyCodable(["location"])
            ]
        ))
    ],
    toolChoice: .auto
)
```

### Agent with Image Generation
```swift
let agent = try await mistral.createAgent(MistralAgentCreateRequest(
    name: "ImageBot",
    instructions: "You generate images based on user requests",
    tools: [AgentTool(type: "image_generation")]
))

let conversation = try await mistral.startConversation(
    MistralConversationStartRequest(
        agentId: agent.id,
        inputs: "Generate an orange cat in an office"
    )
)

// Download generated image
for output in conversation.outputs {
    for content in output.content ?? [] {
        if content.type == "tool_file", let fileId = content.fileId {
            let imageData = try await mistral.downloadFile(fileId: fileId)
            // Save imageData as PNG
        }
    }
}
```

---

## ⚡ Quick Reference

| Capability | Model | Endpoint |
|------------|-------|----------|
| **Chat** | mistral-small-latest, mistral-medium-latest | /v1/chat/completions |
| **Vision** | pixtral-large-latest, mistral-small-latest, magistral-*-latest | /v1/chat/completions |
| **Audio** | voxtral-small-latest, voxtral-mini-latest | /v1/chat/completions |
| **Transcription** | voxtral-mini-latest | /v1/audio/transcriptions |
| **Reasoning** | magistral-medium-latest, magistral-small-latest | /v1/chat/completions |
| **Code** | codestral-latest, devstral-*-latest | /v1/chat/completions |
| **FIM** | codestral-latest | /v1/fim/completions |
| **OCR** | mistral-ocr-latest | /v1/ocr |
| **Text Embed** | mistral-embed | /v1/embeddings |
| **Code Embed** | codestral-embed | /v1/embeddings |
| **Moderation** | mistral-moderation-latest | /v1/moderations |
| **Agents** | (uses mistral-medium by default) | /v1/agents, /v1/conversations |
| **Image Gen** | (via Agents API with FLUX) | /v1/conversations |

---

## 📝 Notes for Integration

1. **Vision-capable models**: mistral-small-2506+, pixtral-*, magistral-*-2509+
2. **Audio-capable models**: voxtral-small-*, voxtral-mini-*
3. **Reasoning mode**: Set `promptMode: "reasoning"` for Magistral models
4. **Image generation**: Only via Agents API (uses Black Forest Labs FLUX)
5. **FIM endpoint**: Use codestral.mistral.ai for IDE integrations
6. **Embeddings dimensions**: mistral-embed = 1024, codestral-embed = up to 3072
7. **OCR limits**: Max 50MB file, 1000 pages per request
8. **Audio limits**: 30 min for transcription, 40 min for understanding

---

*Generated for LLMHub Swift integration - November 2025*
