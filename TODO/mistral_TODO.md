// mistral_TODO — Remaining integration items (Nov 2025)

This checklist tracks what’s left to do after adding/using `MistralProvider` and `Mistral_Integration.md`. We already support streaming chat; below are deltas and production tasks.

## What’s already done
- Provider: `MistralProvider` with `/v1/chat/completions`
- Streaming: SSE parser with token accumulation and usage on final chunk
- Vision mapping: content parts scaffolding (`text`, `image_url`, `input_audio`)
- Request/response models adapted from integration docs

## Remaining (spec deltas and polish)
1) Tool use & function calling
- Wire tool schemas (function definitions) and parse tool calls from responses
- Provide helper to send tool results back to the model

2) Reasoning mode
- Add `prompt_mode = "reasoning"` convenience for Magistral models; expose `reasoningChat(...)`

3) Audio features
- Add `/v1/audio/transcriptions` multipart helper (STT)
- Add Voxtral audio chat convenience (multimodal `input_audio` + text)

4) FIM (code completion)
- Implement `/v1/fim/completions` with streaming option
- Provide helpers for IDE scenarios (prompt/suffix)

5) Embeddings
- Implement `/v1/embeddings` helper + dimension/type options (codestral-embed)
- Add batch chunking for big inputs

6) OCR
- Implement `/v1/ocr` helper with URL/base64/file-id inputs; expose page markdown and images

7) Agents & Conversations (beta)
- Add create agent, start conversation, handle tool execution events
- Provide file download helper for generated images

8) Error handling & retry/backoff
- Map 422 validation errors cleanly ("Extra inputs not permitted")
- Add backoff with jitter for 429/5xx

9) Streaming improvements
- Ensure `Accept: text/event-stream` header present
- Surface streamed tool calls (function name/arguments)
- Provide `onFinish`/`onUsage` callbacks

10) Metrics & logging
- Emit metrics for latency and tokens across endpoints
- Add debug logging toggle

11) Documentation & samples
- Doc comments + README snippets for each capability (chat, vision, audio, FIM, OCR, embeddings)

## Integration with existing llmHub providers
- `MistralProvider` is already wired; extend to tool use and additional endpoints as needed
- Ensure consistent `ProviderEvent` emissions across providers

## Testing checklist (to automate)
- Chat: basic Q&A and streaming
- Vision: URL + base64 image inputs
- Audio: STT; audio chat
- FIM: prompt/suffix flow returns code completion
- Embeddings: dimension handling and vector length validation
- OCR: extract markdown and images from sample PDF
- Agents: start conversation, receive outputs, download generated file
- Errors: 401/422/429 handling

## Open questions / decisions
- Which models should be exposed by default in UI?
- Do we want to ship FIM and OCR in v1 or later?

