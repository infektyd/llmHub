## Plan: anthropicXaiDynamicModelLists

Make Anthropic and xAI model lists truly dynamic by fetching from their official APIs (with correct headers), caching and persisting results, and overlay-merging these dynamic lists on top of the existing `ProvidersConfig` defaults so the UI remains stable and usable offline. Add robust pagination, fallbacks (cached → curated defaults), explicit logging at key points, and a small migration so existing persisted models/hydration still work even when a model disappears or renames.

### Steps
1. Add model-list fetchers for Anthropic and xAI in [llmHub/Services/ModelFetch/ModelFetchService.swift](llmHub/Services/ModelFetch/ModelFetchService.swift) using `LLMURLSession.shared` and provider-specific auth headers.
2. Implement correct pagination loops and decoding types for each provider’s `/models` response shape, including safe early-exit on malformed pages.
3. Overlay-merge fetched models into `ProvidersConfig`-backed defaults (don’t replace), and plumb into [llmHub/Services/ModelFetch/ModelRegistry.swift](llmHub/Services/ModelFetch/ModelRegistry.swift) so cached persistence and `modelsByProvider` stay consistent.
4. Add failure fallbacks: dynamic fetch → cached `ModelRegistryCache` → `makeDefaultConfig()` curated lists; log which tier was chosen.
5. Add persistence/hydration migration rules for previously-selected models (missing/renamed) to resolve to a safe default and keep the chat/session load working; update provider ID canonicalization assumptions if needed.
6. Add 2–4 focused unit tests covering pagination, overlay merge behavior, and fallback/migration outcomes; run with an exact `xcodebuild` test command.

### Further Considerations
1. Should “models.dev” remain first for Anthropic/xAI, or prefer official `/models` first? Option A official-first (recommended), Option B keep models.dev first, Option C setting-controlled priority.
2. Decide where to store “lastGoodDynamicModels” per provider (UserDefaults vs file vs Keychain); current pattern suggests UserDefaults alongside `ModelRegistryCache`.
3. Clarify how to treat “capability metadata” (context/output/tool support) when APIs don’t provide it; keep defaults authoritative unless explicitly provided.

## Provider API contracts (endpoints, headers, pagination)

### Anthropic
- Endpoint: `GET https://api.anthropic.com/v1/models`
- Required headers:
  - `x-api-key: {ANTHROPIC_API_KEY}`
  - `anthropic-version: 2023-06-01`
  - `Accept: application/json`
- Optional: `anthropic-beta: ...` (do **not** require for models listing; only add if Anthropic docs require it for `/models` in your current integration)
- Pagination handling:
  - Anthropic model list is commonly cursor-based. Plan for query parameters:
    - `?limit={N}` (default 100)
    - `?before_id={model_id}` or `?after_id={model_id}` (cursor style varies by doc version)
  - Implementation approach:
    - Start with `limit=100`
    - While response indicates more pages (e.g., `has_more == true`) and provides a cursor (`next_page` / `last_id` / similar):
      - Request next page with that cursor field
    - Stop if:
      - `has_more` is false, OR
      - cursor is missing/unchanged (prevent infinite loops), OR
      - a hard page cap is reached (e.g., 20 pages)
- Response decoding expectations (plan-level):
  - Expect a top-level list field (often `data: [...]`) with per-model objects containing at least `id` (string). If display names exist, use them; otherwise format from `id`.

### xAI
- Endpoint (OpenAI-compatible): `GET https://api.x.ai/v1/models`
- Required headers:
  - `Authorization: Bearer {XAI_API_KEY}`
  - `Accept: application/json`
- Pagination handling:
  - OpenAI `/v1/models` is typically unpaginated; however plan defensively:
    - If response includes `data` only: treat as single page.
    - If provider adds pagination later (cursor/offset), detect known fields (`has_more`, `next`, `page`) and loop similarly to Anthropic with a hard cap.
- Response decoding expectations:
  - OpenAI-like structure: `{ "data": [ { "id": "...", ... } ] }`.

## Overlay merge approach (ProvidersConfig + dynamic models)

### Goals
- Preserve curated defaults from `makeDefaultConfig()` as the “stable contract” for:
  - `contextWindow`, `maxOutputTokens`, and `supportsToolUse` (often missing from provider list endpoints).
- Add any newly-discovered model IDs so users can pick them immediately.
- Avoid breaking persisted selections when dynamic lists temporarily fail.

### Merge rules (per provider: Anthropic, xAI)
Given:
- `defaults = makeDefaultConfig().anthropic.models` (or `.xai.models`)
- `dynamic = fetchedModelsFromAPI` (IDs + optional name)
Produce:
- `merged` keyed by `LLMModel.id`:
  1. Start with all `defaults` in a dictionary by `id`.
  2. For each `dynamicModel`:
     - If `id` exists in defaults: keep default’s numeric capabilities; optionally update *display name only* if API supplies a better name (guarded by “non-empty & not just id”).
     - If `id` is new: insert with conservative placeholders derived from defaults:
       - `contextWindow`: use the max (or most common) from defaults, or a safe conservative value.
       - `maxOutputTokens`: safe conservative value (e.g., min(default maxOutputTokens, 8192) unless you already store a better policy).
       - `supportsToolUse`: default true for these providers in llmHub unless known otherwise (align with existing curated list intent).
  3. Sort merged list deterministically (e.g., curated ordering first, then new IDs alphabetically).
- Store the merged list into `modelsByProvider[providerID]` and into model cache persistence.

### Where to apply merge
- Prefer doing it in `ModelRegistry.fetchModelsForProvider(...)` right after successful provider fetch, so:
  - the same merge logic applies whether source is official endpoint or models.dev.
- Keep `ProvidersConfig` as the baseline source of truth and avoid mutating `makeDefaultConfig()`; treat merge output as runtime state.

## Failure fallbacks (and when to use each)

### Fetch order recommendation (official-first)
For `.anthropic` and `.xai` in `ModelRegistry.fetchModelsForProvider`:
1. Try official provider endpoint `/v1/models` (requires API key, lowest latency, most authoritative for availability).
2. If it fails: try `ModelsDevService.shared.fetchModels(for: providerID)` (best-effort third-party index).
3. If it fails or returns empty: use curated defaults (existing `ModelFetchService.getCurated...()` / `makeDefaultConfig()`).
4. In all failure cases:
   - If `modelCache[providerID]` exists and is not too old, prefer cached over curated (keeps user selection stable).

### Exact fallback behavior
- If official fetch succeeds but returns empty:
  - Treat as suspicious; log warning and fall back to cached → curated rather than showing “no models”.
- If official fetch returns partial pages then fails mid-pagination:
  - Use the partial set if it’s non-empty, but still overlay-merge with defaults.
  - Log that pagination ended early and why.

## Persistence + hydration migration rules

### Existing persistence
- `ModelRegistry` persists models in UserDefaults under `ModelRegistryCache`.
- Sessions or UI selection likely references `providerID` + `modelID`.

### Migration/hydration rules to add (without breaking existing users)
1. Provider ID canonicalization:
  - Ensure persisted provider IDs map through `ProviderID.canonicalID(from:)` (already exists in [llmHub/Services/Support/ProviderRegistry.swift](llmHub/Services/Support/ProviderRegistry.swift)).
   - If any persisted sessions store legacy provider names (e.g., “Claude”, “Grok”), always canonicalize before lookup.
2. Selected model missing:
   - When hydrating a selected model ID for a provider, if it’s not found in `modelsByProvider[providerID]`:
     - Try to find a replacement by heuristics:
       - Exact ID match (case-sensitive), then case-insensitive.
       - If Anthropic: allow mapping from “alias-like” IDs (if any existed historically) to current IDs via a small hardcoded map.
     - If still missing: fallback to the provider’s first curated flagship model from defaults (e.g., newest Sonnet/Opus, or the first item in `makeDefaultConfig().{provider}.models`).
   - Persist the resolved replacement so the app doesn’t repeat migration each launch.
3. Cached dynamic vs curated capability differences:
   - If cached models include “placeholder” token limits from earlier versions, and curated defaults now have better values:
     - On load, re-run overlay merge (defaults win on numeric capabilities) before exposing models to UI.

## Required logging points (what to log, where)

### In ModelRegistry (high-level control plane)
- Start/end of provider fetch attempt:
  - provider ID, forceRefresh, cache age, source chosen (official/models.dev/cache/curated).
- On fallback:
  - include error domain/code/message (if NSError), and which tier was used next.
- On persistence:
  - number of models saved per provider, last fetch date.

### In ModelFetchService (network/data plane)
- Before request:
  - provider, endpoint URL (no query secrets), pagination params, timeout used.
- After response:
  - HTTP status code, decoded count for that page, cursor/hasMore fields (redacted).
- On decode failure:
  - include “page index” and a small safe preview length (not full body) to avoid sensitive logging.

### In providers (optional)
- No changes required in `AnthropicProvider` / `XAIProvider` except updating `fetchModels()` to delegate to the new dynamic mechanism (or clarifying it’s now dynamic).

## Minimal tests (2–4)

1. Pagination loop (Anthropic-style cursor)
   - Given two stubbed pages with `has_more=true` then `false`, assert merged result contains IDs from both pages and stops correctly when `has_more=false`.
2. Overlay merge preserves curated capabilities
   - Given curated model with `contextWindow/maxOutputTokens`, and dynamic response for same ID with missing capabilities, assert merged keeps curated numeric fields and only updates name if allowed.
3. Fallback chain uses cache before curated
   - Simulate official fetch failure and existing `ModelRegistryCache` for provider; assert returned models == cached (and not empty curated) and logs indicate cache fallback.
4. Missing selected model migration
   - With a persisted selected model ID not present in merged list, assert resolution selects curated default model and persists the new selection.

## Focused xcodebuild command (run only relevant tests)

Use a single simulator destination (adjust device if needed), and target the smallest test bundle where you place the new tests (likely `llmHubTests`):

```bash
xcodebuild test \
  -project llmHub.xcodeproj \
  -scheme llmHub \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:llmHubTests/ModelRegistryTests
```

(If you place tests under a different class/file name, replace `ModelRegistryTests` accordingly.)
