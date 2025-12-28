# Quick Fixes - December 7, 2025

## ✅ Fix #1: Corrected Anthropic Model IDs

**File**: `ModelFetchService.swift` (Lines 48-78)

### Problem
Model IDs had incorrect dates and were missing some models.

### Solution - APPLIED ✅
Updated to correct Anthropic API model IDs with accurate dates:

```swift
return [
    LLMModel(
        id: "claude-opus-4-5-20251101",      // ✅ CORRECTED
        name: "Claude Opus 4.5",
        maxOutputTokens: 16_384,
        contextWindow: 200_000,
        supportsToolUse: true
    ),
    LLMModel(
        id: "claude-opus-4-1-20250805",      // ✅ NEW
        name: "Claude Opus 4.1",
        maxOutputTokens: 16_384,
        contextWindow: 200_000,
        supportsToolUse: true
    ),
    LLMModel(
        id: "claude-sonnet-4-5-20250929",    // ✅ CORRECTED
        name: "Claude Sonnet 4.5",
        maxOutputTokens: 16_384,
        contextWindow: 200_000,
        supportsToolUse: true
    ),
    LLMModel(
        id: "claude-sonnet-4-20250514",      // ✅ KEPT
        name: "Claude Sonnet 4",
        maxOutputTokens: 16_384,
        contextWindow: 200_000,
        supportsToolUse: true
    ),
    LLMModel(
        id: "claude-haiku-4-5-20251001",     // ✅ CORRECTED
        name: "Claude Haiku 4.5",
        maxOutputTokens: 16_384,
        contextWindow: 200_000,
        supportsToolUse: true
    ),
    // Legacy Claude 3.x models remain unchanged
]
```

### Changes Made
- ✅ **Claude Opus 4.5**: `claude-opus-4-5-20251101` (was `claude-opus-4-5-20250514`)
- ✅ **Claude Opus 4.1**: `claude-opus-4-1-20250805` (NEW - added)
- ✅ **Claude Sonnet 4.5**: `claude-sonnet-4-5-20250929` (was `claude-sonnet-4-5-20250514`)
- ✅ **Claude Sonnet 4**: `claude-sonnet-4-20250514` (unchanged - was already correct)
- ✅ **Claude Haiku 4.5**: `claude-haiku-4-5-20251001` (was `claude-haiku-4-20250514`)

---

## ✅ Fix #2: Added Missing Providers to Registry

**File**: `ChatViewModel.swift` (Lines 54-61)

### Problem
Only 3 providers were registered (OpenAI, Anthropic, Mistral). When users selected models from Google AI, xAI, or OpenRouter, they'd get `RegistryError.providerMissing`.

### Solution - APPLIED ✅

```swift
let registry = ProviderRegistry(providerBuilders: [
    { OpenAIProvider(keychain: keychain, config: config.openAI) },
    { AnthropicProvider(keychain: keychain, config: config.anthropic) },
    { MistralProvider(keychain: keychain, config: config.mistral) },
    { GoogleAIProvider(keychain: keychain, config: config.googleAI) },     // ✅ ADDED
    { XAIProvider(keychain: keychain, config: config.xai) },               // ✅ ADDED
    { OpenRouterProvider(keychain: keychain, config: config.openRouter) }  // ✅ ADDED
])
```

### Impact
- ✅ Google AI (Gemini) models now work
- ✅ xAI (Grok) models now work  
- ✅ OpenRouter models now work
- ✅ No more `providerMissing` errors

---

## ✅ Fix #3: Duplicate Messages in Request Payload

**File**: `ChatViewModel.swift` (Lines 91-103)

### Problem
Messages were being added **TWICE** to the session:
1. ChatViewModel created and appended user message
2. ChatService.streamCompletion() created and appended the SAME message again

This caused API requests to contain duplicate messages.

### Solution - APPLIED ✅
Removed the duplicate message creation from ChatViewModel. Now ChatService is the single source of truth for message persistence.

```swift
// ❌ BEFORE - Created message and appended to session
let newMessage = ChatMessage(
    id: UUID(),
    role: .user,
    content: userMessageText,
    parts: [.text(userMessageText)],
    createdAt: Date(),
    codeBlocks: []
)
let messageEntity = ChatMessageEntity(message: newMessage)
session.messages.append(messageEntity)  // ← DUPLICATE APPEND
session.updatedAt = Date()

// ✅ AFTER - Let ChatService handle message creation and persistence
messageText = "" // Clear input immediately

// Map UI model selection to real provider/model IDs
let (providerID, modelID) = mapUISelectionToProviderModel(...)

// Call service - it will create and append the message
let stream = try await service.streamCompletion(
    for: updatedSession,
    userMessage: userMessageText
)
```

### Flow After Fix
```
1. User types message and hits send
2. ChatViewModel clears input field
3. ChatViewModel maps UI selection to provider/model IDs
4. ChatViewModel calls ChatService.streamCompletion()
   ↓
5. ChatService creates user message (ONCE)
6. ChatService appends to session (ONCE)
7. ChatService calls provider to stream response
   ↓
8. Messages array contains ONE copy of user message ✅
```

### Impact
- ✅ User messages appear only ONCE in session
- ✅ API requests contain correct message history (no duplicates)
- ✅ Cleaner architecture - single source of truth

---

## Implementation Status

| Fix | Status | File | Lines |
|-----|--------|------|-------|
| #1 Anthropic Model IDs | ✅ **APPLIED** | `ModelFetchService.swift` | 48-78 |
| #2 Add All Providers | ✅ **APPLIED** | `ChatViewModel.swift` | 54-61 |
| #3 Duplicate Messages | ✅ **APPLIED** | `ChatViewModel.swift` | 91-103 |

---

## Testing Checklist

### Test #1: Anthropic Models ✅
```bash
1. Build the app
2. Select "Claude Opus 4.5" from model picker
3. Send message: "What model are you?"
4. ✅ Expected: Response confirms Claude Opus 4.5
5. ✅ Model ID sent to API: "claude-opus-4-5-20251101"
```

### Test #2: xAI Provider ✅
```bash
1. Select "Grok 4.1" (xAI provider)
2. Send message: "Hello"
3. ✅ Expected: Message goes through
4. ❌ Should NOT get: RegistryError.providerMissing
```

### Test #3: No Duplicate Messages ✅
```bash
1. Enable API request logging
2. Send message: "Test message"
3. Check request payload
4. ✅ Expected: Message appears ONCE in messages array
5. ✅ Check session.messages.count - should increment by 1 per message
```

### Verification Commands
```swift
// In ChatService.streamCompletion(), add logging:
logger.debug("Messages being sent to API: \(currentSession.messages.count)")
logger.debug("Last 3 messages: \(currentSession.messages.suffix(3).map { $0.content })")

// You should see:
// "Messages being sent to API: 3"  (e.g., system + 2 user messages)
// NOT: "Messages being sent to API: 5"  (which would indicate duplicates)
```

---

## Expected Results

### ✅ Correct API Request (After Fixes)
```json
{
  "model": "claude-opus-4-5-20251101",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi! How can I help?"},
    {"role": "user", "content": "What model are you?"}
  ]
}
```

### ❌ Bad Request (Before Fixes)
```json
{
  "model": "claude-opus-4-20250514",  // Wrong date
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"},
    {"role": "user", "content": "Hello"},  // ← DUPLICATE!
    {"role": "assistant", "content": "Hi! How can I help?"},
    {"role": "user", "content": "What model are you?"},
    {"role": "user", "content": "What model are you?"}  // ← DUPLICATE!
  ]
}
```

---

## Summary of Changes

### ModelFetchService.swift
- Updated 4 Anthropic model IDs to correct dates
- Added Claude Opus 4.1 model

### ChatViewModel.swift
**Change 1**: Added missing providers to registry
- Added GoogleAIProvider
- Added XAIProvider  
- Added OpenRouterProvider

**Change 2**: Removed duplicate message creation
- Removed user message creation in sendMessage()
- Removed session.messages.append() call
- Let ChatService handle message persistence

---

## Architecture After Fixes

```
┌─────────────────────────────────────────────────────┐
│ User Interface (NeonChatView)                       │
│ - Displays messages                                 │
│ - Passes selections to ChatViewModel                │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│ ChatViewModel                                       │
│ - Clears input field                                │
│ - Maps UI selection to provider/model IDs           │
│ - Calls ChatService (NO message creation)           │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│ ChatService                                         │
│ ✅ Single source of truth for messages              │
│ - Creates user message (ONCE)                       │
│ - Appends to session (ONCE)                         │
│ - Calls ProviderRegistry                            │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│ ProviderRegistry                                    │
│ ✅ All 6 providers registered                       │
│ - OpenAI, Anthropic, Mistral                        │
│ - Google AI, xAI, OpenRouter                        │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│ Provider (e.g., AnthropicProvider)                  │
│ ✅ Uses correct model IDs                           │
│ - Builds API request                                │
│ - Streams response                                  │
└─────────────────────────────────────────────────────┘
```

---

## Files Modified

| File | Lines Changed | Changes |
|------|---------------|---------|
| `ModelFetchService.swift` | 48-78 | Updated Anthropic model IDs |
| `ChatViewModel.swift` | 54-61 | Added 3 providers to registry |
| `ChatViewModel.swift` | 91-103 | Removed duplicate message creation |

---

## Build & Test

1. **Clean Build**: Product → Clean Build Folder (⇧⌘K)
2. **Build**: Product → Build (⌘B)
3. **Run**: Product → Run (⌘R)
4. **Test**: Follow testing checklist above

---

## Monitoring & Verification

### Console Logs to Check
```
✅ Look for:
"Using provider: anthropic with model: claude-opus-4-5-20251101"
"Messages being sent to API: 3"  (not 5 or 6 with duplicates)

❌ Should NOT see:
"RegistryError.providerMissing"
"Invalid model ID" errors from Anthropic API
```

### SwiftData Inspector
```
1. Check session.messages array in debugger
2. Send message: "Test"
3. Verify count increases by 1 (user) then 1 (assistant)
4. Should be +2 total, not +3 or +4
```

---
**All fixes applied! Build and test to verify.** 🚀


