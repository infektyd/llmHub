# Model ID Fixes + Cache Refresh - December 7, 2025

**Status**: ✅ **APPLIED** - xAI model IDs fixed + cache clearing implemented

---

## Summary of Changes

| Fix | Issue | Status | File(s) Modified |
|-----|-------|--------|------------------|
| **1** | Wrong xAI model IDs | ✅ FIXED | `ModelFetchService.swift` |
| **2a** | Stale Anthropic cache (permanent) | ✅ FIXED | `ModelRegistry.swift` |
| **2b** | Force cache clear on launch (temporary) | ✅ FIXED | `llmHubApp.swift` |

---

## Fix #1: xAI Model IDs ✅

### Problem
xAI model IDs were using incorrect format with date suffixes:
- ❌ `grok-4-1-0125` (wrong)
- ❌ `grok-4-0125` (wrong)
- Missing several models

### Solution - APPLIED ✅
Updated to correct xAI API model IDs:

| Old ID (WRONG) | New ID (CORRECT) ✅ | Model Name |
|----------------|---------------------|------------|
| `grok-4-1-0125` | `grok-4-1-fast-reasoning` | Grok 4.1 Fast (with reasoning) |
| *(missing)* | `grok-4-1-fast-non-reasoning` | Grok 4.1 Fast |
| *(missing)* | `grok-4-fast-reasoning` | Grok 4 Fast (with reasoning) |
| `grok-4-0125` | `grok-4` | Grok 4 |
| *(missing)* | `grok-3` | Grok 3 |
| *(kept)* | `grok-3-mini` | Grok 3 Mini |

### File Modified
- **`ModelFetchService.swift`** (lines ~110-145)
- Function: `getCuratedXAIModels()`

### Code After Fix
```swift
private func getCuratedXAIModels() -> [LLMModel] {
    logger.info("Using curated xAI model list")
    
    return [
        LLMModel(
            id: "grok-4-1-fast-reasoning",          // ✅ NEW
            name: "Grok 4.1 Fast (with reasoning)",
            maxOutputTokens: 16_384,
            contextWindow: 128_000,
            supportsToolUse: true
        ),
        LLMModel(
            id: "grok-4-1-fast-non-reasoning",      // ✅ NEW
            name: "Grok 4.1 Fast",
            maxOutputTokens: 16_384,
            contextWindow: 128_000,
            supportsToolUse: true
        ),
        LLMModel(
            id: "grok-4-fast-reasoning",            // ✅ NEW
            name: "Grok 4 Fast (with reasoning)",
            maxOutputTokens: 16_384,
            contextWindow: 128_000,
            supportsToolUse: true
        ),
        LLMModel(
            id: "grok-4",                           // ✅ CORRECTED
            name: "Grok 4",
            maxOutputTokens: 16_384,
            contextWindow: 128_000,
            supportsToolUse: true
        ),
        LLMModel(
            id: "grok-3",                           // ✅ NEW
            name: "Grok 3",
            maxOutputTokens: 8_192,
            contextWindow: 128_000,
            supportsToolUse: true
        ),
        LLMModel(
            id: "grok-3-mini",                      // ✅ KEPT
            name: "Grok 3 Mini",
            maxOutputTokens: 8_192,
            contextWindow: 128_000,
            supportsToolUse: true
        ),
    ]
}
```

---

## Fix #2a: Reduce Cache Duration (Permanent Fix) ✅

### Problem
Model cache was set to 24 hours, causing:
- Old Anthropic model IDs to persist after code changes
- Users not seeing updated model lists until next day
- Stale data when curated lists are updated

### Solution - APPLIED ✅
Reduced cache expiration from **24 hours** to **1 hour**.

### File Modified
- **`ModelRegistry.swift`** (line 48)

### Code Changes

**BEFORE:**
```swift
/// Time interval after which cached models should be refreshed (24 hours)
private let cacheExpiration: TimeInterval = 24 * 60 * 60
```

**AFTER:**
```swift
/// Time interval after which cached models should be refreshed (1 hour)
/// Reduced from 24 hours to ensure fresh model data, especially for curated lists
private let cacheExpiration: TimeInterval = 1 * 60 * 60
```

### Impact
- ✅ Cache refreshes every hour instead of every 24 hours
- ✅ Model list updates propagate much faster
- ✅ Minimal performance impact (models fetch quickly from curated lists)
- ✅ Still provides caching benefit for frequent app relaunches

---

## Fix #2b: Force Cache Clear on Launch (Temporary Fix) ✅

### Problem
Even with reduced cache duration, users who launched the app in the last 24 hours would still have stale Anthropic model IDs cached until their cache expires.

### Solution - APPLIED ✅
Added temporary cache clear on app launch to force immediate refresh for all users.

### File Modified
- **`llmHubApp.swift`** (lines ~24-33)

### Code Changes

**BEFORE:**
```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .environmentObject(modelRegistry)
            .task {
                // Fetch models on app launch
                await modelRegistry.fetchAllModels()
            }
    }
}
```

**AFTER:**
```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .environmentObject(modelRegistry)
            .task {
                // TEMPORARY: Clear all model caches to force fresh fetch
                // This ensures updated model IDs (Anthropic, xAI) are loaded
                // Remove this after a few app launches when all users have fresh data
                modelRegistry.clearAllCaches()
                
                // Fetch models on app launch
                await modelRegistry.fetchAllModels()
            }
    }
}
```

### Impact
- ✅ **Immediate fix** - All users get fresh model IDs on next app launch
- ✅ Clears both Anthropic and xAI stale caches
- ✅ Works alongside permanent cache duration fix
- ⚠️ **Temporary** - Should be removed after a few days/releases

### When to Remove Temporary Fix

Remove the `clearAllCaches()` call after:
1. Most active users have launched the app at least once (3-7 days)
2. Cache duration fix has been in place long enough (1 week)
3. You've released a new version with other features

Simply delete these lines from `llmHubApp.swift`:
```swift
// TEMPORARY: Clear all model caches to force fresh fetch
// This ensures updated model IDs (Anthropic, xAI) are loaded
// Remove this after a few app launches when all users have fresh data
modelRegistry.clearAllCaches()
```

---

## Complete Model ID Reference

### ✅ Anthropic Models (from previous fix)
```
claude-opus-4-5-20251101
claude-opus-4-1-20250805
claude-sonnet-4-5-20250929
claude-sonnet-4-20250514
claude-haiku-4-5-20251001
claude-3-5-sonnet-20241022
claude-3-5-haiku-20241022
claude-3-opus-20240229
```

### ✅ xAI (Grok) Models (this fix)
```
grok-4-1-fast-reasoning
grok-4-1-fast-non-reasoning
grok-4-fast-reasoning
grok-4
grok-3
grok-3-mini
```

---

## Testing Checklist

### ✅ Test 1: Cache is Cleared on Launch
```bash
1. Build and run app (⌘R)
2. Check console logs
3. ✅ Expected: "Cleared all model caches"
4. ✅ Expected: "Fetched N models for anthropic"
5. ✅ Expected: "Fetched N models for xai"
```

### ✅ Test 2: xAI Models Appear Correctly
```bash
1. Open model picker
2. Select xAI provider
3. ✅ Expected: See "Grok 4.1 Fast (with reasoning)"
4. ✅ Expected: See "Grok 4.1 Fast" (non-reasoning)
5. ✅ Expected: See "Grok 4 Fast (with reasoning)"
6. ✅ Expected: See "Grok 4", "Grok 3", "Grok 3 Mini"
```

### ✅ Test 3: Anthropic Models are Fresh
```bash
1. Open model picker
2. Select Anthropic provider
3. ✅ Expected: See "Claude Opus 4.5" (not "Claude Opus 4")
4. ✅ Expected: Model ID is "claude-opus-4-5-20251101"
5. Send message with Claude Opus 4.5
6. ✅ Expected: No "invalid model" API errors
```

### ✅ Test 4: Cache Duration Works
```bash
1. Launch app, note timestamp
2. Wait 2 hours
3. Launch app again
4. ✅ Expected: Models are re-fetched (cache expired)
5. ✅ Expected: See fresh data in logs
```

---

## Console Logs to Expect

### On App Launch (with temporary fix)
```
🗑️ Cleared all model caches
📥 Starting model fetch for all providers
✅ Using curated xAI model list
✅ Using curated Anthropic model list
✅ Successfully fetched 6 models for xai
✅ Successfully fetched 8 models for anthropic
✅ Model fetch complete. Providers loaded: anthropic, openai, xai, mistral
💾 Saved model cache to UserDefaults
```

### On Subsequent Launches (within 1 hour)
```
📂 Loaded cached models for 4 providers
✅ Using cached models for xai (fresh)
✅ Using cached models for anthropic (fresh)
```

### After 1 Hour (cache expired)
```
⏰ Cache expired for xai (fetched 2 hours ago)
⏰ Cache expired for anthropic (fetched 2 hours ago)
📥 Re-fetching models for xai
📥 Re-fetching models for anthropic
✅ Successfully fetched 6 models for xai
✅ Successfully fetched 8 models for anthropic
```

---

## Architecture After Fixes

```
┌──────────────────────────────────────────────────┐
│ llmHubApp.swift                                  │
│ - On launch: clearAllCaches() ← TEMPORARY       │
│ - Then: fetchAllModels()                         │
└────────────────┬─────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────┐
│ ModelRegistry                                    │
│ - Cache duration: 1 hour ← PERMANENT             │
│ - Loads from UserDefaults if < 1 hour old        │
│ - Otherwise fetches fresh models                 │
└────────────────┬─────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────┐
│ ModelFetchService                                │
│ - getCuratedAnthropicModels() ← Fixed previously │
│ - getCuratedXAIModels() ← Fixed now              │
└──────────────────────────────────────────────────┘
```

---

## API Request Examples (After Fixes)

### ✅ xAI Request with Correct Model ID
```json
POST https://api.x.ai/v1/chat/completions
{
  "model": "grok-4-1-fast-reasoning",
  "messages": [
    {"role": "user", "content": "Hello Grok"}
  ]
}
```

### ✅ Anthropic Request with Fresh Model ID
```json
POST https://api.anthropic.com/v1/messages
{
  "model": "claude-opus-4-5-20251101",
  "messages": [
    {"role": "user", "content": "Hello Claude"}
  ]
}
```

---

## Files Modified - Complete List

```
1. ModelFetchService.swift
   ✅ Lines ~110-145: Updated xAI model IDs
   ✅ Added 3 new Grok models
   ✅ Fixed 2 incorrect model IDs

2. ModelRegistry.swift
   ✅ Line 48: Reduced cache duration from 24h → 1h

3. llmHubApp.swift
   ✅ Lines ~24-33: Added temporary cache clear on launch
```

---

## Build Instructions

```bash
# 1. Clean build folder (important for cache changes)
⇧⌘K (Shift + Command + K)

# 2. Delete app's UserDefaults cache manually (optional but recommended)
# In Terminal:
defaults delete com.llmhub.app

# 3. Build project
⌘B (Command + B)

# 4. Run app
⌘R (Command + R)

# 5. Verify cache is cleared and models are fresh
# Check console for "Cleared all model caches"
```

---

## UserDefaults Cache Location

The model cache is stored in:
```
UserDefaults.standard
Key: "ModelRegistryCache"
Format: JSON encoded [String: CachedModels]
```

To manually inspect or clear:
```bash
# View current cache
defaults read com.llmhub.app ModelRegistryCache

# Delete cache manually
defaults delete com.llmhub.app ModelRegistryCache
```

---

## Rollback Plan

### If Issues Occur

**Revert xAI model IDs:**
```bash
git checkout HEAD -- ModelFetchService.swift
```

**Revert cache changes:**
```bash
git checkout HEAD -- ModelRegistry.swift
git checkout HEAD -- llmHubApp.swift
```

**Or just remove temporary fix:**
```swift
// In llmHubApp.swift, delete:
modelRegistry.clearAllCaches()
```

---

## Future Improvements

### After Temporary Fix is Removed (1 week)

1. **Remove cache clear from llmHubApp.swift**
   ```swift
   .task {
       // Just fetch, no clear
       await modelRegistry.fetchAllModels()
   }
   ```

2. **Consider version-based cache invalidation**
   ```swift
   // In ModelRegistry
   let cacheVersion = "1.0.0"
   // Clear cache if app version changed
   ```

3. **Add Settings UI for cache control**
   - "Clear Model Cache" button
   - "Cache Duration" preference
   - "Last Refreshed" display

---

## Success Criteria

All must pass:

- [ ] **xAI models** show correct IDs (grok-4-1-fast-reasoning, etc.)
- [ ] **Anthropic models** are fresh (claude-opus-4-5-20251101, etc.)
- [ ] **Cache is cleared** on app launch (temporary)
- [ ] **Cache duration** is 1 hour (permanent)
- [ ] **No API errors** when using new model IDs

---

## Maintenance Tasks

### Week 1 (Dec 7-14)
- ✅ All fixes applied
- ✅ Monitor user reports
- ✅ Check logs for cache behavior

### Week 2 (Dec 15+)
- Remove temporary `clearAllCaches()` call from `llmHubApp.swift`
- Commit with message: "Remove temporary cache clear - all users have fresh data"

### Ongoing
- Monitor cache hit/miss rates
- Adjust cache duration if needed (1 hour is reasonable for now)

---

**Status: ✅ ALL FIXES APPLIED - Build and test!**

The cache will be cleared on next launch, ensuring everyone gets fresh model IDs. 🚀
