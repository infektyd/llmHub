// gemini_TODO — Remaining integration items (Nov 2025)

// This checklist tracks what’s left to do after adding `GeminiManager.swift` and `GoogleAIProvider` (if applicable). 
// We have one-shot text/vision and basic image/video gen; below are deltas to productionize.

/// What’s already done
/// - Manager: `GeminiManager.swift` with text/vision/video helpers
/// - Base endpoint: `https://generativelanguage.googleapis.com/v1beta`
/// - Image gen (Imagen 3) helper with response parsing
/// - Video gen (Veo) helper with polling
/// - Streaming support (via `streamGenerateContent`)
/// - Error handling mapped (rate limits, quota)

/// Remaining (spec deltas and polish)
/// 1) Provider wiring
///   - [x] Add `GoogleAIProvider` usage path to prefer `GeminiManager` under the hood for consistency
///   - [x] Map `ChatMessage` history to Gemini content parts (including media - text only implemented)
///
/// 2) Streaming
///   - [x] If Gemini streaming is needed, add streaming method and SSE parsing for `generateContent` equivalents
///
/// 3) Thinking mode / reasoning
///   - [x] Expose `thinkingLevel` control; add convenience for high reasoning tasks
///   - [ ] Propagate and store "thought signature" in conversation history when present (Requires ChatMessage model update)
///
/// 4) Media inputs
///   - [ ] Add support for uploading large files via Google file APIs if needed (or document limits)
///   - [ ] Validate MIME type handling and size constraints
///
/// 5) Imagen 3 options
///   - [ ] Add aspect ratio/seed/sampler parameters as available in current API
///   - [ ] Support multiple images per request and base64 decoding helpers
///
/// 6) Veo video generation
///   - [x] Implement proper long-running Operation polling to resolve to final video URL
///   - [ ] Add optional params (duration, style, resolution) when stable
///
/// 7) Error handling & retry/backoff
///   - [x] Map common Google API errors and backoff on 429/5xx
///
/// 8) Metrics & logging
///   - [ ] Emit latency metrics; optional usage if API returns it
///   - [ ] Add debug logging toggle
///
/// 9) Documentation & samples
///   - [ ] Doc comments and README snippets for text, vision, thinking, Imagen, and Veo flows
///
/// Integration with existing llmHub providers
/// - [x] Ensure `GoogleAIProvider` delegates to `GeminiManager` for consistent surface
/// - [x] Provide a non-streaming fallback path in `GoogleAIProvider` and document it
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
/// - Do we need streaming in v1? (Yes, implemented)
