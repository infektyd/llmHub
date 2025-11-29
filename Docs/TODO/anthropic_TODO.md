// anthropic_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding/using `AnthropicProvider` and the Claude integration docs. We already have streaming messages wired; below are deltas, polish, and production tasks.

// ## What’s already done
// - Provider: `AnthropicProvider` with `messages` endpoint
// - Headers: `x-api-key`, `anthropic-version`, `Content-Type`
// - Streaming: SSE parsing (`message_start`/`content_block_delta`/`message_delta`/`message_stop`) with token accumulation
// - Usage: parse from `message_delta` and surface as `ProviderEvent.usage`
// - Basic request mapping: maps our `ChatMessage` to Anthropic message blocks (text-only)
// - Beta features & headers (files, thinking, structured-outputs, effort) enabled
// - Tool use: Structs defined, `tool_use` events surfaced in stream
// - Vision & PDFs: `analyzeImage` and `analyzePDF` convenience methods implemented
// - Files API: `uploadFile` implemented
// - Extended thinking: Structs defined
// - Error handling: `Retry-After` parsed to `LLMProviderError.rateLimited`

// ## Remaining (spec deltas and polish)

// 1) Extended thinking logic
// - Wire up `thinking` config from UI/Config to request

// 2) Tool use Integration
// - Update `ChatMessage` or `buildRequest` to allow passing tools dynamically from the app layer

// 3) Structured outputs
// - Add helpers for JSON-object/schema outputs and typed decoding of structured results

// 4) Metrics & logging
// - Add debug logging toggle for summarized requests/responses (sans secrets)

// 5) Testing
// - Verify vision/tools/files flows with real credentials


// 10) Documentation & samples
// - Add doc comments and README snippets for images/PDF/tools/extended thinking

// ## Integration with existing llmHub providers
// - `AnthropicProvider` is already wired; expand mapping to include vision/doc blocks and tool use
// - Ensure `ChatService` forwards streaming tokens and usage consistently with other providers
// - Consider a thin wrapper around a `ClaudeAPIService` if you prefer the richer typed interface

// ## Testing checklist (to automate)
// - Text: simple Q&A with Sonnet/Haiku
// - Vision: analyze image (URL and base64)
// - PDF: summarize a short PDF via document block
// - Tools: return a `tool_use`, send `tool_result`, verify final message
// - Extended thinking: verify longer reasoning and token budget handling
// - Files: upload → use `file_id` in message → succeed
// - Streaming: tokens arrive incrementally; final usage parsed
// - Errors: bad key, rate limit, invalid inputs → meaningful surfaced errors

// ## Open questions / decisions
// - Which beta features should be enabled by default?
// - Do we want to keep a separate `ClaudeAPIService` for richer APIs, or keep everything in `AnthropicProvider`?
