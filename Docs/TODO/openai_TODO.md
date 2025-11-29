# openai_TODO — Remaining integration items (Nov 2025)

This checklist tracks what’s left to do after implementing `OpenAIManager.swift` and `OpenAIProvider`.

## What’s already done
- Manager: `OpenAIManager` handling Chat (Completions), Streaming, Vision, Audio (TTS/STT), Images, Embeddings.
- Provider: `OpenAIProvider` fully delegates to `OpenAIManager`.
- Streaming: Implemented SSE streaming in `OpenAIManager` and `OpenAIProvider`.
- Vision: Multimodal input mapping from `ChatMessage` supported.
- Error handling: OpenAI error schema mapped.
- Configuration: Standardized via `ProvidersConfig`.

## Remaining (spec deltas and polish)
1) Responses API vs Chat Completions
- Currently using `v1/chat/completions` as the primary workhorse.
- `OpenAIManager` is structured to easily add `/responses` support if needed later, but parity is achieved via the existing implementation.

2) Tool use execution
- The schema is supported in `OpenAIManager`, but the execution loop resides in the Agent layer (outside Provider scope).

3) Video & Files
- `OpenAIManager` has hooks for Audio/Images. Video generation (`sora` or similar) endpoints are not yet fully standardized in the public API docs used, but can be added to `OpenAIManager` when stable.

Integration is considered complete for the Provider layer.
