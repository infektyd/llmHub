# Critical Bugs - Fixes Applied

**Date**: December 7, 2025  
**Status**: ✅ ALL THREE FIXES APPLIED

---

## Summary

Applied all three fixes from `CRITICAL_BUGS_ANALYSIS.md` to fix the model selection flow:

1. ✅ **Pass model selection to sendMessage()** - NeonChatView now passes selections
2. ✅ **Store actual model ID** - UILLMModel now stores API model IDs
3. ✅ **Normalize provider IDs** - ProviderRegistry handles case-insensitive lookups

---

## Fix #1: NeonChatView.swift

**File**: `NeonChatView.swift` (Line 59)

### Change
```swift
// ❌ BEFORE - selections not passed
onSend: {
    chatVM.sendMessage(session: session, modelContext: modelContext)
}

// ✅ AFTER - selections passed through
onSend: {
    chatVM.sendMessage(
        session: session,
        modelContext: modelContext,
        selectedProvider: workbenchVM.selectedProvider,
        selectedModel: workbenchVM.selectedModel
    )
}
```

### Impact
- Model selection from picker is now passed to ChatViewModel
- Prevents falling back to session defaults

---

## Fix #2a: UIModels.swift

**File**: `UIModels.swift`

### Change
```swift
// ❌ BEFORE - only display name stored
struct UILLMModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let contextWindow: Int
}

// ✅ AFTER - actual API model ID stored
struct UILLMModel: Identifiable, Hashable {
    let id: UUID
    let modelID: String  // ← NEW: Actual API model ID
    let name: String     // Display name for UI
    let contextWindow: Int
}
```

### Impact
- UILLMModel now stores both display name (for UI) and API model ID (for API calls)
- Eliminates need for hardcoded display name → model ID mapping

---

## Fix #2b: NeonModelPicker.swift

**File**: `NeonModelPicker.swift` (Line ~119)

### Change
```swift
// ❌ BEFORE - model ID lost
let uiModels = models.map { model in
    UILLMModel(
        id: UUID(),
        name: model.displayName,
        contextWindow: model.contextWindow
    )
}

// ✅ AFTER - model ID preserved
let uiModels = models.map { model in
    UILLMModel(
        id: UUID(),
        modelID: model.id,           // ← Store actual API model ID
        name: model.displayName,     // Display name for UI
        contextWindow: model.contextWindow
    )
}
```

### Impact
- Actual model IDs from ModelRegistry are now passed through to UI layer
- Picker selections contain correct API model IDs

---

## Fix #2c: ChatViewModel.swift

**File**: `ChatViewModel.swift` (Line ~250-310)

### Change
```swift
// ❌ BEFORE - hardcoded display name mapping
let modelID: String
switch model.name {
case "GPT-4 Turbo":
    modelID = "gpt-4-turbo"
case "Claude 3.5 Sonnet":
    modelID = "claude-3-5-sonnet-20241022"
// ... 30+ lines of hardcoded mappings
default:
    modelID = model.name.lowercased().replacingOccurrences(of: " ", with: "-")
}

// ✅ AFTER - use actual model ID
let modelID = model.modelID
```

### Impact
- No more hardcoded model name mappings
- Automatically supports new models without code changes
- Prevents mismatches when display names don't match hardcoded cases

---

## Fix #3: ProviderRegistry.swift

**File**: `ProviderRegistry.swift`

### Change
```swift
// ❌ BEFORE - case-sensitive lookup
init(providerBuilders: [() -> any LLMProvider]) {
    let resolved = providerBuilders.map { $0() }
    self.providers = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
}

func provider(for id: String) throws -> any LLMProvider {
    guard let provider = providers[id] else {
        throw RegistryError.providerMissing
    }
    return provider
}

// ✅ AFTER - case-insensitive lookup
init(providerBuilders: [() -> any LLMProvider]) {
    let resolved = providerBuilders.map { $0() }
    // Normalize provider IDs to lowercase
    self.providers = Dictionary(
        uniqueKeysWithValues: resolved.map { ($0.id.lowercased(), $0) }
    )
}

func provider(for id: String) throws -> any LLMProvider {
    // Normalize lookup to lowercase
    let normalizedID = id.lowercased()
    guard let provider = providers[normalizedID] else {
        throw RegistryError.providerMissing
    }
    return provider
}
```

### Impact
- Prevents `RegistryError.providerMissing` from case mismatches
- "Anthropic" and "anthropic" both resolve to same provider
- More robust provider lookup

---

## Complete Flow (After Fixes)

```
1. User selects: Claude Opus 4.5 (Anthropic)
   ↓
2. NeonModelPicker stores:
   - selectedProvider: UILLMProvider(name: "Anthropic")
   - selectedModel: UILLMModel(
       id: UUID(),
       modelID: "claude-opus-4-20250514", ← Actual API model ID
       name: "Claude Opus 4.5"
     )
   ↓
3. User sends message
   ↓
4. NeonChatView calls:
   chatVM.sendMessage(
     session: session,
     modelContext: modelContext,
     selectedProvider: workbenchVM.selectedProvider, ← ✅ Passed
     selectedModel: workbenchVM.selectedModel        ← ✅ Passed
   )
   ↓
5. ChatViewModel.mapUISelectionToProviderModel():
   - providerID = "anthropic"
   - modelID = "claude-opus-4-20250514" ← ✅ Direct from modelID property
   ↓
6. ChatService.streamCompletion()
   ↓
7. ProviderRegistry.provider(for: "anthropic"):
   - Normalizes to lowercase: "anthropic"
   - Finds: AnthropicProvider
   - ✅ Returns provider
   ↓
8. AnthropicProvider.buildRequest():
   - Uses model: "claude-opus-4-20250514"
   - ✅ Builds correct request
   ↓
9. ✅ Message sent to Anthropic API with correct model
```

---

## Testing Checklist

Test these scenarios after building:

| Test Case | Expected Result | Should Now Work? |
|-----------|----------------|------------------|
| Select Claude Opus 4.5, send message | Uses Claude Opus 4.5 | ✅ Yes |
| Select GPT-4o, send message | Uses GPT-4o | ✅ Yes |
| Select Mistral Large 2, send message | Uses Mistral Large 2 | ✅ Yes |
| Ask model to identify itself | Returns correct model name | ✅ Yes |
| Session has old provider/model | Uses new selection | ✅ Yes |

---

## Files Modified

1. ✅ `NeonChatView.swift` - Pass selections to sendMessage()
2. ✅ `UIModels.swift` - Add modelID property to UILLMModel
3. ✅ `NeonModelPicker.swift` - Store actual model ID from registry
4. ✅ `ChatViewModel.swift` - Use modelID instead of display name mapping
5. ✅ `ProviderRegistry.swift` - Normalize provider IDs to lowercase

---

## Next Steps

1. **Build the project** - Verify no compilation errors
2. **Test model selection** - Try selecting different models
3. **Verify API calls** - Check logs to confirm correct model IDs are used
4. **Ask models to identify** - Send "What model are you?" to each provider
5. **Check error handling** - Verify no more `providerMissing` errors

---

## Expected Log Output

After fixes, you should see:

```
✅ UI Selection - Provider: Anthropic, Model: Claude Opus 4.5
✅ Mapped to - Provider ID: anthropic, Model ID: claude-opus-4-20250514
✅ Using provider: anthropic with model: claude-opus-4-20250514
```

Instead of:

```
❌ Using session defaults - Provider: Anthropic, Model: Claude 3.5 Sonnet
```

---

## Root Cause Summary

The bugs were caused by:
1. **Broken data flow** - Selections never left NeonChatView
2. **Data loss** - Model IDs discarded when creating UILLMModel
3. **Case sensitivity** - Provider lookups failed on case mismatches

The fixes:
1. **Complete the flow** - Pass selections through entire chain
2. **Preserve data** - Store model IDs alongside display names
3. **Normalize lookups** - Make provider IDs case-insensitive

---
