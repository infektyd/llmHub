//
//  openai_integration.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/29/25.
//
Here’s something you can literally copy-paste to the agent as the “spec” for integration.

⸻

✅ OpenAI Swift Integration Spec (2025-11)

Goal

Implement a single Swift API layer (OpenAIClient.swift) that exposes the major OpenAI capabilities:
    •    General text / chat / tools (GPT-5.1, GPT-4.1, GPT-4.1-mini, GPT-4o, etc.)  ￼
    •    Reasoning models (o3-mini / o-series)  ￼
    •    Vision (image input to models like GPT-4.1 / GPT-4o)  ￼
    •    Image generation & editing (GPT Image / DALL·E)  ￼
    •    Audio: speech-to-text, text-to-speech, translations  ￼
    •    Video generation (Sora 2 Pro / videos API)  ￼
    •    Optional: embeddings, files, web search / tools, realtime voice API  ￼

The implementation should be one reusable client plus a small set of type-safe request/response structs.

⸻

1. Project Setup
    1.    Platform & Language
    •    Swift 5.9+ with async/await.
    •    iOS 16+ / macOS 13+ target (or higher).
    2.    Secrets
    •    API key is never hard-coded.
    •    Read from a secure store (e.g. Keychain, encrypted config, or injected from backend).
    •    Client receives something like openAIKey: String in its initializer.
    3.    Base API configuration

struct OpenAIConfig {
    let apiKey: String
    let organizationID: String?     // optional, if used
    let baseURL: URL                // typically https://api.openai.com/v1/

    init(
        apiKey: String,
        organizationID: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1/")!
    ) {
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.baseURL = baseURL
    }
}



⸻

2. Core Client File: OpenAIClient.swift

Create one file that contains:

2.1 Public Models Enum
Expose the key model names as constants (string backed):

enum OpenAIModel: String {
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

Model strings should match the current names in the OpenAI models page at implementation time.  ￼

2.2 Generic HTTP Layer
Implement a single, reusable HTTP sender that:
    •    Uses URLSession
    •    Encodes any Encodable request body
    •    Decodes into any Decodable response type
    •    Adds auth & content headers
    •    Optionally supports streaming via URLSession.bytes(for:) or Server-Sent Events where needed  ￼

Example shape:

final class OpenAIClient {
    private let config: OpenAIConfig
    private let urlSession: URLSession

    init(config: OpenAIConfig, urlSession: URLSession = .shared) {
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

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

Define a simple error type:

enum OpenAIError: Error {
    case httpError(Int, data: Data?)
    case decodingError(Error)
    case unknown(Error)
}


⸻

3. High-Level Capabilities (Methods to Implement)

Each capability below should be implemented as a public async method on OpenAIClient. The exact request/response structs should follow the official OpenAI API reference for each endpoint.  ￼

3.1 Text / Chat / Tools (main workhorse)
Use either:
    •    Responses API (POST /responses) – recommended for new work, supports tools, web search, images/audio outputs, etc.  ￼
    •    Or Chat Completions (POST /chat/completions) if you prefer the older primitive.

Design a type for messages:

struct ChatMessage: Encodable {
    enum Role: String, Encodable {
        case system, user, assistant, tool
    }

    let role: Role
    let content: String            // for basic text use-cases
}

Public method signature:

extension OpenAIClient {
    struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        // Optional: temperature, max_tokens, tools, tool_choice, response_format, etc.
    }

    struct ChatResponse: Decodable {
        // Mirror the shape from /chat/completions or /responses (choices, message, usage, etc.)
    }

    func chat(
        model: OpenAIModel = .gpt5_1,
        messages: [ChatMessage]
    ) async throws -> ChatResponse {
        let requestBody = ChatRequest(model: model.rawValue, messages: messages)
        return try await send(path: "chat/completions", body: requestBody)
        // Or "responses" if using the Responses API.
    }
}

Tools & web search:
Extend ChatRequest with a tools array (function schemas, web search tool) and an optional tool_choice property following the tools documentation.  ￼

3.2 Reasoning (“thinking models” like o3-mini)
These are used like chat models but may require extra parameters (e.g., reasoning effort).  ￼
    •    Expose a convenience method that just delegates to chat but forces a reasoning model:

extension OpenAIClient {
    func reason(
        model: OpenAIModel = .o3_mini,
        messages: [ChatMessage]
    ) async throws -> ChatResponse {
        // Optionally include reasoning-related params in the body
        let request = ChatRequest(model: model.rawValue, messages: messages)
        return try await send(path: "chat/completions", body: request)
    }
}

3.3 Vision (image input)
Models like GPT-4.1 / GPT-4o accept images as part of the input.  ￼

Create an additional content type:

enum ChatContent: Encodable {
    case text(String)
    case imageURL(URL)       // remote image
    case imageBase64(String) // inline base64

    // Encode according to the vision/Responses spec.
}

struct VisionMessage: Encodable {
    let role: ChatMessage.Role
    let content: [ChatContent]
}

Add a method:

extension OpenAIClient {
    struct VisionRequest: Encodable {
        let model: String
        let messages: [VisionMessage]
    }

    func analyzeImage(
        model: OpenAIModel = .gpt4_1,
        messages: [VisionMessage]
    ) async throws -> ChatResponse {
        let body = VisionRequest(model: model.rawValue, messages: messages)
        return try await send(path: "chat/completions", body: body)
        // Or "responses" with multimodal input as per docs.
    }
}

3.4 Image Generation & Editing
Use the image generation API (POST /images) or the image tool via Responses.  ￼

Basic shape:

extension OpenAIClient {
    struct ImageGenerationRequest: Encodable {
        let model: String      // e.g. OpenAIModel.gpt_image.rawValue
        let prompt: String
        let n: Int?
        let size: String?      // e.g. "1024x1024"
    }

    struct ImageGenerationResponse: Decodable {
        struct DataItem: Decodable {
            let url: String?       // or base64 JSON field, depending on API choice
            let b64_json: String?
        }
        let data: [DataItem]
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

Similar pattern for image edits and variations using the corresponding images endpoints.

3.5 Audio: Speech-to-Text (STT) & Text-to-Speech (TTS)
Use /audio/transcriptions, /audio/translations, and /audio/speech.  ￼
    1.    Transcription (file → text)
Method should accept an URL to a local audio file, build a multipart request, and decode the transcription JSON.
Public signature:

func transcribeAudio(
    fileURL: URL,
    model: OpenAIModel = .whisper,
    language: String? = nil
) async throws -> String

    •    Implement using multipart/form-data as per audio API reference.
    •    Decode the text field from the response.

    2.    Text-to-Speech (text → audio)

func synthesizeSpeech(
    text: String,
    model: String,    // TTS model name from audio docs
    voice: String,    // voice identifier
    format: String    // e.g. "mp3", "aac", etc.
) async throws -> Data

    •    Returns raw audio Data for playback with AVAudioPlayer or similar.

3.6 Video Generation
Use the video generation endpoint (POST /videos) with Sora 2 Pro or other video models.  ￼

Public method:

extension OpenAIClient {
    struct VideoGenerationRequest: Encodable {
        let model: String     // e.g. OpenAIModel.sora2_pro.rawValue
        let prompt: String
        // Optional: duration, resolution, seed, reference image, reference video
    }

    // Depending on API, response may include URLs or file IDs.
    struct VideoGenerationResponse: Decodable {
        // Mirror the videos API response: id, status, output URL / file, etc.
    }

    func generateVideo(
        model: OpenAIModel = .sora2_pro,
        prompt: String
    ) async throws -> VideoGenerationResponse {
        let body = VideoGenerationRequest(model: model.rawValue, prompt: prompt)
        return try await send(path: "videos", body: body)
    }
}

If the API returns a file ID instead of a direct URL, expose another helper:

func downloadFile(fileID: String) async throws -> Data

using the /files/{file_id}/content endpoint.  ￼

3.7 Embeddings (optional but recommended)
Expose a simple embeddings wrapper:

extension OpenAIClient {
    struct EmbeddingsRequest: Encodable {
        let model: String
        let input: [String]
    }

    struct EmbeddingsResponse: Decodable {
        struct Embedding: Decodable {
            let embedding: [Double]
        }
        let data: [Embedding]
    }

    func createEmbeddings(
        model: OpenAIModel = .textEmbedding,
        input: [String]
    ) async throws -> EmbeddingsResponse {
        let body = EmbeddingsRequest(model: model.rawValue, input: input)
        return try await send(path: "embeddings", body: body)
    }
}


⸻

4. Realtime Voice / Multimodal (Optional Separate Layer)

For true realtime, low-latency, bi-directional voice+text, use the Realtime API over WebRTC or websockets rather than the regular REST client.  ￼
    •    Implement this as another file (e.g. OpenAIRealtimeClient.swift), not part of OpenAIClient.swift.
    •    Use an existing Swift WebRTC/websocket lib or a dedicated Swift Realtime SDK if you choose.
    •    Responsibilities:
    •    Open/close a realtime session.
    •    Stream microphone audio → model.
    •    Play back model audio.
    •    Optionally send/receive text & tool calls.

The REST client you’re defining here does not need to handle realtime streaming; just keep the design compatible (e.g. similar model enums and error handling).

⸻

5. Error Handling & Observability

Implement:
    •    Uniform error type (OpenAIError) that wraps:
    •    HTTP status
    •    Parsed error JSON from OpenAI (message, type, code) if available.  ￼
    •    Rate-limit handling:
    •    If status 429 or a rate-limit error code is returned, surface it distinctly so the app can retry/backoff.
    •    Metrics hooks:
    •    Optional closure or delegate to receive:
    •    model name
    •    token usage (if returned in usage)
    •    latency

⸻

6. Streaming Support (Text / Chat)

For streaming responses:
    •    Use the documented streaming options on either:
    •    Chat Completions streaming, or
    •    Responses streaming API.  ￼
    •    Implement an additional method:

func chatStream(
    model: OpenAIModel,
    messages: [ChatMessage],
    onDelta: @escaping (String) -> Void
) async throws

which:
    •    Sends the same body as chat, with stream: true.
    •    Parses incoming chunks and calls onDelta with incremental text.

⸻

7. Minimal Testing Checklist

Before shipping, verify all of this actually works:
    1.    General text: simple Q&A call using GPT-5.1 and GPT-4.1-mini.
    2.    Reasoning: o3-mini call that solves multi-step reasoning (e.g. math or planning).
    3.    Vision: send a prompt + image (URL or base64) and confirm it describes or reasons about the image.
    4.    Images: generate & display at least one image in the app.
    5.    Audio:
    •    Transcribe a short microphone recording with Whisper.
    •    Synthesize and play back speech from a short text.
    6.    Video: generate a short clip and download or preview it.
    7.    Embeddings: call embeddings and verify the returned vector length is as documented.
    8.    Errors: deliberately trigger:
    •    bad API key,
    •    bad model name,
    •    too-large prompt
and confirm the error handling code surfaces meaningful information.

⸻

8. Optional: Libraries Instead of Raw HTTP

If you prefer not to maintain all request/response types by hand, you can optionally:
    •    Use a dedicated Swift Responses API SDK (e.g. a typed client for /responses)  ￼
    •    Or a more general OpenAI Swift package that wraps all current endpoints (chat, images, audio, files, etc.)  ￼

If you do this, the overall structure above still applies; OpenAIClient just becomes a thin wrapper around the chosen SDK so the rest of the app only depends on our API surface, not on the third-party package directly.

⸻

That’s the full spec.
If you want, I can next turn this into a concrete OpenAIClient.swift implementation skeleton (full code) that matches this structure.
