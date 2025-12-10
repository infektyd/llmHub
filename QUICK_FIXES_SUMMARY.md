# Quick Fixes - December 7, 2025

## ✅ Fix #1: Corrected Anthropic Model IDs

**File**: `ModelFetchService.swift` (Lines 48-73)

### Problem
Model IDs had incorrect format with extra dashes:
- ❌ `claude-opus-4-5-20250514` (wrong)
- ❌ `claude-sonnet-4-5-20250514` (wrong) 
- ❌ `claude-haiku-4-5-20250514` (wrong)

### Solution
Updated to correct Anthropic API model IDs:
- ✅ `claude-opus-4-20250514` (Claude Opus 4)
- ✅ `claude-sonnet-4-20250514` (Claude Sonnet 4)
- ✅ `claude-sonnet-4-5-20250514` (Claude Sonnet 4.5) - this one is correct
- ✅ `claude-haiku-4-20250514` (Claude Haiku 4)

### Code Change
```swift
// ❌ BEFORE
LLMModel(
    id: "claude-opus-4-5-20250514",  // Wrong format
    name: "Claude Opus 4.5",
    maxOutputTokens: 16_384,
    contextWindow: 200_000,
    supportsToolUse: true
),

// ✅ AFTER
LLMModel(
    id: "claude-opus-4-20250514",  // Correct API ID
    name: "Claude Opus 4",
    maxOutputTokens: 16_384,
    contextWindow: 200_000,
    supportsToolUse: true
),
```

---

## ✅ Fix #2: Added Missing Providers to Registry

**File**: `ChatViewModel.swift` (Lines 54-62)

### Problem
Only 3 providers were registered:
- ✅ OpenAI
- ✅ Anthropic  
- ✅ Mistral
- ❌ Google AI (commented out)
- ❌ xAI (commented out)
- ❌ OpenRouter (commented out)

When users selected models from these providers, they'd get `RegistryError.providerMissing`.

### Solution
Added all available providers to the registry:

```swift
// ❌ BEFORE
let registry = ProviderRegistry(providerBuilders: [
    { OpenAIProvider(keychain: keychain, config: config.openAI) },
    { AnthropicProvider(keychain: keychain, config: config.anthropic) },
    { MistralProvider(keychain: keychain, config: config.mistral) }
    // TODO: Add remaining providers when they're ready
])

// ✅ AFTER
let registry = ProviderRegistry(providerBuilders: [
    { OpenAIProvider(keychain: keychain, config: config.openAI) },
    { AnthropicProvider(keychain: keychain, config: config.anthropic) },
    { MistralProvider(keychain: keychain, config: config.mistral) },
    { GoogleAIProvider(keychain: keychain, config: config.googleAI) },
    { XAIProvider(keychain: keychain, config: config.xai) },
    { OpenRouterProvider(keychain: keychain, config: config.openRouter) }
])
```

### Impact
- ✅ Google AI (Gemini) models now work
- ✅ xAI (Grok) models now work  
- ✅ OpenRouter models now work
- ✅ No more `providerMissing` errors for these providers

---

## 🔍 Fix #3: Duplicate Messages in Request Payload

### Problem Identified
Messages are being added **TWICE** to the session, causing the API request to contain duplicate messages.

### Root Cause
The user message is created and appended in **TWO PLACES**:

1. **ChatViewModel.sendMessage()** (Line ~103):
```swift
// Creates user message
let newMessage = ChatMessage(
    id: UUID(),
    role: .user,
    content: userMessageText,
    parts: [.text(userMessageText)],
    createdAt: Date(),
    codeBlocks: []
)

// ⚠️ FIRST APPEND - Adds to session
let messageEntity = ChatMessageEntity(message: newMessage)
session.messages.append(messageEntity)  // ← APPEND #1
session.updatedAt = Date()
```

2. **ChatService.streamCompletion()** (Line ~109-120):
```swift
// Creates the SAME user message again
let message = ChatMessage(
    id: UUID(),
    role: .user,
    content: userMessage,  // Same text
    parts: parts,
    createdAt: Date(),
    codeBlocks: [],
    tokenUsage: nil,
    costBreakdown: nil
)

// ⚠️ SECOND APPEND - Adds again!
try appendMessage(message, to: session.id)  // ← APPEND #2
```

### Solution Options

**Option A: Remove duplication from ChatViewModel** (Recommended)
- ChatViewModel should NOT append the message to the session
- Let ChatService handle ALL message persistence
- This is cleaner separation of concerns

**Option B: Remove duplication from ChatService**
- ChatService should NOT create/append the user message
- It should only handle the API call and assistant response
- ChatViewModel handles user message persistence

**Option C: Pass existing message to ChatService**
- ChatViewModel creates and saves the message
- Pass the message object to `streamCompletion()` instead of just the text
- ChatService uses existing message instead of creating new one

### Recommended Fix: Option A

**File**: `ChatViewModel.swift`

```swift
// ❌ BEFORE - ChatViewModel appends message
let messageEntity = ChatMessageEntity(message: newMessage)
session.messages.append(messageEntity)  // ← REMOVE THIS
session.updatedAt = Date()

// Then calls service
let stream = try await service.streamCompletion(
    for: updatedSession,
    userMessage: userMessageText
)

// ✅ AFTER - Let ChatService handle everything
// Remove the append, just call service
let stream = try await service.streamCompletion(
    for: updatedSession,
    userMessage: userMessageText,
    images: []  // Add images parameter if needed
)

// ChatService.streamCompletion() will:
// 1. Create the user message
// 2. Append it to session
// 3. Stream the API response
```

### Alternative Fix: Option C (Keep both but avoid duplication)

Modify ChatService to accept an optional pre-created message:

**File**: `ChatService.swift`

```swift
// Change signature to accept optional message
func streamCompletion(
    for session: ChatSession, 
    userMessage: String, 
    images: [Data] = [],
    existingMessage: ChatMessage? = nil  // ← NEW parameter
) async throws -> AsyncThrowingStream<ProviderEvent, Error> {
    
    // Use existing message if provided, otherwise create new one
    let message: ChatMessage
    if let existing = existingMessage {
        message = existing
    } else {
        var parts: [ChatContentPart] = [.text(userMessage)]
        for imgData in images {
            let mimeType = detectImageMimeType(from: imgData)
            parts.append(.image(imgData, mimeType: mimeType))
        }
        
        message = ChatMessage(
            id: UUID(),
            role: .user,
            content: userMessage,
            parts: parts,
            createdAt: Date(),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil
        )
        
        // Only append if we created it (not provided)
        try appendMessage(message, to: session.id)
    }
    
    // Rest of the function...
}
```

Then in ChatViewModel, pass the message:

```swift
// Keep the append in ChatViewModel
let messageEntity = ChatMessageEntity(message: newMessage)
session.messages.append(messageEntity)

// But pass the message to avoid duplication
let stream = try await service.streamCompletion(
    for: updatedSession,
    userMessage: userMessageText,
    images: [],
    existingMessage: newMessage  // ← Pass the message
)
```

### Which Option to Choose?

| Option | Pros | Cons |
|--------|------|------|
| **A** | Cleaner, single source of truth | ChatViewModel loses immediate feedback |
| **B** | ViewModel controls UI state | Service signature changes significantly |
| **C** | Keeps both working, minimal changes | Adds complexity with optional parameter |

**Recommendation: Go with Option A**
- Cleaner architecture
- ChatService is the single source of truth for message persistence
- Easier to maintain

---

## Implementation Status

| Fix | Status | File |
|-----|--------|------|
| #1 Anthropic Model IDs | ✅ Applied | `ModelFetchService.swift` |
| #2 Add All Providers | ✅ Applied | `ChatViewModel.swift` |
| #3 Duplicate Messages | ⏳ Needs Decision | `ChatViewModel.swift` + `ChatService.swift` |

---

## Testing After Fixes

### Test #1: Anthropic Models
```
1. Select "Claude Opus 4" from model picker
2. Send message: "What model are you?"
3. ✅ Expected: Response confirms Claude Opus 4
4. ❌ Should NOT get: API error about invalid model ID
```

### Test #2: Additional Providers
```
1. Select "Gemini Pro" (Google AI)
2. Send message
3. ✅ Expected: Message goes through
4. ❌ Should NOT get: RegistryError.providerMissing

1. Select "Grok 4.1" (xAI)
2. Send message  
3. ✅ Expected: Message goes through
4. ❌ Should NOT get: RegistryError.providerMissing
```

### Test #3: Duplicate Messages (After fix is applied)
```
1. Enable API request logging
2. Send message: "Hello"
3. Check request payload
4. ✅ Expected: Message appears ONCE in messages array
5. ❌ Should NOT see: Same message twice in request
```

---

## Next Steps

1. **Build the project** - Verify fixes #1 and #2 compile
2. **Choose option for fix #3** - Decide on Option A, B, or C
3. **Apply fix #3** - Implement the chosen solution
4. **Test all three fixes** - Use the test scenarios above
5. **Monitor logs** - Verify correct model IDs and no duplicates

---

## Expected Log Output (After All Fixes)

```
✅ UI Selection - Provider: Anthropic, Model: Claude Opus 4
✅ Mapped to - Provider ID: anthropic, Model ID: claude-opus-4-20250514
✅ Using provider: anthropic with model: claude-opus-4-20250514
✅ Request payload:
{
  "model": "claude-opus-4-20250514",
  "messages": [
    {"role": "user", "content": "Hello"}  // ← Only once!
  ]
}
```

---
