//
//  Anthropic_Integration.md
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//
Good timing — let me pull the latest API docs to make sure I'm giving you accurate info. A few quick clarifications while I search:

1. **Image generation** — Claude doesn't generate images natively (that's DALL-E, Midjourney territory). Did you mean *image input/vision* capabilities?
2. **Video** — Same question: do you mean video *input* analysis or something else?
3. **"Flash"** — Are you referring to streaming responses, or the Haiku model (fastest tier)?

Let me grab the current API specs:I've got fresh data. Let me address your initial questions and then provide the comprehensive guide:

**Quick Clarifications:**
- ❌ **Image generation** — Claude doesn't generate images. That's Midjourney/DALL-E territory. Claude *analyzes* images (vision input).
- 📹 **Video** — No native video input. You'd extract frames as images and send those.
- ⚡ **"Flash"** — I'm interpreting this as **streaming responses** (real-time token output).

Now here's your clean, copy-paste ready Swift integration:

---Done! Here's your comprehensive Claude API integration for Swift:

[**Download ClaudeAPIService.swift**](computer:///mnt/user-data/outputs/ClaudeAPIService.swift)

---

## Quick Reference Summary

### 🎯 Current Models (Nov 2025)
| Model | ID | Best For |
|-------|-----|----------|
| Opus 4.5 | `claude-opus-4-5-20251101` | Maximum intelligence |
| Sonnet 4.5 | `claude-sonnet-4-5-20250929` | Best balance (64K output) |
| Haiku 4.5 | `claude-haiku-4-5-20251001` | Speed/cost |

### 🔧 Features Covered
- ✅ **Text completion** (standard + streaming)
- ✅ **Vision** (base64, URL, or Files API)
- ✅ **PDF analysis** (visual + text extraction, up to 100 pages)
- ✅ **Extended thinking** (with `budget_tokens`, min 1024)
- ✅ **Tool use / function calling**
- ✅ **Files API** (persistent file references across requests)
- ✅ **Streaming** (SSE with proper delta handling)

### ⚠️ What Claude *Can't* Do
- ❌ Generate images (no DALL-E equivalent)
- ❌ Process raw video (extract frames → send as images)
- ❌ Text-to-speech / audio generation

### 🏷️ Beta Headers You'll Need
```swift
// For interleaved thinking (thinking between tool calls)
"interleaved-thinking-2025-05-14"

// For Files API
"files-api-2025-04-14"

// For structured JSON outputs
"structured-outputs-2025-11-13"
```

The file includes `ClaudeAPIService` with convenience methods like `.complete()`, `.analyzeImage()`, `.analyzePDF()`, `.thinkAndRespond()`, plus full streaming support. Drop it into LLMHub and wire up the API key. 🚀
                                      // MARK: - Claude API Complete Integration for Swift
                                      // Updated: November 2025
                                      // Supports: Vision, PDF, Extended Thinking, Streaming, Tool Use, Files API

                                      import Foundation

                                      // MARK: - Configuration

                                      struct ClaudeConfig {
                                          static let baseURL = "https://api.anthropic.com/v1"
                                          static let apiVersion = "2023-06-01"
                                          
                                          // Current model IDs (November 2025)
                                          enum Model: String, CaseIterable {
                                              // Flagship
                                              case opus45 = "claude-opus-4-5-20251101"      // Most intelligent
                                              case sonnet45 = "claude-sonnet-4-5-20250929"  // Best balance
                                              case haiku45 = "claude-haiku-4-5-20251001"    // Fastest
                                              
                                              // Previous generation (still available)
                                              case opus4 = "claude-opus-4-20250514"
                                              case sonnet4 = "claude-sonnet-4-20250514"
                                              
                                              var maxOutputTokens: Int {
                                                  switch self {
                                                  case .sonnet45, .sonnet4: return 64_000
                                                  case .opus45, .opus4: return 32_000
                                                  case .haiku45: return 8_192
                                                  }
                                              }
                                              
                                              var contextWindow: Int { 200_000 }  // All models support 200K
                                          }
                                          
                                          // Beta feature headers
                                          enum BetaFeature: String {
                                              case filesAPI = "files-api-2025-04-14"
                                              case interleavedThinking = "interleaved-thinking-2025-05-14"
                                              case fineGrainedToolStreaming = "fine-grained-tool-streaming-2025-05-14"
                                              case structuredOutputs = "structured-outputs-2025-11-13"
                                              case effort = "effort-2025-11-24"
                                          }
                                      }

                                      // MARK: - Request Models

                                      struct ClaudeRequest: Codable {
                                          let model: String
                                          let maxTokens: Int
                                          let messages: [Message]
                                          var system: String?
                                          var temperature: Double?
                                          var topP: Double?
                                          var topK: Int?
                                          var stream: Bool?
                                          var stopSequences: [String]?
                                          var tools: [Tool]?
                                          var toolChoice: ToolChoice?
                                          var thinking: ThinkingConfig?
                                          var metadata: Metadata?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case model
                                              case maxTokens = "max_tokens"
                                              case messages, system, temperature
                                              case topP = "top_p"
                                              case topK = "top_k"
                                              case stream
                                              case stopSequences = "stop_sequences"
                                              case tools
                                              case toolChoice = "tool_choice"
                                              case thinking, metadata
                                          }
                                      }

                                      // MARK: - Message Types

                                      struct Message: Codable {
                                          let role: Role
                                          let content: MessageContent
                                          
                                          enum Role: String, Codable {
                                              case user, assistant
                                          }
                                      }

                                      enum MessageContent: Codable {
                                          case text(String)
                                          case blocks([ContentBlock])
                                          
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.singleValueContainer()
                                              if let text = try? container.decode(String.self) {
                                                  self = .text(text)
                                              } else {
                                                  self = .blocks(try container.decode([ContentBlock].self))
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              var container = encoder.singleValueContainer()
                                              switch self {
                                              case .text(let string):
                                                  try container.encode(string)
                                              case .blocks(let blocks):
                                                  try container.encode(blocks)
                                              }
                                          }
                                      }

                                      // MARK: - Content Blocks (Vision, PDF, Text, Tool Results)

                                      enum ContentBlock: Codable {
                                          case text(TextBlock)
                                          case image(ImageBlock)
                                          case document(DocumentBlock)  // For PDFs
                                          case toolUse(ToolUseBlock)
                                          case toolResult(ToolResultBlock)
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                          }
                                          
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.container(keyedBy: CodingKeys.self)
                                              let type = try container.decode(String.self, forKey: .type)
                                              
                                              switch type {
                                              case "text":
                                                  self = .text(try TextBlock(from: decoder))
                                              case "image":
                                                  self = .image(try ImageBlock(from: decoder))
                                              case "document":
                                                  self = .document(try DocumentBlock(from: decoder))
                                              case "tool_use":
                                                  self = .toolUse(try ToolUseBlock(from: decoder))
                                              case "tool_result":
                                                  self = .toolResult(try ToolResultBlock(from: decoder))
                                              default:
                                                  throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              switch self {
                                              case .text(let block): try block.encode(to: encoder)
                                              case .image(let block): try block.encode(to: encoder)
                                              case .document(let block): try block.encode(to: encoder)
                                              case .toolUse(let block): try block.encode(to: encoder)
                                              case .toolResult(let block): try block.encode(to: encoder)
                                              }
                                          }
                                      }

                                      struct TextBlock: Codable {
                                          let type: String = "text"
                                          let text: String
                                      }

                                      // MARK: - Vision (Image Input)

                                      struct ImageBlock: Codable {
                                          let type: String = "image"
                                          let source: ImageSource
                                      }

                                      enum ImageSource: Codable {
                                          case base64(Base64ImageSource)
                                          case url(URLImageSource)
                                          case file(FileImageSource)  // Files API reference
                                          
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.container(keyedBy: CodingKeys.self)
                                              let type = try container.decode(String.self, forKey: .type)
                                              
                                              switch type {
                                              case "base64":
                                                  self = .base64(try Base64ImageSource(from: decoder))
                                              case "url":
                                                  self = .url(try URLImageSource(from: decoder))
                                              case "file":
                                                  self = .file(try FileImageSource(from: decoder))
                                              default:
                                                  throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown source type")
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              switch self {
                                              case .base64(let source): try source.encode(to: encoder)
                                              case .url(let source): try source.encode(to: encoder)
                                              case .file(let source): try source.encode(to: encoder)
                                              }
                                          }
                                          
                                          enum CodingKeys: String, CodingKey { case type }
                                      }

                                      struct Base64ImageSource: Codable {
                                          let type: String = "base64"
                                          let mediaType: String  // "image/jpeg", "image/png", "image/gif", "image/webp"
                                          let data: String       // Base64 encoded image data
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                              case mediaType = "media_type"
                                              case data
                                          }
                                      }

                                      struct URLImageSource: Codable {
                                          let type: String = "url"
                                          let url: String
                                      }

                                      struct FileImageSource: Codable {
                                          let type: String = "file"
                                          let fileId: String
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                              case fileId = "file_id"
                                          }
                                      }

                                      // MARK: - PDF Support

                                      struct DocumentBlock: Codable {
                                          let type: String = "document"
                                          let source: DocumentSource
                                      }

                                      enum DocumentSource: Codable {
                                          case base64(Base64DocumentSource)
                                          case url(URLDocumentSource)
                                          case file(FileDocumentSource)
                                          
                                          // Similar encoding pattern to ImageSource...
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.container(keyedBy: CodingKeys.self)
                                              let sourceType = try container.decode(String.self, forKey: .type)
                                              switch sourceType {
                                              case "base64": self = .base64(try Base64DocumentSource(from: decoder))
                                              case "url": self = .url(try URLDocumentSource(from: decoder))
                                              case "file": self = .file(try FileDocumentSource(from: decoder))
                                              default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown document source")
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              switch self {
                                              case .base64(let s): try s.encode(to: encoder)
                                              case .url(let s): try s.encode(to: encoder)
                                              case .file(let s): try s.encode(to: encoder)
                                              }
                                          }
                                          
                                          enum CodingKeys: String, CodingKey { case type }
                                      }

                                      struct Base64DocumentSource: Codable {
                                          let type: String = "base64"
                                          let mediaType: String = "application/pdf"
                                          let data: String
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                              case mediaType = "media_type"
                                              case data
                                          }
                                      }

                                      struct URLDocumentSource: Codable {
                                          let type: String = "url"
                                          let url: String
                                      }

                                      struct FileDocumentSource: Codable {
                                          let type: String = "file"
                                          let fileId: String
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                              case fileId = "file_id"
                                          }
                                      }

                                      // MARK: - Extended Thinking

                                      struct ThinkingConfig: Codable {
                                          let type: String           // "enabled" or "disabled"
                                          let budgetTokens: Int?     // Minimum 1024, must be < max_tokens
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                              case budgetTokens = "budget_tokens"
                                          }
                                          
                                          static func enabled(budget: Int) -> ThinkingConfig {
                                              ThinkingConfig(type: "enabled", budgetTokens: max(1024, budget))
                                          }
                                          
                                          static var disabled: ThinkingConfig {
                                              ThinkingConfig(type: "disabled", budgetTokens: nil)
                                          }
                                      }

                                      // MARK: - Tool Use / Function Calling

                                      struct Tool: Codable {
                                          let name: String
                                          let description: String
                                          let inputSchema: InputSchema
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case name, description
                                              case inputSchema = "input_schema"
                                          }
                                      }

                                      struct InputSchema: Codable {
                                          let type: String = "object"
                                          let properties: [String: PropertySchema]
                                          let required: [String]?
                                      }

                                      struct PropertySchema: Codable {
                                          let type: String
                                          let description: String?
                                          let enumValues: [String]?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type, description
                                              case enumValues = "enum"
                                          }
                                      }

                                      enum ToolChoice: Codable {
                                          case auto
                                          case any
                                          case none
                                          case specific(name: String)
                                          
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.singleValueContainer()
                                              if let dict = try? container.decode([String: String].self) {
                                                  if let name = dict["name"] {
                                                      self = .specific(name: name)
                                                  } else if dict["type"] == "auto" {
                                                      self = .auto
                                                  } else if dict["type"] == "any" {
                                                      self = .any
                                                  } else {
                                                      self = .none
                                                  }
                                              } else {
                                                  self = .auto
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              var container = encoder.singleValueContainer()
                                              switch self {
                                              case .auto:
                                                  try container.encode(["type": "auto"])
                                              case .any:
                                                  try container.encode(["type": "any"])
                                              case .none:
                                                  try container.encode(["type": "none"])
                                              case .specific(let name):
                                                  try container.encode(["type": "tool", "name": name])
                                              }
                                          }
                                      }

                                      struct ToolUseBlock: Codable {
                                          let type: String = "tool_use"
                                          let id: String
                                          let name: String
                                          let input: [String: AnyCodable]  // Dynamic JSON
                                      }

                                      struct ToolResultBlock: Codable {
                                          let type: String = "tool_result"
                                          let toolUseId: String
                                          let content: String      // Or can be array of content blocks
                                          let isError: Bool?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type
                                              case toolUseId = "tool_use_id"
                                              case content
                                              case isError = "is_error"
                                          }
                                      }

                                      // MARK: - Metadata

                                      struct Metadata: Codable {
                                          let userId: String?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case userId = "user_id"
                                          }
                                      }

                                      // MARK: - Response Models

                                      struct ClaudeResponse: Codable {
                                          let id: String
                                          let type: String
                                          let role: String
                                          let content: [ResponseContentBlock]
                                          let model: String
                                          let stopReason: String?
                                          let stopSequence: String?
                                          let usage: Usage
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case id, type, role, content, model
                                              case stopReason = "stop_reason"
                                              case stopSequence = "stop_sequence"
                                              case usage
                                          }
                                      }

                                      enum ResponseContentBlock: Codable {
                                          case text(ResponseTextBlock)
                                          case thinking(ThinkingBlock)
                                          case toolUse(ToolUseBlock)
                                          
                                          // Decoding logic similar to ContentBlock...
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.container(keyedBy: CodingKeys.self)
                                              let type = try container.decode(String.self, forKey: .type)
                                              
                                              switch type {
                                              case "text":
                                                  self = .text(try ResponseTextBlock(from: decoder))
                                              case "thinking":
                                                  self = .thinking(try ThinkingBlock(from: decoder))
                                              case "tool_use":
                                                  self = .toolUse(try ToolUseBlock(from: decoder))
                                              default:
                                                  // Fallback to text
                                                  self = .text(ResponseTextBlock(type: "text", text: ""))
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              switch self {
                                              case .text(let block): try block.encode(to: encoder)
                                              case .thinking(let block): try block.encode(to: encoder)
                                              case .toolUse(let block): try block.encode(to: encoder)
                                              }
                                          }
                                          
                                          enum CodingKeys: String, CodingKey { case type }
                                      }

                                      struct ResponseTextBlock: Codable {
                                          let type: String
                                          let text: String
                                      }

                                      struct ThinkingBlock: Codable {
                                          let type: String = "thinking"
                                          let thinking: String       // Summary of thinking (Claude 4 models)
                                          let signature: String?     // Encrypted full thinking
                                      }

                                      struct Usage: Codable {
                                          let inputTokens: Int
                                          let outputTokens: Int
                                          let cacheCreationInputTokens: Int?
                                          let cacheReadInputTokens: Int?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case inputTokens = "input_tokens"
                                              case outputTokens = "output_tokens"
                                              case cacheCreationInputTokens = "cache_creation_input_tokens"
                                              case cacheReadInputTokens = "cache_read_input_tokens"
                                          }
                                      }

                                      // MARK: - Streaming Event Types

                                      enum StreamEvent: Decodable {
                                          case messageStart(MessageStartEvent)
                                          case contentBlockStart(ContentBlockStartEvent)
                                          case contentBlockDelta(ContentBlockDeltaEvent)
                                          case contentBlockStop(ContentBlockStopEvent)
                                          case messageDelta(MessageDeltaEvent)
                                          case messageStop
                                          case ping
                                          case error(StreamError)
                                          
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.container(keyedBy: CodingKeys.self)
                                              let type = try container.decode(String.self, forKey: .type)
                                              
                                              switch type {
                                              case "message_start":
                                                  self = .messageStart(try MessageStartEvent(from: decoder))
                                              case "content_block_start":
                                                  self = .contentBlockStart(try ContentBlockStartEvent(from: decoder))
                                              case "content_block_delta":
                                                  self = .contentBlockDelta(try ContentBlockDeltaEvent(from: decoder))
                                              case "content_block_stop":
                                                  self = .contentBlockStop(try ContentBlockStopEvent(from: decoder))
                                              case "message_delta":
                                                  self = .messageDelta(try MessageDeltaEvent(from: decoder))
                                              case "message_stop":
                                                  self = .messageStop
                                              case "ping":
                                                  self = .ping
                                              case "error":
                                                  self = .error(try StreamError(from: decoder))
                                              default:
                                                  self = .ping  // Fallback
                                              }
                                          }
                                          
                                          enum CodingKeys: String, CodingKey { case type }
                                      }

                                      struct MessageStartEvent: Decodable {
                                          let type: String
                                          let message: PartialMessage
                                      }

                                      struct PartialMessage: Decodable {
                                          let id: String
                                          let type: String
                                          let role: String
                                          let model: String
                                          let usage: Usage?
                                      }

                                      struct ContentBlockStartEvent: Decodable {
                                          let type: String
                                          let index: Int
                                          let contentBlock: ResponseContentBlock
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type, index
                                              case contentBlock = "content_block"
                                          }
                                      }

                                      struct ContentBlockDeltaEvent: Decodable {
                                          let type: String
                                          let index: Int
                                          let delta: DeltaContent
                                      }

                                      struct DeltaContent: Decodable {
                                          let type: String
                                          let text: String?
                                          let thinking: String?
                                          let partialJson: String?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case type, text, thinking
                                              case partialJson = "partial_json"
                                          }
                                      }

                                      struct ContentBlockStopEvent: Decodable {
                                          let type: String
                                          let index: Int
                                      }

                                      struct MessageDeltaEvent: Decodable {
                                          let type: String
                                          let delta: MessageDelta
                                          let usage: Usage?
                                      }

                                      struct MessageDelta: Decodable {
                                          let stopReason: String?
                                          let stopSequence: String?
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case stopReason = "stop_reason"
                                              case stopSequence = "stop_sequence"
                                          }
                                      }

                                      struct StreamError: Decodable {
                                          let type: String
                                          let error: APIError
                                      }

                                      struct APIError: Decodable {
                                          let type: String
                                          let message: String
                                      }

                                      // MARK: - Files API Models (Beta)

                                      struct FileUploadResponse: Codable {
                                          let id: String        // "file_abc123"
                                          let type: String
                                          let filename: String
                                          let mimeType: String
                                          let sizeBytes: Int
                                          let createdAt: String
                                          
                                          enum CodingKeys: String, CodingKey {
                                              case id, type, filename
                                              case mimeType = "mime_type"
                                              case sizeBytes = "size_bytes"
                                              case createdAt = "created_at"
                                          }
                                      }

                                      // MARK: - API Service

                                      @MainActor
                                      class ClaudeAPIService: ObservableObject {
                                          
                                          private let apiKey: String
                                          private let session: URLSession
                                          private let encoder: JSONEncoder
                                          private let decoder: JSONDecoder
                                          
                                          @Published var isLoading = false
                                          @Published var lastError: Error?
                                          
                                          init(apiKey: String) {
                                              self.apiKey = apiKey
                                              
                                              let config = URLSessionConfiguration.default
                                              config.timeoutIntervalForRequest = 300  // 5 min for extended thinking
                                              config.timeoutIntervalForResource = 600
                                              self.session = URLSession(configuration: config)
                                              
                                              self.encoder = JSONEncoder()
                                              self.decoder = JSONDecoder()
                                          }
                                          
                                          // MARK: - Standard Request
                                          
                                          func sendMessage(
                                              _ request: ClaudeRequest,
                                              betaFeatures: [ClaudeConfig.BetaFeature] = []
                                          ) async throws -> ClaudeResponse {
                                              var urlRequest = try buildRequest(endpoint: "/messages", betaFeatures: betaFeatures)
                                              urlRequest.httpBody = try encoder.encode(request)
                                              
                                              let (data, response) = try await session.data(for: urlRequest)
                                              try validateResponse(response)
                                              
                                              return try decoder.decode(ClaudeResponse.self, from: data)
                                          }
                                          
                                          // MARK: - Streaming Request
                                          
                                          func streamMessage(
                                              _ request: ClaudeRequest,
                                              betaFeatures: [ClaudeConfig.BetaFeature] = []
                                          ) -> AsyncThrowingStream<StreamEvent, Error> {
                                              AsyncThrowingStream { continuation in
                                                  Task {
                                                      do {
                                                          var streamRequest = request
                                                          streamRequest.stream = true
                                                          
                                                          var urlRequest = try buildRequest(endpoint: "/messages", betaFeatures: betaFeatures)
                                                          urlRequest.httpBody = try encoder.encode(streamRequest)
                                                          
                                                          let (bytes, response) = try await session.bytes(for: urlRequest)
                                                          try validateResponse(response)
                                                          
                                                          var buffer = ""
                                                          
                                                          for try await byte in bytes {
                                                              buffer.append(Character(UnicodeScalar(byte)))
                                                              
                                                              // SSE format: "data: {...}\n\n"
                                                              while let range = buffer.range(of: "\n\n") {
                                                                  let line = String(buffer[..<range.lowerBound])
                                                                  buffer.removeSubrange(..<range.upperBound)
                                                                  
                                                                  if line.hasPrefix("data: ") {
                                                                      let jsonStr = String(line.dropFirst(6))
                                                                      if jsonStr == "[DONE]" {
                                                                          continuation.finish()
                                                                          return
                                                                      }
                                                                      
                                                                      if let jsonData = jsonStr.data(using: .utf8),
                                                                         let event = try? decoder.decode(StreamEvent.self, from: jsonData) {
                                                                          continuation.yield(event)
                                                                      }
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
                                          
                                          // MARK: - Files API (Beta)
                                          
                                          func uploadFile(
                                              data: Data,
                                              filename: String,
                                              mimeType: String
                                          ) async throws -> FileUploadResponse {
                                              let boundary = UUID().uuidString
                                              var urlRequest = try buildRequest(
                                                  endpoint: "/files",
                                                  betaFeatures: [.filesAPI]
                                              )
                                              urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                                              
                                              var body = Data()
                                              body.append("--\(boundary)\r\n".data(using: .utf8)!)
                                              body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                                              body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                                              body.append(data)
                                              body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                                              
                                              urlRequest.httpBody = body
                                              
                                              let (responseData, response) = try await session.data(for: urlRequest)
                                              try validateResponse(response)
                                              
                                              return try decoder.decode(FileUploadResponse.self, from: responseData)
                                          }
                                          
                                          // MARK: - Convenience Methods
                                          
                                          /// Simple text completion
                                          func complete(
                                              prompt: String,
                                              model: ClaudeConfig.Model = .sonnet45,
                                              system: String? = nil,
                                              maxTokens: Int = 4096
                                          ) async throws -> String {
                                              let request = ClaudeRequest(
                                                  model: model.rawValue,
                                                  maxTokens: maxTokens,
                                                  messages: [Message(role: .user, content: .text(prompt))],
                                                  system: system
                                              )
                                              
                                              let response = try await sendMessage(request)
                                              return extractText(from: response)
                                          }
                                          
                                          /// Vision: Analyze image
                                          func analyzeImage(
                                              imageData: Data,
                                              mimeType: String,
                                              prompt: String,
                                              model: ClaudeConfig.Model = .sonnet45
                                          ) async throws -> String {
                                              let base64 = imageData.base64EncodedString()
                                              let imageSource = ImageSource.base64(Base64ImageSource(mediaType: mimeType, data: base64))
                                              
                                              let content: [ContentBlock] = [
                                                  .image(ImageBlock(source: imageSource)),
                                                  .text(TextBlock(text: prompt))
                                              ]
                                              
                                              let request = ClaudeRequest(
                                                  model: model.rawValue,
                                                  maxTokens: 4096,
                                                  messages: [Message(role: .user, content: .blocks(content))]
                                              )
                                              
                                              let response = try await sendMessage(request)
                                              return extractText(from: response)
                                          }
                                          
                                          /// PDF Analysis
                                          func analyzePDF(
                                              pdfData: Data,
                                              prompt: String,
                                              model: ClaudeConfig.Model = .sonnet45
                                          ) async throws -> String {
                                              let base64 = pdfData.base64EncodedString()
                                              let docSource = DocumentSource.base64(Base64DocumentSource(data: base64))
                                              
                                              let content: [ContentBlock] = [
                                                  .document(DocumentBlock(source: docSource)),
                                                  .text(TextBlock(text: prompt))
                                              ]
                                              
                                              let request = ClaudeRequest(
                                                  model: model.rawValue,
                                                  maxTokens: 8192,
                                                  messages: [Message(role: .user, content: .blocks(content))]
                                              )
                                              
                                              let response = try await sendMessage(request)
                                              return extractText(from: response)
                                          }
                                          
                                          /// Extended Thinking
                                          func thinkAndRespond(
                                              prompt: String,
                                              thinkingBudget: Int = 8192,
                                              model: ClaudeConfig.Model = .sonnet45
                                          ) async throws -> (thinking: String?, response: String) {
                                              let request = ClaudeRequest(
                                                  model: model.rawValue,
                                                  maxTokens: 16384,
                                                  messages: [Message(role: .user, content: .text(prompt))],
                                                  thinking: .enabled(budget: thinkingBudget)
                                              )
                                              
                                              let response = try await sendMessage(request)
                                              
                                              var thinkingSummary: String?
                                              var responseText = ""
                                              
                                              for block in response.content {
                                                  switch block {
                                                  case .thinking(let t):
                                                      thinkingSummary = t.thinking
                                                  case .text(let t):
                                                      responseText = t.text
                                                  case .toolUse:
                                                      break
                                                  }
                                              }
                                              
                                              return (thinkingSummary, responseText)
                                          }
                                          
                                          // MARK: - Private Helpers
                                          
                                          private func buildRequest(
                                              endpoint: String,
                                              betaFeatures: [ClaudeConfig.BetaFeature]
                                          ) throws -> URLRequest {
                                              guard let url = URL(string: ClaudeConfig.baseURL + endpoint) else {
                                                  throw URLError(.badURL)
                                              }
                                              
                                              var request = URLRequest(url: url)
                                              request.httpMethod = "POST"
                                              request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                                              request.setValue(ClaudeConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
                                              request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                                              
                                              if !betaFeatures.isEmpty {
                                                  let betaHeader = betaFeatures.map(\.rawValue).joined(separator: ",")
                                                  request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
                                              }
                                              
                                              return request
                                          }
                                          
                                          private func validateResponse(_ response: URLResponse) throws {
                                              guard let httpResponse = response as? HTTPURLResponse else {
                                                  throw URLError(.badServerResponse)
                                              }
                                              
                                              guard (200...299).contains(httpResponse.statusCode) else {
                                                  throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode)
                                              }
                                          }
                                          
                                          private func extractText(from response: ClaudeResponse) -> String {
                                              response.content.compactMap { block in
                                                  if case .text(let textBlock) = block {
                                                      return textBlock.text
                                                  }
                                                  return nil
                                              }.joined()
                                          }
                                      }

                                      // MARK: - Errors

                                      enum ClaudeAPIError: LocalizedError {
                                          case httpError(statusCode: Int)
                                          case invalidResponse
                                          case rateLimited
                                          case overloaded
                                          
                                          var errorDescription: String? {
                                              switch self {
                                              case .httpError(let code):
                                                  switch code {
                                                  case 400: return "Bad request - check your parameters"
                                                  case 401: return "Invalid API key"
                                                  case 403: return "Forbidden - check permissions"
                                                  case 404: return "Endpoint not found"
                                                  case 429: return "Rate limited - slow down"
                                                  case 500: return "Server error"
                                                  case 529: return "API overloaded - try again"
                                                  default: return "HTTP error: \(code)"
                                                  }
                                              case .invalidResponse: return "Invalid response format"
                                              case .rateLimited: return "Rate limited"
                                              case .overloaded: return "API overloaded"
                                              }
                                          }
                                      }

                                      // MARK: - Helper for Dynamic JSON

                                      struct AnyCodable: Codable {
                                          let value: Any
                                          
                                          init(_ value: Any) {
                                              self.value = value
                                          }
                                          
                                          init(from decoder: Decoder) throws {
                                              let container = try decoder.singleValueContainer()
                                              
                                              if let bool = try? container.decode(Bool.self) {
                                                  value = bool
                                              } else if let int = try? container.decode(Int.self) {
                                                  value = int
                                              } else if let double = try? container.decode(Double.self) {
                                                  value = double
                                              } else if let string = try? container.decode(String.self) {
                                                  value = string
                                              } else if let array = try? container.decode([AnyCodable].self) {
                                                  value = array.map(\.value)
                                              } else if let dict = try? container.decode([String: AnyCodable].self) {
                                                  value = dict.mapValues(\.value)
                                              } else {
                                                  value = NSNull()
                                              }
                                          }
                                          
                                          func encode(to encoder: Encoder) throws {
                                              var container = encoder.singleValueContainer()
                                              
                                              switch value {
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
                                              case let dict as [String: Any]:
                                                  try container.encode(dict.mapValues { AnyCodable($0) })
                                              default:
                                                  try container.encodeNil()
                                              }
                                          }
                                      }

                                      // MARK: - Usage Examples

                                      /*
                                       
                                       // 1. Basic completion
                                       let api = ClaudeAPIService(apiKey: "sk-ant-...")
                                       let response = try await api.complete(prompt: "Explain quantum computing")
                                       
                                       // 2. Streaming
                                       for try await event in api.streamMessage(request) {
                                           if case .contentBlockDelta(let delta) = event,
                                              let text = delta.delta.text {
                                               print(text, terminator: "")
                                           }
                                       }
                                       
                                       // 3. Vision
                                       let imageData = try Data(contentsOf: imageURL)
                                       let analysis = try await api.analyzeImage(
                                           imageData: imageData,
                                           mimeType: "image/jpeg",
                                           prompt: "What's in this image?"
                                       )
                                       
                                       // 4. PDF
                                       let pdfData = try Data(contentsOf: pdfURL)
                                       let summary = try await api.analyzePDF(
                                           pdfData: pdfData,
                                           prompt: "Summarize this document"
                                       )
                                       
                                       // 5. Extended Thinking
                                       let (thinking, answer) = try await api.thinkAndRespond(
                                           prompt: "Solve this complex problem...",
                                           thinkingBudget: 16384
                                       )
                                       
                                       // 6. Tool Use
                                       let weatherTool = Tool(
                                           name: "get_weather",
                                           description: "Get current weather for a location",
                                           inputSchema: InputSchema(
                                               properties: [
                                                   "location": PropertySchema(type: "string", description: "City name", enumValues: nil)
                                               ],
                                               required: ["location"]
                                           )
                                       )
                                       
                                       let request = ClaudeRequest(
                                           model: ClaudeConfig.Model.sonnet45.rawValue,
                                           maxTokens: 1024,
                                           messages: [Message(role: .user, content: .text("What's the weather in Paris?"))],
                                           tools: [weatherTool]
                                       )
                                       
                                       let response = try await api.sendMessage(request)
                                       // Check for tool_use in response.content, execute tool, send tool_result back
                                       
                                       // 7. Files API (persistent file reference)
                                       let fileResponse = try await api.uploadFile(
                                           data: pdfData,
                                           filename: "document.pdf",
                                           mimeType: "application/pdf",
                                           betaFeatures: [.filesAPI]
                                       )
                                       // Use fileResponse.id in subsequent requests
                                       
                                       */
//
//  anthropic_integration.md
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//

