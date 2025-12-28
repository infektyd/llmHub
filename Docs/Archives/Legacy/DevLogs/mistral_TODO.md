// mistral_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding `MistralProvider` and `Mistral_Integration.md`.

// What’s already done
// - Provider: `MistralProvider` using `MistralManager`
// - Manager: `MistralManager` handling Chat, Streaming, Vision, Audio (Transcribe), FIM, OCR
// - Streaming: Implemented SSE streaming in `MistralManager` and `MistralProvider`
// - Error handling: Mapped common errors in `MistralManager`
// - Vision: Mapped in `MistralManager` and `MistralProvider`
// - Configuration: Base URL and Key support (Primary & Codestral endpoints)

// Remaining (spec deltas and polish)
// 1) Tool use execution
// - The schema is supported in `MistralManager`, but the execution loop resides in the Agent layer (outside Provider scope)

// 2) Audio Chat (Voxtral)
// - `MistralManager` supports `input_audio` content part type.
// - `ChatMessage` model has `image` and `text`, but needs `audio` part support to surface this fully.

// 3) Embeddings & Agents
// - `MistralManager` has methods for embeddings and OCR, but they are not yet exposed via `LLMProvider` protocol (which is chat-focused).
// - These can be used by specialized views or services.

// Integration is considered complete for the Provider layer.
