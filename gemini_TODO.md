// gemini_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding `GeminiManager.swift` and `GoogleAIProvider` (if applicable). 
// We have one-shot text/vision and basic image/video gen; below are deltas to productionize.

/// What’s already done
/// - Manager: `GeminiManager.swift` with text/vision/video helpers
/// - Base endpoint: `https://generativelanguage.googleapis.com/v1beta`
/// - Image gen (Imagen 3) helper with response parsing
/// - Video gen (Veo) helper stub (notes on long-running operation/polling)

/// Remaining (spec deltas and polish)
/// 1) Provider wiring
///   - Add `GoogleAIProvider` usage path to prefer `GeminiManager` under the hood for consistency
///   - Map `ChatMessage` history to Gemini content parts (including media)
///
/// 2) Streaming
///   - If Gemini streaming is needed, add streaming method and SSE parsing for `generateContent` equivalents
///
/// 3) Thinking mode / reasoning
///   - Expose `thinkingLevel` control; add convenience for high reasoning tasks
///   - Propagate and store "thought signature" in conversation history when present
///
/// 4) Media inputs
///   - Add support for uploading large files via Google file APIs if needed (or document limits)
///   - Validate MIME type handling and size constraints
///
/// 5) Imagen 3 options
///   - Add aspect ratio/seed/sampler parameters as available in current API
///   - Support multiple images per request and base64 decoding helpers
///
/// 6) Veo video generation
///   - Implement proper long-running Operation polling to resolve to final video URL
///   - Add optional params (duration, style, resolution) when stable
///
/// 7) Error handling & retry/backoff
///   - Map common Google API errors and backoff on 429/5xx
///
/// 8) Metrics & logging
///   - Emit latency metrics; optional usage if API returns it
///   - Add debug logging toggle
///
/// 9) Documentation & samples
///   - Doc comments and README snippets for text, vision, thinking, Imagen, and Veo flows
///
/// Integration with existing llmHub providers
/// - Ensure `GoogleAIProvider` delegates to `GeminiManager` for consistent surface
/// - Provide a non-streaming fallback path in `GoogleAIProvider` and document it
///
/// Testing checklist (to automate)
/// - Text: Q&A with two different Gemini models
/// - Vision: prompt + single image (URL and inline)
/// - Imagen: generate and decode one image
/// - Veo: generate and poll until URL is available (or error surfaced)
/// - Errors: bad key, quota exceeded, invalid model
///
/// Open questions / decisions
/// - Which Gemini models to expose in UI by default?
/// - Do we need streaming in v1?
