# AFM → Gemini Flash Fallback Verification

## Pinned model used

- llmHub fallback constant: `GeminiPinnedModels.afmFallbackFlash`
- Current value: `gemini-2.0-flash-001` (pinned suffix)

## How it was verified (Models endpoint)

This repo includes a small development verification script that calls the official Google Gemini Models endpoint and checks for the pinned model:

- Script: `scripts/verify_gemini_models.swift`
- Required env var: `GOOGLE_API_KEY`
- Run:
  - `GOOGLE_API_KEY=... scripts/verify_gemini_models.swift`

The script:

- Calls `https://generativelanguage.googleapis.com/v1beta/models`
- Confirms `models/gemini-2.0-flash-001` exists
- Prints `supportedGenerationMethods` (expects `generateContent`; streaming may appear as `streamGenerateContent`)

## Manual checklist (app)

- AFM unavailable/disabled:
  - Conversation classification falls back to Gemini Flash and still produces metadata.
  - Memory distillation falls back to Gemini Flash and persists a memory (if a Google API key is configured).

- Gemini fallback safety defaults:
  - Temperature is explicitly set to `0.0` for the AFM fallback.

## Notes

If Google deprecates `gemini-2.0-flash-001`, rerun the script and update `GeminiPinnedModels.afmFallbackFlash` to the closest pinned Flash successor (documenting the exact replacement and why).
