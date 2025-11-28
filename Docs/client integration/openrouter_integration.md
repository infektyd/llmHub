//
//  openrouter_integration.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//
Here’s something you can hand directly to the engineer as the “OpenRouter integration spec” for a Swift app.

⸻

0. Goal

Implement a single Swift client around OpenRouter that can:
    •    Call any chat model (text-only, reasoning, “flash”/cheap models, etc.).
    •    Handle multimodal input: images, PDFs/files, audio, video.
    •    Do image generation via models with image output.
    •    Use reasoning / thinking tokens.
    •    Use streaming (SSE).
    •    Call embeddings.
    •    Discover models & parameters and inspect usage/credits.

Everything below is based on OpenRouter’s current docs as of Nov 2025.  ￼

⸻

1. Core HTTP Setup

Base URL & Auth
    •    Base URL: https://openrouter.ai/api/v1  ￼
    •    Auth header:
    •    Authorization: Bearer <OPENROUTER_API_KEY>
    •    Recommended attribution headers (optional but good to add):  ￼
    •    HTTP-Referer: <YOUR_SITE_URL>
    •    X-Title: <YOUR_APP_NAME>
    •    Content-Type for JSON: application/json.

Swift config struct (suggested)

struct OpenRouterConfig {
    let apiKey: String
    let baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!
    let appURL: String?      // for HTTP-Referer
    let appName: String?     // for X-Title
}

Base client

final class OpenRouterClient {
    private let config: OpenRouterConfig
    private let urlSession: URLSession

    init(config: OpenRouterConfig, session: URLSession = .shared) {
        self.config = config
        self.urlSession = session
    }

    private func makeRequest(
        path: String,
        method: String = "POST",
        body: Encodable? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let appURL = config.appURL {
            request.setValue(appURL, forHTTPHeaderField: "HTTP-Referer")
        }
        if let appName = config.appName {
            request.setValue(appName, forHTTPHeaderField: "X-Title")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        return request
    }
}

(You can implement AnyEncodable as a simple type-erased wrapper.)

⸻

2. Shared Data Models (Chat & Multimodal)

2.1 Roles

enum ORRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

2.2 Content parts (text, image, audio, video, file)

All content is an array of typed parts. OpenRouter uses OpenAI-style multimodal content with extra types:  ￼

enum ORContentPart: Codable {
    case text(String)
    case imageURL(url: String, detail: String?)
    case inputAudio(dataBase64: String, format: String) // e.g. "mp3" or "wav"
    case videoURL(url: String)
    case file(dataBase64: String, mimeType: String)     // PDFs/other files

    private enum CodingKeys: String, CodingKey {
        case type, text, image_url, input_audio, video_url, file, url, detail, data, format, mime_type
    }

    private enum PartType: String, Codable {
        case text
        case image_url
        case input_audio
        case video_url
        case file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PartType.self, forKey: .type)

        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)

        case .image_url:
            let imageContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .image_url)
            let url = try imageContainer.decode(String.self, forKey: .url)
            let detail = try imageContainer.decodeIfPresent(String.self, forKey: .detail)
            self = .imageURL(url: url, detail: detail)

        case .input_audio:
            let audioContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .input_audio)
            let data = try audioContainer.decode(String.self, forKey: .data)
            let format = try audioContainer.decode(String.self, forKey: .format)
            self = .inputAudio(dataBase64: data, format: format)

        case .video_url:
            let videoContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .video_url)
            let url = try videoContainer.decode(String.self, forKey: .url)
            self = .videoURL(url: url)

        case .file:
            let fileContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .file)
            let data = try fileContainer.decode(String.self, forKey: .data)
            let mime = try fileContainer.decode(String.self, forKey: .mime_type)
            self = .file(dataBase64: data, mimeType: mime)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode(PartType.text, forKey: .type)
            try container.encode(text, forKey: .text)

        case .imageURL(let url, let detail):
            try container.encode(PartType.image_url, forKey: .type)
            var img = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .image_url)
            try img.encode(url, forKey: .url)
            if let detail = detail {
                try img.encode(detail, forKey: .detail)
            }

        case .inputAudio(let data, let format):
            try container.encode(PartType.input_audio, forKey: .type)
            var audio = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .input_audio)
            try audio.encode(data, forKey: .data)
            try audio.encode(format, forKey: .format)

        case .videoURL(let url):
            try container.encode(PartType.video_url, forKey: .type)
            var video = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .video_url)
            try video.encode(url, forKey: .url)

        case .file(let data, let mime):
            try container.encode(PartType.file, forKey: .type)
            var file = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .file)
            try file.encode(data, forKey: .data)
            try file.encode(mime, forKey: .mime_type)
        }
    }
}

2.3 Messages

struct ORMessage: Codable {
    let role: ORRole
    let content: [ORContentPart]  // for plain text, use [.text("...")]

    // Optional: tool-related fields, etc., can be added later as needed.
}


⸻

3. Chat / Completions (Text + Multimodal + Reasoning)

Endpoint:
POST /chat/completions  ￼

3.1 Request model

Make a general-purpose request struct that covers:
    •    Model name ("provider/model"), e.g. "openai/gpt-5", "google/gemini-2.5-flash", "google/gemini-2.5-flash-image-preview", "openai/o3-mini" etc.  ￼
    •    messages (incl. multimodal).
    •    Standard sampling params.
    •    OpenRouter-only params.
    •    Reasoning options.
    •    Streaming flag.
    •    Image generation modalities.

struct ORChatRequest: Codable {
    // Core
    let model: String
    let messages: [ORMessage]

    // Optional: "modalities" is used for image generation (e.g. ["text", "image"])
    let modalities: [String]?

    // Sampling
    let temperature: Double?
    let top_p: Double?
    let max_tokens: Int?
    let stop: [String]?

    // Streaming
    let stream: Bool?

    // Reasoning / thinking tokens
    struct Reasoning: Codable {
        // OpenRouter normalizes this; only one of these should be set.  [oai_citation:6‡GitHub](https://github.com/simonw/llm-openrouter/issues/45?utm_source=chatgpt.com)
        let effort: String?       // "low" | "medium" | "high" (OpenAI-style)
        let max_tokens: Int?      // Anthropic-style cap
    }
    let reasoning: Reasoning?
    let include_reasoning: Bool? // if true, reasoning tokens are returned in `reasoning` field.  [oai_citation:7‡OpenRouter](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens?utm_source=chatgpt.com)

    // Usage accounting
    struct UsageConfig: Codable { let include: Bool }
    let usage: UsageConfig?

    // OpenRouter-only fields (prompt transforms, routing)  [oai_citation:8‡OpenRouter](https://openrouter.ai/docs/guides/features/message-transforms?utm_source=chatgpt.com)
    let transforms: [String]? // e.g. ["middle-out"] (default; [] disables)
    let models: [String]?     // list for model routing instead of single `model`
    let route: String?        // e.g. "fallback"
    let provider: [String: AnyCodable]? // provider routing object (order, allow_fallbacks, etc.)
    let user: String?         // stable end-user id
}

Minimal plain-text chat example

JSON that the Swift client should effectively send:

{
  "model": "openai/gpt-5-mini",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Explain quantum entanglement simply." }
      ]
    }
  ]
}

(Engineer: encode via ORMessage(role: .user, content: [.text("...")]) and ORChatRequest.)

3.2 Response model (non-streaming)

OpenRouter returns an OpenAI-like structure: id, choices, usage, etc.  ￼

struct ORChatResponse: Codable {
    struct Choice: Codable {
        struct AssistantMessage: Codable {
            let role: ORRole
            let content: [ORContentPart]?

            // For image generation responses:
            struct ImagePart: Codable {
                struct ImageURL: Codable { let url: String }
                let type: String           // "image_url"
                let image_url: ImageURL
            }
            let images: [ImagePart]?

            // Reasoning tokens (if enabled and supported)  [oai_citation:10‡OpenRouter](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens?utm_source=chatgpt.com)
            let reasoning: String?
        }

        let index: Int?
        let message: AssistantMessage
        let finish_reason: String?
    }

    struct UsageDetails: Codable {
        let prompt_tokens: Double?
        let completion_tokens: Double?
        // completion_tokens_details may include reasoning_tokens, audio_tokens, etc.  [oai_citation:11‡OpenRouter](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request?explorer=true&utm_source=chatgpt.com)
    }

    let id: String
    let object: String // "chat.completion"
    let created: Int?
    let model: String
    let choices: [Choice]
    let usage: UsageDetails?
}

3.3 Synchronous call wrapper

extension OpenRouterClient {
    func chat(
        request: ORChatRequest,
        completion: @escaping (Result<ORChatResponse, Error>) -> Void
    ) {
        do {
            var urlRequest = try makeRequest(path: "chat/completions", body: request)
            urlRequest.httpMethod = "POST"

            urlSession.dataTask(with: urlRequest) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(ORChatResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }
}


⸻

4. Streaming (Server-Sent Events)

OpenRouter uses SSE when stream: true. Each line starts with data: and contains JSON chunks; final line is data: [DONE].  ￼
    •    Endpoint is the same: POST /chat/completions.
    •    Request: identical to non-streaming but with stream: true.

Swift interface

extension OpenRouterClient {
    // Basic SSE streaming; you can refine as needed.
    func chatStream(
        request: ORChatRequest,
        onChunk: @escaping (Result<ORChatResponse.Choice.AssistantMessage, Error>) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        // Implement an SSE parser on top of URLSession.dataTask or a custom stream task.
        // 1. Set `stream: true` on the request
        // 2. Read the response as a text stream
        // 3. For each line starting with `data: `
        //    - If payload is "[DONE]" => call onComplete(.success(()))
        //    - Else JSON-decode into a chunk object and surface `delta.message` or `delta.images`
    }
}

Engineer can model the streaming chunks similar to OpenAI chat-completion chunks (object chat.completion.chunk containing choices[].delta).  ￼

⸻

5. Vision / Multimodal Input (Images, PDFs, Audio, Video)

Same /chat/completions endpoint, with multimodal content.  ￼

5.1 Image understanding
    •    Use models with image input modality (filter on models page: Input: Image).  ￼

Example JSON shape the client must produce:

{
  "model": "google/gemini-2.5-flash",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Describe this image in detail." },
        {
          "type": "image_url",
          "image_url": { "url": "https://example.com/cat.png", "detail": "high" }
        }
      ]
    }
  ]
}

In Swift, that’s ORMessage(role: .user, content: [.text(...), .imageURL(url: ..., detail: "high")]).

5.2 PDF / files
    •    Use content part type "file" with base64 data + MIME type (e.g. application/pdf).  ￼

JSON pattern:

{
  "type": "file",
  "file": {
    "data": "<base64-encoded-pdf>",
    "mime_type": "application/pdf"
  }
}

Swift: ORContentPart.file(dataBase64: ..., mimeType: "application/pdf").

5.3 Audio input
    •    Type: "input_audio" with { data: <base64>, format: "mp3" | "wav" }.  ￼

{
  "type": "input_audio",
  "input_audio": {
    "data": "<base64-audio>",
    "format": "mp3"
  }
}

Swift: ORContentPart.inputAudio(dataBase64: ..., format: "mp3").

5.4 Video input (video understanding, not generation)
    •    Type: "video_url" with { url: <http(s) or data URL> }.  ￼

Example:

{
  "model": "google/gemini-2.5-pro",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Summarize this video." },
        { "type": "video_url", "video_url": { "url": "https://example.com/video.mp4" } }
      ]
    }
  ]
}

As of Nov 2025, OpenRouter supports video input (understanding/summarization), but video generation is generally done via separate media APIs, not OpenRouter’s own output modalities, which are text, images and embeddings.  ￼

⸻

6. Image Generation

Image generation also uses /chat/completions, with modalities including "image".  ￼

6.1 Request
    •    Use a model whose output_modalities includes "image" (e.g. Gemini Flash Image-preview, Flux, etc.).  ￼

Example JSON the client should send:

{
  "model": "google/gemini-3-pro-image-preview",
  "modalities": ["text", "image"],
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Create a cinematic photo of a red sports car at night in the rain." }
      ]
    }
  ]
}

You can also pass additional image-generation config (aspect ratio, etc.) using model-specific parameters; OpenRouter forwards those to providers.  ￼

6.2 Response

The assistant message includes an images field with base64 data URLs (usually PNG).  ￼
    •    Top-level: choices[0].message.images[].
    •    Each item roughly:

{
  "type": "image_url",
  "image_url": { "url": "data:image/png;base64,..." }
}

Swift helper to extract images

extension ORChatResponse {
    func firstImageDataURLs() -> [String] {
        guard let images = choices.first?.message.images else { return [] }
        return images.map { $0.image_url.url }
    }
}


⸻

7. Reasoning / “Thinking” Models

OpenRouter exposes reasoning tokens for supported models (o-series, reasoning variants, “thinking” models, etc.).  ￼

7.1 Enabling reasoning

Use the reasoning object and include_reasoning: true:

{
  "model": "openai/o3-mini",
  "messages": [
    { "role": "user", "content": [ { "type": "text", "text": "Solve this step by step: ..." } ] }
  ],
  "reasoning": {
    "effort": "medium"   // or "low", "high"
  },
  "include_reasoning": true
}

or for Anthropic-style caps:

"reasoning": {
  "max_tokens": 2000
}

Only one of effort or max_tokens should be set.  ￼

7.2 Reading reasoning tokens
    •    Reasoning text (when returned) appears in choices[x].message.reasoning.  ￼
    •    Token counts are in usage.completion_tokens_details.reasoning_tokens and sometimes in Responses API usage.  ￼

⸻

8. Embeddings

Endpoint: POST /embeddings  ￼

8.1 Request

struct OREmbeddingsRequest: Codable {
    let model: String           // e.g. "openai/text-embedding-3-large" (via OpenRouter)
    let input: [String]         // or a single string
}

Example JSON:

{
  "model": "openai/text-embedding-3-large",
  "input": ["some text", "another text"]
}

8.2 Response

struct OREmbeddingsResponse: Codable {
    struct Embedding: Codable {
        let embedding: [Double]
        let index: Int
    }
    let data: [Embedding]
    let model: String
    let object: String  // "list"
}

8.3 Client method

extension OpenRouterClient {
    func embeddings(
        request: OREmbeddingsRequest,
        completion: @escaping (Result<OREmbeddingsResponse, Error>) -> Void
    ) {
        do {
            let urlRequest = try makeRequest(path: "embeddings", body: request)
            urlSession.dataTask(with: urlRequest) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else {
                    completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(OREmbeddingsResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }
}


⸻

9. Models & Parameters Discovery

9.1 List models

Endpoint: GET /models  ￼
    •    Returns an array of models with id, input_modalities, output_modalities, pricing, etc.

Swift-style:

struct ORModelInfo: Codable {
    let id: String
    let input_modalities: [String]?
    let output_modalities: [String]?
    // plus other fields if needed
}

extension OpenRouterClient {
    func listModels(completion: @escaping (Result<[ORModelInfo], Error>) -> Void) {
        do {
            let request = try makeRequest(path: "models", method: "GET", body: Optional<String>.none)
            urlSession.dataTask(with: request) { data, response, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data else {
                    completion(.failure(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                    return
                }
                do {
                    let models = try JSONDecoder().decode([ORModelInfo].self, from: data)
                    completion(.success(models))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }
}

Use this to find:
    •    Which models accept image / file / audio / video input.
    •    Which models produce image output (for generation).
    •    Cheap “flash” models vs heavy reasoning models (by pricing, context length, etc.).  ￼

9.2 Per-model parameter metadata (optional)

Endpoint: GET /parameters/:author/:slug (e.g. /parameters/openai/gpt-5) for detailed supported parameter metadata (sampling, reasoning, etc.).  ￼

⸻

10. Usage / Cost & Key Info

10.1 Get current key info

Endpoint: GET /key  ￼
    •    Returns label, credit limit, usage, rate-limits, expiry, etc.
    •    Implement as a simple GET with the standard auth header.

10.2 Per-generation stats

For any chat/response, you can query /generation?id=<GENERATION_ID> using the id returned by the API to get tokens & cost across all models, for both streaming and non-streaming.  ￼

⸻

11. Responses API (Optional but Recommended)

Besides /chat/completions, OpenRouter exposes a Responses API at:  ￼
    •    POST /responses
    •    More “unified” format (input array of typed items instead of messages).
    •    Supports reasoning options, structured outputs, and streaming events in a similar way to OpenAI Responses.

If you want maximum future compatibility, define a second client method:

struct ORResponsesRequest: Codable {
    let model: String
    let input: AnyCodable          // can be string or list of message-like objects
    let reasoning: ORChatRequest.Reasoning?
    let include_reasoning: Bool?
    // plus sampling, usage, etc.
}

struct ORResponsesResponse: Codable {
    // Map to OpenRouter’s /responses schema:
    // - output items (text, images)
    // - usage: prompt_tokens, completion_tokens, reasoning_tokens
}

extension OpenRouterClient {
    func responses(
        request: ORResponsesRequest,
        // streaming or non-streaming
    ) { /* similar to chat() or chatStream() */ }
}

This is optional; Chat Completions alone are enough for most apps.

⸻

12. OpenRouter-specific Features to Expose

At minimum, the Swift client should surface these as optional parameters:
    •    transforms: [String] for prompt transforms; "middle-out" is the default and can be disabled via [].  ￼
    •    models: [String] and route: "fallback" for model routing / fallbacks.  ￼
    •    provider object for provider routing (order, allow_fallbacks, data_collection, require_parameters).  ￼
    •    usage: { include: true } to get normalized usage info in responses.  ￼
    •    reasoning + include_reasoning for thinking models.  ￼

These can be bundled into a single Swift struct (e.g. ORChatOptions) and merged into ORChatRequest.

⸻

13. Minimal High-Level Swift API Surface

So the agent has something concrete to implement, here’s a suggested high-level API to expose to the rest of the app:

protocol LLMService {
    // 1) Generic chat (text or multimodal), sync-style callback
    func chat(
        model: String,
        messages: [ORMessage],
        options: ORChatOptions?,
        completion: @escaping (Result<ORChatResponse, Error>) -> Void
    )

    // 2) Streaming chat
    func chatStream(
        model: String,
        messages: [ORMessage],
        options: ORChatOptions?,
        onChunk: @escaping (ORChatResponse.Choice.AssistantMessage) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    )

    // 3) Image generation
    func generateImage(
        model: String,
        prompt: String,
        options: ORChatOptions?,
        completion: @escaping (Result<[String], Error>) -> Void // returns data URLs
    )

    // 4) Embeddings
    func embed(
        model: String,
        input: [String],
        completion: @escaping (Result<OREmbeddingsResponse, Error>) -> Void
    )

    // 5) Discovery
    func listModels(
        completion: @escaping (Result<[ORModelInfo], Error>) -> Void
    )

    // 6) Usage / key info
    func getKeyInfo(
        completion: @escaping (Result<ORKeyInfo, Error>) -> Void
    )
}

Where ORChatOptions wraps temperature/top_p/max_tokens/stream/usage/reasoning/transforms/provider/etc., and ORKeyInfo mirrors /key response fields.  ￼

⸻

If you hand this whole spec to the integrating engineer, they should be able to implement a single OpenRouterClient.swift that:
    •    works with any OpenRouter model (OpenAI, Anthropic, Gemini Flash/Pro, free/open models, etc.),
    •    covers vision, audio, PDFs, video input,
    •    supports image generation,
    •    and exposes reasoning / “thinking”, flash/cheap models, embeddings, and usage/monitoring without needing to consult the external docs.
