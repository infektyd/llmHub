// openrouter_TODO — Remaining integration items (Nov 2025)
//
// This checklist tracks what’s left to do after adding `OpenRouterClient.swift` and the spec in `openrouter_integration.md`. Generated without network access; items marked VERIFY should be checked against current docs before implementation.
//
// What’s already done
// - Spec document: `openrouter_integration.md` (roles, content parts, requests/responses, streaming, embeddings, discovery, key info)
// - Client skeleton: `OpenRouterClient.swift`
//   - Config + headers (Authorization, Content-Type; optional HTTP-Referer/X-Title)
//   - Shared models: `ORRole`, `ORContentPart`, `ORMessage`
//   - Chat: `chat(request:completion:)` (non-streaming)
//   - Streaming: `chatStream(...)` placeholder using dataTask fallback (bytes(for:) recommended)
//   - Embeddings: `embeddings(request:completion:)`
//   - Models: `listModels(completion:)`
//   - Key info: `getKeyInfo(completion:)`
//   - Responses API: placeholder `responses(...)`
//   - Helpers: `AnyEncodable`, `AnyCodable`, `firstImageDataURLs()`
//
// Remaining (spec deltas and polish)
// 1) Streaming (SSE)
// - VERIFY: Streaming chunk schema. Implement true SSE parsing with `URLSession.bytes(for:)` and iterate `bytes.lines`.
// - Add `Accept: text/event-stream` header (already supported via `accept:` param) and parse `data: [DONE]` termination.
// - Surface incremental deltas as `ORChatResponse.Choice.AssistantMessage` or a delta type.
//
// 2) Error handling & retries
// - VERIFY: Error body schema from OpenRouter; decode and surface message/code.
// - Add rate-limit handling (429) with `Retry-After` parsing and exponential backoff + jitter.
// - Surface non-2xx status codes with useful context.
//
// 3) Usage details
// - VERIFY: `completion_tokens_details` fields (e.g., `reasoning_tokens`) and extend `UsageDetails` accordingly.
// - Provide a convenience to extract total tokens and reasoning tokens (if present).
//
// 4) Reasoning options
// - VERIFY: Allowed values for `reasoning.effort` and precedence vs `max_tokens`.
// - Add helpers to enable reasoning and include reasoning text in outputs.
//
// 5) Image generation options
// - VERIFY: Model-specific parameters (aspect ratio, seed, etc.) and how to pass them through.
// - Add a convenience `generateImage(model:prompt:options:)` that wraps chat with `modalities: ["text","image"]` and extracts `images`.
//
// 6) Multimodal inputs
// - Add convenience helpers for: image URL, base64 file (PDF), input audio, video URL.
// - Validate data URI formats and size constraints (client-side guards).
//
// 7) Responses API (optional)
// - VERIFY: `/responses` schema and streaming format.
// - Implement typed request/response and a streaming variant if adopted.
//
// 8) Discovery & parameters
// - VERIFY: `/parameters/:author/:slug` schema. Add helper to fetch and expose supported parameters for selected model.
//
// 9) Metrics & logging
// - Emit latency metrics and optional debug logging (sans secrets) for all endpoints.
//
// 10) Concurrency & configuration
// - Consider making the client an `actor` or document thread-safety.
// - Allow injecting custom encoders/decoders and session configuration.
//
// Integration with llmHub
// - Add an `OpenRouterProvider` implementation that delegates to `OpenRouterClient` for non-streaming and streaming.
// - Map deltas to `ProviderEvent.token` and final message/usage to `ProviderEvent.completion`/`ProviderEvent.usage`.
// - Respect `ProvidersConfig.OpenRouter` (baseURL/models/pricing) and secure key from `KeychainStore`.
//
// Testing checklist (to automate)
// - Non-streaming chat: plain text Q&A
// - Streaming chat: incremental tokens and final completion
// - Vision input: URL and base64 image
// - Files/PDF: attach base64 PDF and get summarized output
// - Audio input: base64 mp3/wav
// - Video URL: simple summarization
// - Image generation: extract `images` data URLs from response
// - Embeddings: vector length matches expectations
// - Discovery: list models returns non-empty set
// - Key: key info returns label/credits
// - Errors: bad key, rate-limited, invalid model → meaningful surfaced errors
//
// Open questions / decisions
// - Do we adopt `/responses` now or later?
// - Which models and transforms do we enable by default in the app UI?
//
