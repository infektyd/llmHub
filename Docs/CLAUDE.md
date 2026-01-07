# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build via command line
xcodebuild -scheme llmHub -configuration Debug build

# Run tests
xcodebuild -scheme llmHub test

# Open in Xcode (alternative)
open llmHub.xcodeproj
# Then: Cmd+B (build) or Cmd+R (run)

# View logs during execution
log stream --predicate 'subsystem == "com.llmhub"'
```

**Requirements:** macOS 26.2 SDK="25C57", Xcode 26.2 build="17C52", iOS 26.2 SDK="23C53" iPhone=17 pro, Swift 6.2

## Architecture: Brain/Hand/Loop

llmHub is a native macOS AI Workbench for LLMs with a modular architecture:

**Brain (Providers)** - LLM backends in `llmHub/Providers/`

- All conform to `@MainActor LLMProvider` protocol
- Implementations: OpenAI, Anthropic, Gemini, Mistral, xAI, OpenRouter
- Handle API communication, streaming via `AsyncThrowingStream<ProviderEvent, Error>`

**Hand (Tools)** - Deterministic tools in `llmHub/llmHub/Tools/`

- Conform to `Tool` protocol with platform-aware availability
- **Core Tools**: Calculator, CodeInterpreterTool (Swift/Python/JS via XPC), FileEditorTool, FileReaderTool, WebSearchTool
- **Extended Tools**: Shell, HTTPRequest, ImageGeneration, DataVisualization, FilePatch, Workspace, ShellSession, MCPToolBridge
- **17+ tools total** with unified registration via `ToolRegistry`
- **Legacy**: Original tools use `LegacyTool` protocol (renamed from `Tool` during architecture unification)

**Loop (Orchestrator)** - `ChatService` in `llmHub/Services/ChatService.swift`

- Coordinates recursive Brain/Hand interaction
- Flow: User Input → Provider → Tool Calls → Tool Execution → Provider → Response
- Max 10 tool iterations per turn
- Integrated context management with token estimation and compaction

## Key Patterns

**Swift 6 Strict Concurrency**

- `@MainActor` on UI types, providers, and view models
- `actor` for isolated state (CodeExecutionEngine)
- All cross-actor parameters must be `Sendable`

**XPC Sandboxed Execution**

- Code runs in separate `llmHubHelper` XPC service
- Main app sandboxed; XPC helper unsandboxed for execution
- Protocol: `CodeExecutionXPCProtocol`

**Liquid Glass UI (SwiftUI)**

- Use `.glassEffect()` on views. Reference `LiquidGlassTokens` for spacing and radii. Do not use legacy wrapper views.
- `.buttonStyle(.glass)` for buttons
- `.interactive()` for touch-responsive elements
- Avoid legacy `.ultraThinMaterial`

**Persistence**

- SwiftData with `@Model` entities
- Domain models (`ChatSession`) ↔ Entities (`ChatSessionEntity`) via `.asDomain()`
- API keys stored in macOS Keychain via `KeychainStore`

## Key Files

| Purpose            | Location                                                           |
| ------------------ | ------------------------------------------------------------------ |
| Entry point        | `llmHub/App/llmHubApp.swift`                                       |
| Chat orchestration | `llmHub/Services/ChatService.swift`                                |
| Provider protocol  | `llmHub/Providers/LLMProviderProtocol.swift`                       |
| Provider registry  | `llmHub/Services/Providers/ProviderRegistry.swift`                 |
| Model caching      | `llmHub/Services/ModelFetch/ModelRegistry.swift`                   |
| Tool registry      | `llmHub/Services/ToolRegistry.swift`                               |
| Context management | `llmHub/Services/ContextManagement/ContextManagementService.swift` |
| Token estimation   | `llmHub/Services/ContextManagement/TokenEstimator.swift`           |
| Context compaction | `llmHub/Services/ContextManagement/ContextCompactor.swift`         |
| Domain models      | `llmHub/Models/ChatModels.swift`                                   |
| Shared types       | `llmHub/Models/SharedTypes.swift`                                  |
| API key storage    | `llmHub/Support/KeychainStore.swift`                               |
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

1. Create in `Views/Components/` or `Views/Glass/`
2. Use Liquid Glass (`glassEffect()`)
3. Use `@Observable` for view models

## Agent Tier Guidelines

From `Docs/AGENTS.md`:

- **Haiku:** Quick tasks, follow patterns exactly, single-file changes, syntax help
- **Sonnet:** New features, UI components, provider integrations, multi-file changes. Liquid Glass mandatory for UI.
- **Opus:** Architecture design, complex concurrency bugs, 5+ file refactors, subsystem design

Escalate to Opus if uncertain about architecture or existing patterns seem wrong.

## Current Status (December 2025)

- ✅ **Fully Functional**: Complete Brain/Hand/Loop implementation with all 6 providers
- ✅ **17+ Tools**: Unified tool system with platform-aware availability
- ✅ **Context Management**: Token estimation and compaction integrated into ChatService
- ✅ **Liquid Glass UI**: Modern glass-morphism interface throughout
- ✅ **Swift 6.2**: Strict concurrency compliance with `@MainActor` and `Sendable`
- ✅ **Streaming**: Full async streaming support via `AsyncThrowingStream`
- ✅ **Persistence**: SwiftData with bidirectional domain/entity conversion

## Notes

- Each `ChatSession` is bound to one provider/model (no mid-conversation switching)
- Model cache has 1-hour expiration; force refresh via `ModelRegistry.fetchAllModels(forceRefresh: true)`
- Code execution timeout configurable in `CodeExecutionEngine`
- XPC helper must build successfully and embed in main app bundle (macOS only)
- Context compaction uses `.truncateOldest` strategy with emergency fallback
- Tools self-report availability based on platform (iOS vs macOS) and sandbox status
- **Memory**: Use `[weak self]` in closures, nil callbacks in `onDisappear`, add deinit logging during debugging
