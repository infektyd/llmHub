// xai_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding `XAIProvider` (Grok) and any Grok integration docs. We have non‑streaming chat in place; below are deltas to reach parity with others.

// What’s already done
// - Provider: `XAIProvider` using OpenAI‑compatible `/chat/completions`
// - Basic one‑shot flow that yields a completion and usage
// - Endpoint/headers aligned with `https://api.x.ai/v1`

// Remaining (spec deltas and polish)
// 1) Streaming
// - Add SSE streaming for chat; ensure `Accept: text/event-stream` header and parse `data:` lines
// - Yield `ProviderEvent.token` and final `ProviderEvent.usage`

// 2) Vision & images
// - If Grok supports image input via chat, add content parts mapping (text + image_url/data URI)
// - Add images generation endpoint if available; otherwise document limitations

// 3) Tool use
// - Add function/tool schema to requests and parse `tool_calls` from responses
// - Provide helper to send tool results back

// 4) Error handling & retry/backoff
// - Map rate limits and 5xx with exponential backoff + jitter
// - Surface server error bodies for debugging

// 5) Metrics & logging
// - Emit latency/usage metrics
// - Add debug logging toggle

// 6) Configuration
// - Allow base URL override via `ProvidersConfig.XAI`
// - Ensure key is pulled securely from `KeychainStore`

// Integration with existing llmHub providers
// - Extend `XAIProvider` to support streaming and tool use similar to OpenAI/Mistral
// - Keep message/usage mapping consistent across providers

// Testing checklist (to automate)
// - Chat: non‑streaming and streaming
// - Vision: URL/base64 image input (if supported)
// - Tools: function call → tool result roundtrip
// - Errors: bad key, invalid model, rate limit

// Open questions / decisions
// - Which Grok models should be exposed in UI?
// - Do we need image generation for initial release, or is chat/vision enough?
