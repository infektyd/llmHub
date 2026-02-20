# llmHub Architecture

**Requirements:** macOS 26.2 SDK="25C57", Xcode 26.2 build="17C52", iOS 26.2 SDK="23C53" iPhone=17 pro, Swift 6.2

**Reality Map (authoritative current-state doc):** `Docs/REALITY_MAP.md`

> **Authoritative architectural reference for the llmHub project.**

---

## 🎯 Vision Statement

**llmHub** is a native macOS/iOS AI Workbench that bridges conversational chat with powerful agentic workflows. Core priorities:

1. **Frontier Model Integration**: All major providers (OpenAI, Anthropic, Gemini, Mistral, xAI, OpenRouter)
2. **Canvas/Flat UI**: Canvas-first SwiftUI interface with matte surfaces and minimal ornament
3. **Brain/Hand/Loop Architecture**: Strict separation of reasoning, execution, and orchestration
4. **Execution Safety**: Code execution backend exists but is currently disabled on macOS

---

## 🏗 System Architecture: "Brain/Hand/Loop"

```
┌─────────────────────────────────────────────────────────────┐
│                         USER INPUT                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    🧠 BRAIN (Providers)                     │
│  OpenAI · Anthropic · Gemini · Mistral · xAI · OpenRouter   │
│                                                             │
│  Protocol: LLMProvider                                      │
│  Output: AsyncThrowingStream<ProviderEvent, Error>          │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
            [Text Response]      [Tool Calls]
                    │                   │
                    │                   ▼
                    │   ┌─────────────────────────────────────┐
                    │   │           ✋ HAND (Tools)           │
                    │   │                                     │
                    │   │  Calculator · CodeInterpreter       │
                    │   │  FileReader · FileEditor · FilePatch│
                    │   │  Shell · ShellSession · Workspace   │
                    │   │  WebSearch · HTTPRequest · MCP      │
                    │   │                                     │
                    │   │  Protocol: Tool (Sendable)          │
                    │   │  Registry: ToolRegistry             │
                    │   └─────────────────────────────────────┘
                    │                   │
                    │                   ▼
                    │           [Tool Results]
                    │                   │
                    └─────────┬─────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    🔄 LOOP (Orchestrator)                   │
│                                                             │
│  Component: ChatService                                     │
│  Max Iterations: 10 tool calls per turn                     │
│  Persistence: SwiftData (ChatSessionEntity)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      FINAL RESPONSE                         │
└─────────────────────────────────────────────────────────────┘
```

### 1. The Brain (Providers)

| Aspect              | Details                                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| **Role**            | Intent processing and text generation                                                                     |
| **Protocol**        | `LLMProvider` (`@MainActor`)                                                                              |
| **Implementations** | `OpenAIManager`, `AnthropicManager`, `GeminiManager`, `MistralManager`, `XAIManager`, `OpenRouterManager` |
| **Pattern**         | Stateless API wrappers; state managed by `ChatService`                                                    |
| **Output**          | `AsyncThrowingStream<ProviderEvent, Error>`                                                               |

### 2. The Hand (Tools)

| Aspect         | Details                                                              |
| -------------- | -------------------------------------------------------------------- |
| **Role**       | Deterministic execution of capabilities                              |
| **Protocol**   | `Tool` (Sendable) — unified protocol for all tools                   |
| **Registry**   | `ToolRegistry` — manages tool registration and lookup                |
| **Categories** | Core (Calculator, FileReader), System (Shell, CodeExec), Network (Web/HTTP) |

**Registered Tools (current app wiring):**

| Tool                       | Platform | Purpose                                        |
| -------------------------- | -------- | ---------------------------------------------- |
| `CalculatorTool`           | All      | Mathematical evaluation                        |
| `CodeInterpreterTool`      | All      | Code execution (macOS backend disabled)        |
| `FileReaderTool`           | All      | File content reading                           |
| `FileEditorTool`           | All      | File creation/modification                     |
| `FilePatchTool`            | All      | Unified diff patching                          |
| `ShellTool`                | macOS    | Terminal command execution                     |
| `WebSearchTool`            | All      | Web search integration                         |
| `HTTPRequestTool`          | All      | HTTP API calls                                 |
| `WorkspaceTool`            | All      | Workspace item management                      |
| `DataVisualizationTool`    | All      | Chart/graph description output (text/JSON)     |
| `ArtifactListTool`         | All      | List artifacts available in the sandbox        |
| `ArtifactOpenTool`         | All      | Open/focus an artifact in the UI               |
| `ArtifactReadTextTool`     | All      | Read text content of an artifact               |
| `ArtifactDescribeImageTool`| All      | Image metadata + dimensions (vision stub)      |

> **Note**: `MCPToolBridge` exists but is not wired into the registry; tools under `Tools/Stubs/` are not registered. Availability is platform- and backend-aware.

### 3. The Loop (Orchestrator)

| Aspect             | Details                                                                  |
| ------------------ | ------------------------------------------------------------------------ |
| **Role**           | Coordinates recursive Brain↔Hand interaction                             |
| **Component**      | `ChatService`                                                            |
| **Flow**           | User Input → Brain → Tool Calls → Hand → Tool Results → Brain → Response |
| **Max Iterations** | 10 tool calls per turn                                                   |
| **Persistence**    | SwiftData entities with domain model conversion                          |

### 4. The Sandbox (Execution)

| Aspect        | Details                                                        |
| ------------- | -------------------------------------------------------------- |
| **Role**      | Securely execute user-generated code                           |
| **Component** | `llmHubHelper` (XPC Service) + `CodeExecutionEngine`           |
| **Protocol**  | `CodeExecutionXPCProtocol`                                     |
| **Platform**  | macOS (XPC helper), iOS (JavaScriptCore)                        |
| **Status**    | macOS backend disabled due to entitlements; iOS is JS-only     |

### 5. Memory Management

| Pattern              | Implementation                                                         |
| -------------------- | ---------------------------------------------------------------------- |
| **Weak Captures**    | Use `[weak self]` or `[weak viewModel]` in escaping closures           |
| **Callback Cleanup** | Nil closure properties in `onDisappear` (e.g., `onAddReference = nil`) |
| **Nested Tasks**     | Always use `[weak self]` in `Task { }` blocks inside view models       |
| **Debug Logging**    | Add `deinit { print("🗑️ ClassName deallocated") }` during debugging    |

---

## 🎨 Canvas/Flat UI

The UI is Canvas-first: flat/matte surfaces, dense information, and minimal ornament.

### Current UI Anchors

| Component               | Purpose                                      |
| ----------------------- | -------------------------------------------- |
| `CanvasRootView`        | Main app layout                              |
| `ModernSidebarLeft`     | Session list and navigation                  |
| `ModernSidebarRight`    | Inspector and tool toggles (basic)           |
| `TranscriptCanvasView`  | Transcript surface                           |
| `Composer`              | Input/composer bar                           |
| `TextualMessageView`    | Markdown rendering                            |

---

## 💾 Persistence & State

### SwiftData Entities

| Entity              | Purpose                                            |
| ------------------- | -------------------------------------------------- |
| `ChatSessionEntity` | Chat session with messages, folder, tags           |
| `ChatMessageEntity` | Individual messages with role, content, tool calls |
| `ChatFolderEntity`  | Folder organization                                |
| `ChatTagEntity`     | Tagging system                                     |

### Brain Swapping

Each session remembers its provider/model configuration:

```swift
// On model change
session.providerID = newProvider.id
session.model = newModel.id

// On session load
viewModel.hydrateState(from: session)
```

---

## 📂 Directory Structure

```
llmHub/
├── App/                    # @main entry point (llmHubApp.swift)
├── Views/                  # SwiftUI views (Canvas/flat UI)
│   ├── ContentView.swift   # Entry view
│   ├── Components/         # Reusable UI components
│   ├── Settings/           # Settings UI
│   └── UI/                 # Main app UI (RootView, Transcript, Composer, etc.)
├── ViewModels/             # UI logic, state, and UI data structures
│   ├── Core/               # ChatViewModel, ChatInteractionController
│   ├── Features/           # SidebarViewModel, WorkbenchViewModel, SettingsViewModel
│   ├── Managers/           # ModelFavoritesManager
│   └── Models/             # UI data structures (Artifact, UIModels, etc.)
├── Models/                 # Domain models (Chat, Code, Core, Memory, Tool)
├── Providers/              # LLM API wrappers (OpenAI, Anthropic, etc.)
├── Services/               # Business logic (ChatService, ToolRegistry, etc.)
│   ├── Chat/               # Chat orchestration
│   ├── ContextManagement/  # Token estimation & compaction
│   ├── ModelFetch/         # Model registry & fetching
│   └── Tools/              # Tool execution services
├── Tools/                  # Tool implementations
│   └── Stubs/              # Future tools (not wired in registry)
└── Utilities/              # Shared helpers (organized by purpose)
    ├── Extensions/         # Swift/SwiftUI extensions
    ├── Infrastructure/     # KeychainStore, AppLogger, SettingsManager
    ├── UI/                 # AppColors, UIAppearance, WindowAccessor
    ├── Formatting/         # Formatters and name helpers
    └── Helpers/            # Provider helpers, resolvers
```

---

## 🛠 Build Requirements

| Platform | Minimum Version                  |
| -------- | -------------------------------- |
| macOS    | 26.2+ SDK="25C57"                |
| iOS      | 26.2+ SDK="23C53". iPhone 17 Pro |
| Xcode    | 26.2+ build="17C52"              |
| Swift    | 6.2+                             |

### Dependencies

- **Textual** — Chat message rendering
- **Splash** — Syntax highlighting
- **SwiftCollections** — Efficient data structures

---

_Last Updated: December 2025_
