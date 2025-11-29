// openrouter_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding `OpenRouterManager` and `OpenRouterProvider`.

// What’s already done
// - Manager: `OpenRouterManager` handling Chat (Completions), Streaming, Multimodal inputs (Vision).
// - Provider: `OpenRouterProvider` fully delegates to `OpenRouterManager`.
// - Streaming: Implemented SSE streaming in `OpenRouterManager` and `OpenRouterProvider`.
// - Vision: Multimodal input mapping from `ChatMessage` supported.
// - Error handling: OpenRouter error schema mapped.
// - Configuration: Standardized via `ProvidersConfig`.

// Remaining (spec deltas and polish)
// 1) Responses API (Optional)
// - Currently using `v1/chat/completions` which is the standard. OpenRouter's `/responses` API is newer and less standard, but `OpenRouterManager` is structured to add it if required.

// 2) Tool use execution
// - The schema is present in `OpenRouterManager`, but the execution loop resides in the Agent layer (outside Provider scope).

// 3) Usage/Cost tracking
// - Basic token usage is parsed. OpenRouter provides detailed cost info which could be surfaced if `TokenUsage` model is expanded.

// Integration is considered complete for the Provider layer.
