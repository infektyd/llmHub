# Critical Bugs Analysis - Model Selection & Provider Registration

**Date**: December 7, 2025  
**Status**: 🔴 THREE CRITICAL BUGS IDENTIFIED

---

## 🔴 Problem Summary

1. **Provider registration IS applied** but model selection isn't being passed through
2. **Model selection flow is broken** - NeonModelPicker selections don't reach API calls
3. **Wrong model is being used** - "ChatGPT 3.5" being used instead of selected model

---

## 🐛 Bug #1: Model Selection Not Passed Through

### **Root Cause**

In `NeonChatView.swift` line 59, the `sendMessage` call **DOES NOT** pass the selected provider/model:

```swift
// ❌ CURRENT CODE
onSend: {
    chatVM.sendMessage(session: session, modelContext: modelContext)
}
```

The `WorkbenchViewModel` has the selection state (`selectedProvider` and `selectedModel`), but it's never passed to `ChatViewModel.sendMessage()`.

### **Evidence**

From your log:
```
"Using session defaults - Provider: Anthropic, Model: Claude 3.5 Sonnet"
```

This message comes from line 307 in `ChatViewModel.swift`:
```swift
// Fallback: use session's existing provider/model or default to OpenAI GPT-4o
let providerID = sessionEntity.providerID.isEmpty ? "openai" : sessionEntity.providerID
let modelID = sessionEntity.model.isEmpty ? "gpt-4o" : sessionEntity.model

logger.info("Using session defaults - Provider: \(providerID), Model: \(modelID)")
```

The function reached the **fallback** because `selectedProvider` and `selectedModel` were both `nil`.

---

## 🐛 Bug #2: Wrong Model Name in Picker

### **Root Cause**

`NeonModelPicker.swift` is creating `UILLMModel` objects with **display names only**, losing the actual model ID:

```swift
// ❌ Line 119 - Only stores display name
let uiModels = models.map { model in
    UILLMModel(
        id: UUID(), // ← Generates random UUID, loses model ID!
        name: model.displayName, // ← Only display name, not API model ID
        contextWindow: model.contextWindow
    )
}
```

The actual model ID (e.g., `"claude-opus-4-20250514"`) from `ModelRegistry` is **thrown away**.

### **Result**

When `ChatViewModel.mapUISelectionToProviderModel()` receives the selection:
1. It gets `UILLMModel.name = "Claude Opus 4.5"` (display name)
2. It tries to map it using hardcoded cases (line 268-295)
3. **"Claude Opus 4.5" is NOT in the mapping** (only "Claude 3.5 Sonnet", "Claude 3 Opus", "Claude 3 Haiku")
4. Falls through to default case (line 297-299):
   ```swift
   default:
       // Fallback: use the name as-is and hope it matches
       modelID = model.name.lowercased().replacingOccurrences(of: " ", with: "-")
   ```
5. Results in `modelID = "claude-opus-4.5"` which is **NOT a valid Anthropic API model ID**

---

## 🐛 Bug #3: ProviderMissing Error (The Original Issue)

### **Root Cause**

The provider registration **IS applied** (lines 53-58 in ChatViewModel), but there's likely a **case-sensitivity issue**.

### **Provider IDs in Registry**

Looking at line 53-58 of `ChatViewModel.swift`:
```swift
let registry = ProviderRegistry(providerBuilders: [
    { OpenAIProvider(keychain: keychain, config: config.openAI) },
    { AnthropicProvider(keychain: keychain, config: config.anthropic) },
    { MistralProvider(keychain: keychain, config: config.mistral) }
])
```

The providers are registered with their `id` property. **We need to verify what those IDs are.**

### **Provider ID Lookup**

In line 109-113, the code maps UI selection to provider ID:
```swift
let (providerID, modelID) = mapUISelectionToProviderModel(
    selectedProvider: selectedProvider, // ← This is nil!
    selectedModel: selectedModel,       // ← This is nil!
    sessionEntity: session
)
```

Then in the fallback (line 306):
```swift
let providerID = sessionEntity.providerID.isEmpty ? "openai" : sessionEntity.providerID
```

**Question**: What is `sessionEntity.providerID` set to? If it's "Anthropic" (capital A) but the provider registered as "anthropic" (lowercase), we get `providerMissing`.

---

## 🔍 The Complete Flow (Current Broken State)

### **Step 1: User Opens Picker**
```
WorkbenchViewModel.selectedProvider = nil
WorkbenchViewModel.selectedModel = nil
```

### **Step 2: User Selects Claude Opus 4.5**
```
NeonModelPicker reads ModelRegistry
├─ ModelRegistry has: LLMModel(
│     id: "claude-opus-4-20250514",
│     displayName: "Claude Opus 4.5",
│     ...
│  )
└─ Creates: UILLMModel(
      id: UUID(), ← Random, not the real model ID
      name: "Claude Opus 4.5", ← Display name only
      contextWindow: ...
   )

WorkbenchViewModel.selectedProvider = UILLMProvider(name: "Anthropic", ...)
WorkbenchViewModel.selectedModel = UILLMModel(name: "Claude Opus 4.5", ...)
```

### **Step 3: User Sends Message**
```swift
// NeonChatView.swift line 59
onSend: {
    chatVM.sendMessage(session: session, modelContext: modelContext)
    //                 ❌ selectedProvider and selectedModel NOT passed!
}
```

### **Step 4: ChatViewModel.sendMessage()**
```swift
func sendMessage(
    session: ChatSessionEntity,
    modelContext: ModelContext,
    selectedProvider: UILLMProvider? = nil, // ← Defaults to nil
    selectedModel: UILLMModel? = nil        // ← Defaults to nil
)

// Line 109
let (providerID, modelID) = mapUISelectionToProviderModel(
    selectedProvider: nil, // ❌ No UI selection passed
    selectedModel: nil,    // ❌ No UI selection passed
    sessionEntity: session
)
```

### **Step 5: mapUISelectionToProviderModel()**
```swift
if let provider = selectedProvider, let model = selectedModel {
    // ❌ SKIPPED - both are nil
}

// Falls through to line 306
let providerID = sessionEntity.providerID.isEmpty ? "openai" : sessionEntity.providerID
let modelID = sessionEntity.model.isEmpty ? "gpt-4o" : sessionEntity.model

logger.info("Using session defaults - Provider: \(providerID), Model: \(modelID)")
// ← This is where your log message comes from!
```

### **Step 6: ChatService.streamCompletion()**
```swift
// Line 152
let stream = try await service.streamCompletion(
    for: updatedSession, // Has providerID from session entity
    userMessage: userMessageText
)
```

### **Step 7: ChatService Looks Up Provider**
```swift
let provider = try providerRegistry.provider(for: providerID)
// If providerID = "Anthropic" (capital) but registry has "anthropic" (lowercase)
// ❌ Throws RegistryError.providerMissing
```

---

## ✅ The Fixes

### **Fix #1: Pass Model Selection to sendMessage()**

**File**: `NeonChatView.swift`  
**Line**: 59

```swift
// ❌ BEFORE
onSend: {
    chatVM.sendMessage(session: session, modelContext: modelContext)
}

// ✅ AFTER
onSend: {
    chatVM.sendMessage(
        session: session,
        modelContext: modelContext,
        selectedProvider: workbenchVM.selectedProvider,
        selectedModel: workbenchVM.selectedModel
    )
}
```

---

### **Fix #2: Store Actual Model ID in UILLMModel**

**Option A: Add modelID Property to UILLMModel**

**File**: `UILLMProvider.swift` (or wherever `UILLMModel` is defined)

```swift
struct UILLMModel: Identifiable, Codable {
    let id: UUID
    let modelID: String      // ✅ ADD THIS - Actual API model ID
    let name: String         // Display name for UI
    let contextWindow: Int
}
```

**File**: `NeonModelPicker.swift` (line 119)

```swift
// ✅ AFTER
let uiModels = models.map { model in
    UILLMModel(
        id: UUID(),
        modelID: model.id,           // ✅ Store actual model ID
        name: model.displayName,     // Display name for UI
        contextWindow: model.contextWindow
    )
}
```

**File**: `ChatViewModel.swift` (line 252-302)

```swift
// ✅ AFTER - Use actual model ID instead of mapping
private func mapUISelectionToProviderModel(
    selectedProvider: UILLMProvider?,
    selectedModel: UILLMModel?,
    sessionEntity: ChatSessionEntity
) -> (providerID: String, modelID: String) {
    
    // If we have UI selections, use them directly
    if let provider = selectedProvider, let model = selectedModel {
        logger.info("UI Selection - Provider: \(provider.name), Model: \(model.name)")
        
        // Map provider names to IDs
        let providerID: String
        switch provider.name.lowercased() {
        case "openai":
            providerID = "openai"
        case "anthropic":
            providerID = "anthropic"
        case "google":
            providerID = "google"
        case "mistral":
            providerID = "mistral"
        case "xai":
            providerID = "xai"
        case "openrouter":
            providerID = "openrouter"
        default:
            providerID = provider.name.lowercased()
        }
        
        // ✅ Use actual model ID instead of display name mapping
        let modelID = model.modelID
        
        return (providerID, modelID)
    }
    
    // Fallback: use session's existing provider/model or default to OpenAI GPT-4o
    let providerID = sessionEntity.providerID.isEmpty ? "openai" : sessionEntity.providerID
    let modelID = sessionEntity.model.isEmpty ? "gpt-4o" : sessionEntity.model
    
    logger.info("Using session defaults - Provider: \(providerID), Model: \(modelID)")
    return (providerID, modelID)
}
```

---

### **Fix #3: Ensure Provider ID Consistency**

**Need to verify**: What are the actual provider IDs?

We need to check:
1. What does `OpenAIProvider.id` return?
2. What does `AnthropicProvider.id` return?
3. What does `MistralProvider.id` return?

**Likely Issue**: Provider IDs might be capitalized (e.g., "Anthropic") but we're looking up with lowercase ("anthropic").

**Temporary Fix**: Normalize provider ID lookups to lowercase in `ProviderRegistry`:

```swift
// ProviderRegistry.swift
func provider(for id: String) throws -> any LLMProvider {
    let normalizedID = id.lowercased()
    guard let provider = providers[normalizedID] else {
        throw RegistryError.providerMissing
    }
    return provider
}

init(providerBuilders: [() -> any LLMProvider]) {
    let resolved = providerBuilders.map { $0() }
    // ✅ Normalize keys to lowercase
    self.providers = Dictionary(
        uniqueKeysWithValues: resolved.map { ($0.id.lowercased(), $0) }
    )
}
```

---

## 📊 Architecture Diagram (Fixed Flow)

```
User selects: Claude Opus 4.5 (Anthropic)
    ↓
WorkbenchViewModel stores:
  - selectedProvider: UILLMProvider(name: "Anthropic")
  - selectedModel: UILLMModel(
      id: UUID(),
      modelID: "claude-opus-4-20250514", ← Real model ID
      name: "Claude Opus 4.5"
    )
    ↓
User sends message
    ↓
NeonChatView calls:
  chatVM.sendMessage(
    session: session,
    modelContext: modelContext,
    selectedProvider: workbenchVM.selectedProvider, ← Now passed!
    selectedModel: workbenchVM.selectedModel        ← Now passed!
  )
    ↓
ChatViewModel.mapUISelectionToProviderModel():
  - providerID = "anthropic"
  - modelID = "claude-opus-4-20250514" ← Actual API model ID
    ↓
ChatService.streamCompletion():
  - Looks up provider: "anthropic"
    ↓
ProviderRegistry.provider(for: "anthropic"):
  - Normalizes to lowercase: "anthropic"
  - Finds: AnthropicProvider
  - ✅ Returns provider
    ↓
AnthropicProvider.buildRequest():
  - Uses model: "claude-opus-4-20250514"
  - Reads API key from Keychain
  - ✅ Builds correct request
    ↓
✅ Message sent to Anthropic API with correct model
```

---

## 🧪 Testing Checklist

| Test Case | Expected Result | Current Status |
|-----------|----------------|----------------|
| Select Claude Opus 4.5, send message | Uses Claude Opus 4.5 | ❌ Uses session default |
| Select GPT-4o, send message | Uses GPT-4o | ❌ Uses session default |
| Session has old provider/model | Uses new selection | ❌ Uses session default |
| Ask model to identify itself | Returns correct model name | ❌ Returns "ChatGPT 3.5" |

---

## 🎯 Summary

### **Three Bugs, Three Fixes**

1. **Bug**: Model selection not passed to sendMessage()  
   **Fix**: Pass `workbenchVM.selectedProvider` and `workbenchVM.selectedModel` in NeonChatView

2. **Bug**: UILLMModel loses actual model ID  
   **Fix**: Add `modelID` property to UILLMModel, use it instead of display name mapping

3. **Bug**: Provider ID case sensitivity  
   **Fix**: Normalize provider IDs to lowercase in ProviderRegistry

### **Impact**

After these fixes:
- ✅ Model selection will actually be used
- ✅ Correct model ID will be sent to API
- ✅ Model will correctly identify itself
- ✅ Provider lookup will always succeed (if registered)

### **Files to Modify**

1. `NeonChatView.swift` - Pass selections to sendMessage()
2. `UILLMProvider.swift` - Add modelID to UILLMModel
3. `NeonModelPicker.swift` - Store actual model ID
4. `ChatViewModel.swift` - Use modelID instead of name mapping
5. `ProviderRegistry.swift` - Normalize provider IDs to lowercase

---

## 🔍 Next Steps

1. **Verify provider IDs** - Check what OpenAIProvider.id, AnthropicProvider.id, etc. return
2. **Find UILLMModel definition** - Locate the struct to add modelID property
3. **Apply fixes in order** - Fix #1 first (easiest), then #2, then #3
4. **Test with each provider** - Verify OpenAI, Anthropic, Mistral all work
5. **Test model identity** - Ask each model to identify itself

---
