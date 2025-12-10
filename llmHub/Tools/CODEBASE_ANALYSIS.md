# llmHub Codebase Analysis

> **Generated:** December 7, 2025  
> **Status:** Project does not compile — blocked by Swift 6.2 concurrency errors

---

## 1. Architecture Overview

### Entry Point
- `llmHubApp.swift` — Standard SwiftUI `@main` entry
- Primary window: `NeonWorkbenchWindow.swift`

### Core Data Flow
```
User Input → NeonChatInput → ChatViewModel.sendMessage()
                                    ↓
                         ChatSessionEntity (SwiftData)
                                    ↓
                              [STUB] — No actual LLM call
                                    ↓
                         Simulated response appended
```

**Critical finding:** `ChatViewModel.sendMessage()` does NOT call any LLM provider. It appends a hardcoded simulated response.

**Quote** (`ChatViewModel.swift:44-52`):
```swift
// Simulate AI response
Task {
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    await MainActor.run {
        let responseMessage = ChatMessage(
            ...
            content: "This is a simulated response for: \"\(newMessage.content)\"",
            ...
        )
    }
}
```

### Key Dependencies/Frameworks
| Framework | Usage |
|-----------|-------|
| SwiftUI | All UI |
| SwiftData | Persistence (`ChatSessionEntity`, `ChatMessageEntity`, etc.) |
| Foundation/URLSession | Networking (providers) |
| XPC Services | Code execution sandbox |
| OSLog | Logging |

**No third-party dependencies** — all native Apple frameworks.

---

## 2. What's Working

### Implemented & Functional

- **SwiftData persistence layer**
  - `ChatModels.swift` — Full domain models + `@Model` entities
  - Bidirectional conversion: `ChatSession ↔ ChatSessionEntity`
  - Folder/tag organization system

- **XPC code execution architecture**
  - `CodeExecutionXPCProtocol.swift` — Protocol defined
  - `XPCExecutionBackend.swift` — Client implementation complete
  - `CodeExecutionEngine.swift` — Actor-based engine with sandbox support
  - `CodeInterpreterTool.swift` — Full `Tool` protocol conformance
  - Supports: Swift, Python, JavaScript, TypeScript, Dart

- **UI shell structure**
  - `NeonWorkbenchWindow.swift` — Three-pane layout (sidebar, chat, inspector)
  - `NeonChatView.swift` — Message display with scroll tracking
  - `NeonSidebar.swift` — Conversation history
  - `NeonToolInspector.swift` — Tool execution display

- **Provider configuration** (`ProvidersConfig.swift`)
  - Model definitions for: OpenAI, Anthropic, Google AI, Mistral, xAI, OpenRouter
  - Context windows and token limits specified

### Which Models Are Integrated?

**Configured but not callable:**
- OpenAI: GPT-4o, GPT-4o Mini, o1-preview, o1-mini, GPT-4 Turbo, GPT-4, GPT-3.5 Turbo
- Anthropic: Claude Opus 4.5, Sonnet 4.5, Haiku 4.5, Claude 4, Claude 3.5, Claude 3
- Google: Gemini 1.5 Flash/Pro, Gemini 1.0 Pro/Ultra
- Mistral: Large, Pixtral, Small, Codestral, 7B, Mixtral 8x7B
- xAI: Grok 4.1, Grok 4, Grok 3 Mini, Grok 2 Vision/Image
- OpenRouter: GPT-4o, Claude 3.5 Sonnet (aggregator)

**Reason not callable:** Provider files exist (`*Provider.swift`, `*Manager.swift`) but fail to compile.

### Storage/Persistence

- **SwiftData** with `ModelContext`
- Entities: `ChatSessionEntity`, `ChatMessageEntity`, `ChatFolderEntity`, `ChatTagEntity`
- Includes tool calling support: `toolCallID`, `toolCallsData` fields

---

## 3. What's Incomplete

### Build Errors (Blocking)

**7 Swift 6 concurrency errors** in provider files (`Build llmHub_2025-12-01T17-34-19.txt`):

| File | Error |
|------|-------|
| `AnthropicProvider.swift:4` | Conformance crosses into main actor-isolated code |
| `GoogleAIProvider.swift:3` | Same |
| `MistralProvider.swift:3` | Same |
| `OpenAIProvider.swift:3` | Same |
| `OpenRouterProvider.swift:3` | Same |
| `XAIProvider.swift:4` | Same |
| `MCPToolBridge.swift:234` | Sending 'input' risks data races |
| `CodeExecutionModels.swift:204` | Main actor-isolated property access from nonisolated context |

**Fix required:** Add `@MainActor` to provider struct declarations or mark `LLMProvider` protocol as `@MainActor`.

### Stubs & Placeholders

- **`ChatViewModel.sendMessage()`** — Simulated response only, no LLM integration
- **`ChatViewModel.triggerTool()`** — `DispatchQueue.main.asyncAfter` simulation, no real tool execution
- **`CodeExecutionEngine.startREPL()`** — Throws "REPL not yet implemented" (`CodeExecutionEngine.swift:167`)

### TODOs & FIXMEs

None found via code search. Documentation mentions planned features in `AGENTS.md`:

- Multi-window support with glass coordination
- Widget for quick prompts
- visionOS port
- Apple Intelligence integration
- On-device model support (MLX)

### Commented-Out / Planned Features

From `LIQUID_GLASS_MIGRATION.md`:
- Liquid Glass migration incomplete — 8 files need updating
- Legacy `.ultraThinMaterial` still in use

From `AGENTS.md` roadmap:
```
Near-term:
- [ ] Complete Liquid Glass migration
- [ ] Multi-window support
- [ ] Widget for quick prompts

Medium-term:
- [ ] visionOS port
- [ ] Apple Intelligence integration
- [ ] On-device model support (MLX)
```

---

## 4. What's Missing

### UI Connected But No Backend

| UI Component | Backend Status |
|--------------|----------------|
| `NeonChatInput` | ❌ No provider call |
| `NeonModelPicker` | ❌ Model selection has no effect |
| `NeonToolInspector` | ⚠️ Shows simulated execution only |
| Sidebar conversations | ✅ SwiftData persistence works |

### Backend Exists But No UI

| Backend Component | UI Status |
|-------------------|-----------|
| `MCPClient.swift` | ❌ No configuration UI |
| `KeychainStore.swift` | ❌ No API key settings screen |
| `CostCalculator.swift` | ❌ Cost display not wired up |
| `WebSearchTool.swift` | ❌ Not in tool picker |
| `FileEditorTool.swift` / `FileReaderTool.swift` | ❌ Not in tool picker |

### Critical Gaps

1. **No ChatService orchestration** — `ChatService.swift` exists per architecture doc but `ChatViewModel` doesn't use it
2. **No streaming support in UI** — Providers support `AsyncThrowingStream` but chat view doesn't consume streams
3. **API key management** — `KeychainStore` exists but no settings UI to enter keys
4. **Tool registration** — `ToolRegistry` mentioned but tools aren't registered anywhere visible

---

## 5. Quick Wins

### Immediate (Fix Build)

1. **Add `@MainActor` to provider structs** — All 6 provider files need this one-line fix:
   ```swift
   @MainActor
   struct OpenAIProvider: LLMProvider { ... }
   ```

2. **Fix `CodeExecutionModels.swift:204`** — Mark `displayName`/`interpreterName` as `nonisolated` or make error description main actor isolated

3. **Fix `MCPToolBridge.swift:234`** — Copy `input` to a sendable type before crossing actor boundary:
   ```swift
   let sendableInput = Dictionary(uniqueKeysWithValues: input.map { ($0.key, $0.value) })
   ```

### Low-Effort Improvements

4. **Wire up model selection** — `NeonModelPicker` already captures selection; pass to actual provider call

5. **Connect ChatService** — Replace simulated response in `ChatViewModel` with `ChatService.sendMessage()` call

6. **Add sample tools to picker** — `UIToolDefinition.sampleTools` is hardcoded; replace with `ToolRegistry.defaultRegistry().tools`

7. **Display token usage** — `TokenUsage` exists on messages; add to `NeonMessageBubble` footer

8. **Show cost breakdown** — `CostBreakdown` is on messages; display in session metadata

---

## File Reference

| Category | Files |
|----------|-------|
| **Models** | `ChatModels.swift`, `CodeExecutionModels.swift`, `FileOperationModels.swift`, `UIModels.swift` |
| **Providers** | `LLMProviderProtocol.swift`, `OpenAIManager.swift`, `AnthropicManager.swift`, `GeminiManager.swift`, `MistralManager.swift`, `XAIManager.swift`, `OpenRouterManager.swift`, `*Provider.swift` (6 files) |
| **Services** | `ChatService.swift`, `ToolRegistry.swift`, `ProviderRegistry.swift`, `CodeExecutionEngine.swift`, `MCPClient.swift`, `MCPTypes.swift`, `SandboxManager.swift` |
| **Tools** | `CodeInterpreterTool.swift`, `FileEditorTool.swift`, `FileReaderTool.swift`, `WebSearchTool.swift`, `MCPToolBridge.swift` |
| **XPC** | `CodeExecutionXPCProtocol.swift`, `XPCExecutionBackend.swift`, `ExecutionBackend.swift` |
| **Views** | `NeonWorkbenchWindow.swift`, `NeonChatView.swift`, `NeonChatInput.swift`, `NeonToolbar.swift`, `NeonMessageBubble.swift`, `NeonSidebar.swift`, `NeonToolInspector.swift`, `NeonWelcomeView.swift`, `NeonModelPicker.swift` |
| **ViewModels** | `ChatViewModel.swift`, `WorkbenchViewModel.swift` |
| **Support** | `ProvidersConfig.swift`, `KeychainStore.swift`, `ReferenceFormatter.swift`, `NeonTheme.swift` |

---

## Summary

**llmHub is ~60% scaffolded, 0% functional for LLM chat.**

- ✅ Architecture is sound (Brain/Hand/Loop pattern documented)
- ✅ Persistence layer complete
- ✅ XPC code execution backend complete
- ✅ UI shell exists
- ❌ Build is broken (7 Swift 6 concurrency errors)
- ❌ Chat flow is stubbed (simulated responses only)
- ❌ No API key management UI
- ❌ Tools not wired to UI

**Priority 1:** Fix Swift 6 concurrency errors to unblock build  
**Priority 2:** Connect `ChatViewModel` → `ChatService` → `LLMProvider`  
**Priority 3:** Add API key settings screen
