# Mistral AI API - Complete Swift Integration Reference
## Verified November 2025

---

## 1. BASE CONFIGURATION

```swift
// Primary API
let baseURL = "https://api.mistral.ai/v1"

// Codestral-specific (for IDE integrations)
let codestralURL = "https://codestral.mistral.ai/v1"

// Headers
let headers = [
    "Authorization": "Bearer \(apiKey)",
    "Content-Type": "application/json"
]
```

---

## 2. CHAT COMPLETIONS

### Endpoint
```
POST /v1/chat/completions
```

### Complete Request Schema
```swift
struct MistralChatRequest: Codable {
    let model: String
    let messages: [MistralMessage]
    var temperature: Double?           // 0.0-1.0, default varies by model
    var topP: Double?                  // default: 1
    var maxTokens: Int?
    var minTokens: Int?
    var stream: Bool?                  // default: false
    var stop: [String]?
    var randomSeed: Int?
    var responseFormat: ResponseFormat?
    var tools: [Tool]?
    var toolChoice: ToolChoice?
    var presencePenalty: Double?       // default: 0
    var frequencyPenalty: Double?      // default: 0
    var n: Int?                        // number of completions
    var safePrompt: Bool?              // default: false
    var prediction: Prediction?
    var parallelToolCalls: Bool?       // default: true
    var promptMode: String?            // "reasoning" for Magistral models
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, stop, tools, n
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case minTokens = "min_tokens"
        case randomSeed = "random_seed"
        case responseFormat = "response_format"
        case toolChoice = "tool_choice"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case safePrompt = "safe_prompt"
        case prediction
        case parallelToolCalls = "parallel_tool_calls"
        case promptMode = "prompt_mode"
    }
}

struct ResponseFormat: Codable {
    let type: String  // "text" | "json_object" | "json_schema"
    var jsonSchema: JSONSchema?
    
    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

struct Prediction: Codable {
    let type: String  // "content"
    let content: String
}
```

### Message Types
```swift
enum MistralMessage: Codable {
    case system(SystemMessage)
    case user(UserMessage)
    case assistant(AssistantMessage)
    case tool(ToolMessage)
}

struct SystemMessage: Codable {
    let role: String = "system"
    let content: String
}

struct UserMessage: Codable {
    let role: String = "user"
    let content: UserContent
}

// Content can be string OR array for multimodal
enum UserContent: Codable {
    case text(String)
    case parts([ContentPart])
}

enum ContentPart: Codable {
    case text(TextPart)
    case imageUrl(ImageUrlPart)
    case inputAudio(InputAudioPart)
}

struct TextPart: Codable {
    let type: String = "text"
    let text: String
}

struct ImageUrlPart: Codable {
    let type: String = "image_url"
    let imageUrl: ImageUrlContent
    
    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
    }
}

struct ImageUrlContent: Codable {
    let url: String  // URL or data:image/jpeg;base64,{base64}
}

struct InputAudioPart: Codable {
    let type: String = "input_audio"
    let inputAudio: String  // base64 encoded OR URL
    
    enum CodingKeys: String, CodingKey {
        case type
        case inputAudio = "input_audio"
    }
}

struct AssistantMessage: Codable {
    let role: String = "assistant"
    var content: String?
    var toolCalls: [ToolCall]?
    var prefix: Bool?
    
    enum CodingKeys: String, CodingKey {
        case role, content, prefix
        case toolCalls = "tool_calls"
    }
}

struct ToolMessage: Codable {
    let role: String = "tool"
    let content: String
    let toolCallId: String
    var name: String?
    
    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCallId = "tool_call_id"
    }
}
```

### Tool Calling Structures
```swift
struct Tool: Codable {
    let type: String = "function"
    let function: FunctionDefinition
}

struct FunctionDefinition: Codable {
    let name: String
    let description: String
    let parameters: JSONSchema
}

struct JSONSchema: Codable {
    let type: String
    var properties: [String: PropertySchema]?
    var required: [String]?
}

struct PropertySchema: Codable {
    let type: String
    var description: String?
    var `enum`: [String]?
}

// tool_choice can be string OR object
enum ToolChoice: Codable {
    case none           // "none"
    case auto           // "auto"
    case any            // "any" or "required"
    case specific(ToolChoiceSpecific)
}

struct ToolChoiceSpecific: Codable {
    let type: String = "function"
    let function: ToolChoiceFunction
}

struct ToolChoiceFunction: Codable {
    let name: String
}
```

### Response Schema
```swift
struct MistralChatResponse: Codable {
    let id: String
    let object: String           // "chat.completion"
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
}

struct Choice: Codable {
    let index: Int
    let message: AssistantMessage
    let finishReason: String?    // "stop" | "length" | "tool_calls"
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct ToolCall: Codable {
    let id: String
    let type: String             // "function"
    let function: FunctionCall
}

struct FunctionCall: Codable {
    let name: String
    let arguments: String        // JSON string
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

### cURL - Basic Chat
```bash
curl https://api.mistral.ai/v1/chat/completions \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'
```

---

## 3. STREAMING

### SSE Chunk Schema
```swift
// Each chunk is prefixed with "data: " and ends with "\n\n"
// Final chunk is "data: [DONE]\n\n"

struct StreamChunk: Codable {
    let id: String
    let object: String           // "chat.completion.chunk"
    let created: Int
    let model: String
    let choices: [StreamChoice]
    let usage: Usage?            // Only in final chunk
    var p: String?               // Security padding (since Nov 2025)
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
    var role: String?
    var content: String?
    var toolCalls: [StreamToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

// Tool calls in stream come as deltas with index
struct StreamToolCall: Codable {
    let index: Int
    var id: String?
    var type: String?
    var function: StreamFunctionCall?
}

struct StreamFunctionCall: Codable {
    var name: String?
    var arguments: String?       // Streamed incrementally
}
```

### SSE Example Stream
```
data: {"id":"cmpl-xxx","object":"chat.completion.chunk","created":1234567890,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"cmpl-xxx","object":"chat.completion.chunk","created":1234567890,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"cmpl-xxx","object":"chat.completion.chunk","created":1234567890,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

data: {"id":"cmpl-xxx","object":"chat.completion.chunk","created":1234567890,"model":"mistral-small-latest","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}

data: [DONE]
```

### Tool Calls in Stream
```
data: {"id":"cmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_abc123","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}

data: {"id":"cmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"location\":"}}]}}]}

data: {"id":"cmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"Paris\"}"}}]}}]}

data: {"id":"cmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]
```

---

## 4. VISION

### Request - URL
```bash
curl https://api.mistral.ai/v1/chat/completions \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "What is in this image?"},
          {"type": "image_url", "image_url": "https://example.com/image.jpg"}
        ]
      }
    ]
  }'
```

### Request - Base64
```bash
curl https://api.mistral.ai/v1/chat/completions \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "pixtral-large-latest",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Describe this image"},
          {"type": "image_url", "image_url": "data:image/jpeg;base64,/9j/4AAQSkZJRg..."}
        ]
      }
    ]
  }'
```

### Vision-Capable Models
- `pixtral-12b-latest` (pixtral-12b-2409)
- `pixtral-large-latest` (pixtral-large-2411)
- `mistral-small-latest` (mistral-small-2506)
- `mistral-medium-latest` (mistral-medium-2508)
- `magistral-medium-latest` (magistral-medium-2509)
- `magistral-small-latest` (magistral-small-2509)

---

## 5. AUDIO CHAT (Voxtral)

### Request - Base64
```bash
curl https://api.mistral.ai/v1/chat/completions \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "voxtral-mini-latest",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "input_audio", "input_audio": "<base64_audio_data>"},
          {"type": "text", "text": "What is in this file?"}
        ]
      }
    ]
  }'
```

### Request - URL
```bash
curl https://api.mistral.ai/v1/chat/completions \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "voxtral-small-latest",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "input_audio", "input_audio": "https://example.com/audio.mp3"},
          {"type": "text", "text": "Transcribe and summarize this audio"}
        ]
      }
    ]
  }'
```

### Audio-Capable Models
- `voxtral-small-latest` (voxtral-small-2507) - 24B params
- `voxtral-mini-latest` (voxtral-mini-2507) - 3B params

### Limits
- Chat with audio: ~20 minutes max
- Transcription: ~15 minutes max

---

## 6. TRANSCRIPTION

### Endpoint
```
POST /v1/audio/transcriptions
Content-Type: multipart/form-data
```

### Request Schema
```swift
struct MistralTranscriptionRequest {
    // Multipart form fields:
    let file: Data?              // Audio file data (optional if file_url provided)
    let fileUrl: String?         // OR remote URL
    let model: String            // "voxtral-mini-latest"
    var language: String?        // Optional ISO language code
    var timestampGranularities: [String]?  // ["segment"]
}
```

### cURL - File Upload
```bash
curl https://api.mistral.ai/v1/audio/transcriptions \
  -H "x-api-key: $MISTRAL_API_KEY" \
  -F 'file=@"/path/to/audio.mp3"' \
  -F 'model="voxtral-mini-latest"'
```

### cURL - URL
```bash
curl https://api.mistral.ai/v1/audio/transcriptions \
  -H "x-api-key: $MISTRAL_API_KEY" \
  -F 'file_url="https://example.com/audio.mp3"' \
  -F 'model="voxtral-mini-latest"'
```

### cURL - With Timestamps
```bash
curl https://api.mistral.ai/v1/audio/transcriptions \
  -H "x-api-key: $MISTRAL_API_KEY" \
  -F 'file_url="https://example.com/audio.mp3"' \
  -F 'model="voxtral-mini-latest"' \
  -F 'timestamp_granularities="segment"'
```

### Response Schema
```swift
struct MistralTranscriptionResponse: Codable {
    let model: String
    let text: String
    var language: String?
    var segments: [TranscriptionSegment]?
    let usage: TranscriptionUsage?
}

struct TranscriptionSegment: Codable {
    let text: String
    let start: Double            // seconds
    let end: Double              // seconds
}

struct TranscriptionUsage: Codable {
    let promptAudioSeconds: Int?
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptAudioSeconds = "prompt_audio_seconds"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
```

### Response Example
```json
{
  "model": "voxtral-mini-2507",
  "text": "This week, I traveled to Chicago...",
  "language": "en",
  "segments": [
    {"text": "This week, I traveled to Chicago", "start": 0.8, "end": 6.2},
    {"text": "to deliver my final farewell address", "start": 6.2, "end": 9.0}
  ],
  "usage": {
    "prompt_audio_seconds": 203,
    "prompt_tokens": 4,
    "total_tokens": 3264,
    "completion_tokens": 635
  }
}
```

---

## 7. FIM (Fill-in-the-Middle)

### Endpoint
```
POST /v1/fim/completions
```

### Request Schema
```swift
struct MistralFIMRequest: Codable {
    let model: String            // "codestral-latest"
    let prompt: String           // Code before cursor
    var suffix: String?          // Code after cursor
    var maxTokens: Int?
    var minTokens: Int?
    var temperature: Double?
    var topP: Double?
    var stop: [String]?
    var randomSeed: Int?
    var stream: Bool?
    
    enum CodingKeys: String, CodingKey {
        case model, prompt, suffix, temperature, stop, stream
        case maxTokens = "max_tokens"
        case minTokens = "min_tokens"
        case topP = "top_p"
        case randomSeed = "random_seed"
    }
}
```

### cURL
```bash
curl https://api.mistral.ai/v1/fim/completions \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codestral-latest",
    "prompt": "def add_numbers(a: int, b: int) -> int:\n    ",
    "suffix": "\n    return result"
  }'
```

### Response Schema
```swift
struct MistralFIMResponse: Codable {
    let id: String
    let object: String           // "chat.completion"
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
    let role: String
    let content: String
    var toolCalls: [ToolCall]?
    var prefix: Bool?
    
    enum CodingKeys: String, CodingKey {
        case role, content, prefix
        case toolCalls = "tool_calls"
    }
}
```

### Response Example
```json
{
  "id": "447e3e0d457e42e98248b5d2ef52a2a3",
  "object": "chat.completion",
  "model": "codestral-2508",
  "usage": {"prompt_tokens": 8, "completion_tokens": 91, "total_tokens": 99},
  "created": 1759496862,
  "choices": [{
    "index": 0,
    "message": {
      "content": "result = a + b",
      "role": "assistant"
    },
    "finish_reason": "stop"
  }]
}
```

---

## 8. EMBEDDINGS

### Endpoint
```
POST /v1/embeddings
```

### Request Schema
```swift
struct MistralEmbeddingsRequest: Codable {
    let model: String            // "mistral-embed" or "codestral-embed"
    let input: EmbeddingInput    // String or [String]
    var encodingFormat: String?  // "float" | "base64"
    var outputDimension: Int?    // Custom dimension (codestral-embed only)
    var outputDtype: String?     // "float" | "int8" | "uint8" | "binary" | "ubinary"
    
    enum CodingKeys: String, CodingKey {
        case model, input
        case encodingFormat = "encoding_format"
        case outputDimension = "output_dimension"
        case outputDtype = "output_dtype"
    }
}

enum EmbeddingInput: Codable {
    case single(String)
    case batch([String])
}
```

### cURL
```bash
curl https://api.mistral.ai/v1/embeddings \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-embed",
    "input": ["Embed this sentence.", "As well as this one."]
  }'
```

### Response Schema
```swift
struct MistralEmbeddingsResponse: Codable {
    let id: String
    let object: String           // "list"
    let model: String
    let data: [EmbeddingData]
    let usage: EmbeddingUsage
}

struct EmbeddingData: Codable {
    let object: String           // "embedding"
    let index: Int
    let embedding: [Double]
}

struct EmbeddingUsage: Codable {
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

### Response Example
```json
{
  "id": "embd-xxx",
  "object": "list",
  "model": "mistral-embed",
  "data": [
    {"object": "embedding", "index": 0, "embedding": [-0.0166, 0.0701, ...]},
    {"object": "embedding", "index": 1, "embedding": [-0.0230, 0.0393, ...]}
  ],
  "usage": {"prompt_tokens": 15, "completion_tokens": 0, "total_tokens": 15}
}
```

### Embedding Models
- `mistral-embed` - 1024 dimensions (text)
- `codestral-embed` - up to 3072 dimensions (code), supports custom dimensions

---

## 9. OCR

### Endpoint
```
POST /v1/ocr
```

### Request Schema
```swift
struct MistralOCRRequest: Codable {
    let model: String            // "mistral-ocr-latest"
    let document: OCRDocument
    var pages: String?           // "0", "0-5", "0,2,4"
    var includeImageBase64: Bool?
    var imageLimit: Int?
    var imageMinSize: Int?
    var bboxAnnotationFormat: ResponseFormat?
    var documentAnnotationFormat: ResponseFormat?
    
    enum CodingKeys: String, CodingKey {
        case model, document, pages
        case includeImageBase64 = "include_image_base64"
        case imageLimit = "image_limit"
        case imageMinSize = "image_min_size"
        case bboxAnnotationFormat = "bbox_annotation_format"
        case documentAnnotationFormat = "document_annotation_format"
    }
}

enum OCRDocument: Codable {
    case documentUrl(DocumentUrlSource)
    case imageUrl(ImageUrlSource)
    case fileId(FileIdSource)
}

struct DocumentUrlSource: Codable {
    let type: String = "document_url"
    let documentUrl: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case documentUrl = "document_url"
    }
}

struct ImageUrlSource: Codable {
    let type: String = "image_url"
    let imageUrl: ImageUrlContent
    
    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
    }
}

struct FileIdSource: Codable {
    let type: String = "file_id"
    let fileId: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case fileId = "file_id"
    }
}
```

### cURL - URL
```bash
curl https://api.mistral.ai/v1/ocr \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-ocr-latest",
    "document": {
      "type": "document_url",
      "document_url": "https://arxiv.org/pdf/2201.04234"
    }
  }'
```

### cURL - Image
```bash
curl https://api.mistral.ai/v1/ocr \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-ocr-latest",
    "document": {
      "type": "image_url",
      "image_url": {"url": "https://example.com/document.png"}
    },
    "include_image_base64": true
  }'
```

### Response Schema
```swift
struct MistralOCRResponse: Codable {
    let model: String
    let pages: [OCRPage]
    var documentAnnotation: String?
    let usageInfo: OCRUsageInfo?
    
    enum CodingKeys: String, CodingKey {
        case model, pages
        case documentAnnotation = "document_annotation"
        case usageInfo = "usage_info"
    }
}

struct OCRPage: Codable {
    let index: Int
    let markdown: String
    let images: [OCRImage]
    let dimensions: OCRDimensions?
}

struct OCRImage: Codable {
    let id: String
    let topLeftX: Int
    let topLeftY: Int
    let bottomRightX: Int
    let bottomRightY: Int
    var imageBase64: String?
    
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
    let dpi: Int?
    let height: Int?
    let width: Int?
}

struct OCRUsageInfo: Codable {
    let pagesProcessed: Int?
    let docSizeBytes: Int?
    
    enum CodingKeys: String, CodingKey {
        case pagesProcessed = "pages_processed"
        case docSizeBytes = "doc_size_bytes"
    }
}
```

### Limits
- Max file size: 50MB
- Max pages: 1000 per request

---

## 10. AGENTS API (Beta)

### Create Agent
```
POST /v1/agents
```

### Request Schema
```swift
struct MistralAgentCreateRequest: Codable {
    let model: String
    let name: String
    var description: String?
    var instructions: String?
    var tools: [AgentTool]?
    var handoffs: [String]?
    var completionArgs: AgentCompletionArgs?
    
    enum CodingKeys: String, CodingKey {
        case model, name, description, instructions, tools, handoffs
        case completionArgs = "completion_args"
    }
}

enum AgentTool: Codable {
    case function(Tool)
    case webSearch(WebSearchTool)
    case codeInterpreter(CodeInterpreterTool)
    case imageGeneration(ImageGenerationTool)
    case documentLibrary(DocumentLibraryTool)
}

struct WebSearchTool: Codable {
    let type: String = "web_search"  // or "web_search_premium"
}

struct CodeInterpreterTool: Codable {
    let type: String = "code_interpreter"
}

struct ImageGenerationTool: Codable {
    let type: String = "image_generation"
}

struct DocumentLibraryTool: Codable {
    let type: String = "document_library"
    let libraryIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case type
        case libraryIds = "library_ids"
    }
}

struct AgentCompletionArgs: Codable {
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    var randomSeed: Int?
    var stop: [String]?
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var responseFormat: ResponseFormat?
    var toolChoice: String?
    var prediction: Prediction?
    
    enum CodingKeys: String, CodingKey {
        case temperature, stop, prediction
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case randomSeed = "random_seed"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case responseFormat = "response_format"
        case toolChoice = "tool_choice"
    }
}
```

### cURL - Create Agent
```bash
curl https://api.mistral.ai/v1/agents \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-medium-2505",
    "name": "Image Generator",
    "description": "An agent that generates images",
    "tools": [{"type": "image_generation"}]
  }'
```

### Agent Response
```json
{
  "id": "ag_06835a34f2c476518000c372a505c2c4",
  "object": "agent",
  "model": "mistral-medium-2505",
  "name": "Image Generator",
  "description": "An agent that generates images",
  "version": 0,
  "created_at": "2025-05-27T11:34:39.175924Z",
  "updated_at": "2025-05-27T11:34:39.175926Z",
  "tools": [{"type": "image_generation"}],
  "completion_args": {
    "temperature": 0.3,
    "tool_choice": "auto"
  }
}
```

---

## 11. CONVERSATIONS API (Beta)

### Start Conversation
```
POST /v1/conversations
```

### Request Schema
```swift
struct MistralConversationRequest: Codable {
    var agentId: String?         // Use existing agent
    var model: String?           // OR specify model directly
    let inputs: ConversationInputs
    var stream: Bool?
    var store: Bool?             // Store in cloud (default: true)
    var handoffExecution: String?  // "server" | "client"
    var tools: [AgentTool]?      // For model-only conversations
    
    enum CodingKeys: String, CodingKey {
        case inputs, stream, store, tools
        case agentId = "agent_id"
        case model
        case handoffExecution = "handoff_execution"
    }
}

// Inputs can be string, message, or array
enum ConversationInputs: Codable {
    case text(String)
    case message(ConversationEntry)
    case messages([ConversationEntry])
}

struct ConversationEntry: Codable {
    let role: String
    let content: String
    let object: String = "entry"
    let type: String = "message.input"
}
```

### cURL - Start with Agent
```bash
curl https://api.mistral.ai/v1/conversations \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "ag_xxx",
    "inputs": "Generate an image of a sunset",
    "stream": false
  }'
```

### cURL - Start with Model (no agent)
```bash
curl https://api.mistral.ai/v1/conversations \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-medium-latest",
    "inputs": [
      {"role": "user", "content": "Hello!", "object": "entry", "type": "message.input"}
    ],
    "tools": [{"type": "web_search"}],
    "stream": false
  }'
```

### Response Schema
```swift
struct MistralConversationResponse: Codable {
    let conversationId: String
    let outputs: [ConversationOutput]
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case outputs
    }
}

struct ConversationOutput: Codable {
    let type: String
    var content: String?
    var toolName: String?
    var toolCallId: String?
    var name: String?
    var arguments: String?
    var result: AnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case type, content, name, arguments, result
        case toolName = "tool_name"
        case toolCallId = "tool_call_id"
    }
}
```

### Response Example
```json
{
  "conversation_id": "conv_0684fe18cbc57ba6800065acdd2b6c85",
  "outputs": [
    {
      "type": "message.output",
      "content": "Albert Einstein was a German-born theoretical physicist..."
    }
  ]
}
```

### Continue Conversation
```
POST /v1/conversations/{conversation_id}
```

```bash
curl https://api.mistral.ai/v1/conversations/conv_xxx \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": "Tell me more about his work",
    "stream": false
  }'
```

### Function Result (for function calling)
```bash
curl https://api.mistral.ai/v1/conversations/conv_xxx \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": [
      {
        "tool_call_id": "call_abc123",
        "result": "{\"temperature\": \"22°C\"}",
        "object": "entry",
        "type": "function.result"
      }
    ],
    "stream": false,
    "handoff_execution": "server"
  }'
```

### Streaming Events
When `stream: true`, SSE events with these types:
- `conversation.response.started` - Response beginning
- `message.output.delta` - Content chunks
- `tool.execution.started` - Tool starting
- `tool.execution.done` - Tool finished
- `function.call.delta` - Function call chunks
- `agent.handoff.started` - Handoff beginning
- `agent.handoff.done` - Handoff complete
- `conversation.response.done` - Response finished
- `conversation.response.error` - Error occurred

---

## 12. IMAGE GENERATION (via Agents)

Image generation uses Agents API with `image_generation` tool. Images stored as files.

### Create Image Agent
```bash
curl https://api.mistral.ai/v1/agents \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-medium-2505",
    "name": "Image Generator",
    "tools": [{"type": "image_generation"}]
  }'
```

### Generate Image
```bash
curl https://api.mistral.ai/v1/conversations \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "ag_xxx",
    "inputs": "Generate an image of a futuristic city at sunset",
    "stream": false
  }'
```

### Download Generated Image
```
GET /v1/files/{file_id}/content
```

```bash
curl https://api.mistral.ai/v1/files/file_abc123/content \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -o generated_image.png
```

---

## 13. FILES API

### Upload File
```bash
curl https://api.mistral.ai/v1/files \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -F 'purpose="audio"' \
  -F 'file=@"audio.mp3"'
```

### Get Signed URL
```bash
curl "https://api.mistral.ai/v1/files/file_xxx/url?expiry=24" \
  -H "Authorization: Bearer $MISTRAL_API_KEY"
```

### Purpose Values
- `batch` - Batch processing
- `audio` - Audio files
- `ocr` - Documents for OCR

---

## 14. MODELS LIST

```bash
curl https://api.mistral.ai/v1/models \
  -H "Authorization: Bearer $MISTRAL_API_KEY"
```

---

## 15. COMPLETE MODEL REFERENCE (November 2025)

### Premier Tier
| Alias | Resolved | Capabilities |
|-------|----------|--------------|
| `mistral-large-latest` | mistral-large-2411 | Chat, tools |
| `mistral-medium-latest` | mistral-medium-2508 | Chat, vision, tools |
| `pixtral-large-latest` | pixtral-large-2411 | Vision (124B) |
| `magistral-medium-latest` | magistral-medium-2509 | Reasoning, vision |
| `magistral-small-latest` | magistral-small-2509 | Reasoning, vision |
| `codestral-latest` | codestral-2508 | Code, FIM |
| `voxtral-small-latest` | voxtral-small-2507 | Audio (24B) |
| `voxtral-mini-latest` | voxtral-mini-2507 | Audio, transcription (3B) |
| `mistral-ocr-latest` | mistral-ocr-2505 | OCR |
| `devstral-small-latest` | devstral-small-2507 | Agentic coding |

### Free/Research
| Alias | Resolved | Capabilities |
|-------|----------|--------------|
| `mistral-small-latest` | mistral-small-2506 | Chat, vision, tools |
| `open-mistral-nemo` | open-mistral-nemo-2407 | Chat (12B, Apache 2.0) |
| `pixtral-12b-latest` | pixtral-12b-2409 | Vision (Apache 2.0) |

### Embeddings
| Model | Dimensions |
|-------|------------|
| `mistral-embed` | 1024 |
| `codestral-embed` | up to 3072 |

---

## 16. QUICK REFERENCE TABLE

| Capability | Endpoint | Models |
|------------|----------|--------|
| Chat | POST /v1/chat/completions | mistral-small, mistral-medium |
| Vision | POST /v1/chat/completions | pixtral-*, mistral-small |
| Audio | POST /v1/chat/completions | voxtral-* |
| Transcription | POST /v1/audio/transcriptions | voxtral-mini |
| Reasoning | POST /v1/chat/completions + promptMode=reasoning | magistral-* |
| Code FIM | POST /v1/fim/completions | codestral |
| Embeddings | POST /v1/embeddings | mistral-embed, codestral-embed |
| OCR | POST /v1/ocr | mistral-ocr |
| Agents | POST /v1/agents | any chat model |
| Conversations | POST /v1/conversations | agent or model |
| Image Gen | Agents + image_generation tool | via agents |

---

## 17. ERROR HANDLING

```swift
struct MistralAPIError: Codable {
    let message: String
    let type: String?
    let code: String?
}
```

HTTP codes:
- 400 - Bad request
- 401 - Unauthorized
- 422 - Validation error ("Extra inputs not permitted")
- 429 - Rate limited
- 500 - Server error

---

*Document verified November 2025 from official Mistral AI documentation*

