# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build via command line
xcodebuild -scheme llmHub -configuration Debug build | xcpretty

# Run tests
xcodebuild -scheme llmHub test | xcpretty

# Open in Xcode (alternative)
open llmHub.xcodeproj
# Then: Cmd+B (build) or Cmd+R (run)

# View logs during execution
log stream --predicate 'subsystem == "com.llmhub"'
```

**Requirements:** macOS 26.2 SDK="25C57", Xcode 26.2 build="17C52", iOS 26.2 SDK="23C53" iPhone=17 pro, Swift 6.2

**Reality Map (authoritative current-state doc):** `Docs/REALITY_MAP.md`

## Architecture: Brain/Hand/Loop

llmHub is a native macOS AI Workbench for LLMs with a modular architecture:

**Brain (Providers)** - LLM backends in `llmHub/Providers/`

- All conform to `@MainActor LLMProvider` protocol
- Implementations: OpenAI, Anthropic, Gemini, Mistral, xAI, OpenRouter
- Handle API communication, streaming via `AsyncThrowingStream<ProviderEvent, Error>`

**Hand (Tools)** - Deterministic tools in `llmHub/Tools/`

- Conform to `Tool` protocol with platform-aware availability
- **Registered Tools**: Calculator, CodeInterpreterTool (macOS backend disabled; iOS JS-only), FileEditorTool, FileReaderTool, FilePatchTool, WebSearchTool, HTTPRequestTool, ShellTool (macOS only), WorkspaceTool, DataVisualizationTool
- **Additional**: MCPToolBridge and tools under `Tools/Stubs/` exist but are not wired into the registry

**Loop (Orchestrator)** - `ChatService` in `llmHub/Services/Chat/ChatService.swift`

- Coordinates recursive Brain/Hand interaction
- Flow: User Input → Provider → Tool Calls → Tool Execution → Provider → Response
- Max 10 tool iterations per turn
- Integrated context management with token estimation and compaction

## Key Patterns

**Swift 6 Strict Concurrency**

- `@MainActor` on UI types, providers, and view models
- `actor` for isolated state (CodeExecutionEngine)
- All cross-actor parameters must be `Sendable`

**Code Execution Backend**

- XPC helper (`llmHubHelper`) exists but is disabled on macOS due to entitlements/sandbox issues
- iOS uses a JavaScriptCore backend (JavaScript only)
- Protocol: `CodeExecutionXPCProtocol` for macOS XPC path

**Canvas/Flat UI (SwiftUI)**

- Use Canvas-first, matte styling (`AppColors`, `UIAppearance`)
- Prefer existing Canvas components (`CanvasRootView`, `TranscriptCanvasView`, `ModernSidebar*`)
- Avoid legacy glass modifiers and tokens

**Persistence**

- SwiftData with `@Model` entities
- Domain models (`ChatSession`) ↔ Entities (`ChatSessionEntity`) via `.asDomain()`
- API keys stored in macOS Keychain via `KeychainStore`

## Key Files

| Purpose            | Location                                                           |
| ------------------ | ------------------------------------------------------------------ |
| Entry point        | `llmHub/App/llmHubApp.swift`                                       |
| Chat orchestration | `llmHub/Services/ChatService.swift`                                |
| Provider protocol  | `llmHub/Providers/Shared/LLMProviderProtocol.swift`                |
| Provider registry  | `llmHub/Services/Support/ProviderRegistry.swift`                   |
| Model caching      | `llmHub/Services/ModelFetch/ModelRegistry.swift`                   |
| Tool registry      | `llmHub/Services/Tools/Core/ToolRegistry.swift`                    |
| Context management | `llmHub/Services/ContextManagement/ContextManagementService.swift` |
| Token estimation   | `llmHub/Services/ContextManagement/TokenEstimator.swift`           |
| Context compaction | `llmHub/Services/ContextManagement/ContextCompactor.swift`         |
| Domain models      | `llmHub/Models/Chat/ChatModels.swift`                              |
| Shared types       | `llmHub/Models/Core/SharedTypes.swift`                             |
| API key storage    | `llmHub/Utilities/Infrastructure/KeychainStore.swift`              |
| XPC service        | `llmHubHelper/main.swift`                                          |
| **Documentation**  | `Docs/README.md`                                                   |

## Documentation

| Folder               | Contents                             |
| -------------------- | ------------------------------------ |
| `Docs/`              | Start at `README.md` for navigation  |
| `Docs/Architecture/` | Codebase analysis, design principles |
| `Docs/Providers/`    | LLM provider integration guides      |
| `Docs/Changelogs/`   | Monthly change logs                  |
| `Docs/Legacy/`       | Archived DevLogs and build logs      |

## Adding New Components

**New Provider:**

1. Create `NewProviderManager.swift` in `Providers/`
2. Conform to `@MainActor LLMProvider`
3. Add API key to `KeychainStore.ProviderKey`
4. Register in `ProviderRegistry`

**New Tool:**

1. Create `NewTool.swift` in `Tools/`
2. Conform to `Tool` protocol with `inputSchema` (JSON Schema)
3. Register in `ToolRegistry.defaultRegistry()`

**New UI Component:**

1. Create in `Views/Components/` or `Views/UI/`
2. Follow Canvas/flat styling conventions
3. Use `@Observable` for view models

## Agent Tier Guidelines

From `Docs/AGENTS.md`:

- **Haiku:** Quick tasks, follow patterns exactly, single-file changes, syntax help
- **Sonnet:** New features, UI components, provider integrations, multi-file changes. Canvas/flat UI mandatory.
- **Opus:** Architecture design, complex concurrency bugs, 5+ file refactors, subsystem design

Escalate to Opus if uncertain about architecture or existing patterns seem wrong.

## Current Status (January 2026)

- ✅ **Brain/Hand/Loop** implemented with all 6 providers
- ✅ **Tool system** wired with 10 registered tools (see Reality Map)
- ✅ **Context management** integrated into `ChatService`
- ✅ **Canvas/flat UI** is the current design direction
- ⚠️ **macOS code execution** disabled pending XPC entitlements fix
- ✅ **Swift 6.2**, streaming, and SwiftData persistence in place

## Notes

- Each `ChatSession` is bound to one provider/model (no mid-conversation switching)
- Model cache has 1-hour expiration; force refresh via `ModelRegistry.fetchAllModels(forceRefresh: true)`
- Code execution timeout configurable in `CodeExecutionEngine`
- XPC helper must build successfully and embed in main app bundle (macOS only)
- Context compaction uses `.truncateOldest` strategy with emergency fallback
- Tools self-report availability based on platform (iOS vs macOS) and sandbox status
- **Memory**: Use `[weak self]` in closures, nil callbacks in `onDisappear`, add deinit logging during debugging
