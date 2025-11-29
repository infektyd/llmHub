// xai_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding `XAIProvider` (Grok) and any Grok integration docs.

// What’s already done
// - Provider: `XAIProvider` using `XAIManager`
// - Manager: `XAIManager` handling Text, Vision, Streaming, and Tool schemas
// - Streaming: Implemented SSE streaming in `XAIManager` and `XAIProvider`
// - Error handling: Mapped common errors in `XAIManager`
// - Vision: Mapped in `XAIManager`; `XAIProvider` ready for content parts
// - Configuration: Base URL and Key support
// - Availability: Updated to iOS/macOS 26.1 as requested

// Remaining (spec deltas and polish)
// 1) Tool use execution
// - The schema is supported in `XAIManager`, but the execution loop resides in the Agent layer (outside Provider scope)

// 2) Image Generation
// - `XAIManager` doesn't strictly have a separate image gen method yet (xAI uses OpenAI-compat image gen usually), but Chat/Vision is the core requirement.

// Integration is considered complete for the Provider layer.
