# llmHub Architecture

**Requirements:** macOS 26.2 SDK="25C57", Xcode 26.2 build="17C52", iOS 26.2 SDK="23C53" iPhone=17 pro, Swift 6.2

> **Authoritative architectural reference for the llmHub project.**

---

## 🎯 Vision Statement

**llmHub** is a native macOS/iOS AI Workbench that bridges conversational chat with powerful agentic workflows. Core priorities:

1. **Frontier Model Integration**: All major providers (OpenAI, Anthropic, Gemini, Mistral, xAI, OpenRouter)
2. **Liquid Glass UI**: Translucent SwiftUI interface using native `GlassEffect` APIs
3. **Brain/Hand/Loop Architecture**: Strict separation of reasoning, execution, and orchestration
4. **Secure Execution**: Sandboxed code execution on macOS via XPC

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
| **Categories** | Core (Calculator, FileReader), System (Shell, CodeExec), Cloud (MCP) |

**Active Tools (17+):**

| Tool                    | Platform | Purpose                            |
| ----------------------- | -------- | ---------------------------------- |
| `CalculatorTool`        | All      | Mathematical evaluation            |
| `CodeInterpreterTool`   | macOS    | Swift/Python/JS execution via XPC  |
| `FileReaderTool`        | All      | File content reading               |
| `FileEditorTool`        | All      | File creation/modification         |
| `FilePatchTool`         | All      | Unified diff patching              |
| `ShellTool`             | macOS    | Terminal command execution         |
| `ShellSession`          | macOS    | Persistent shell sessions          |
| `WebSearchTool`         | All      | Web search integration             |
| `HTTPRequestTool`       | All      | HTTP API calls                     |
| `WorkspaceTool`         | All      | Workspace item management          |
| `MCPToolBridge`         | All      | Model Context Protocol integration |
| `DataVisualizationTool` | All      | Chart/graph generation             |
| `ImageGenerationTool`   | All      | AI image generation                |

> **Note**: Some tools report availability based on platform and sandbox status.

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
| **Component** | `llmHubHelper` (XPC Service)                                   |
| **Protocol**  | `CodeExecutionXPCProtocol`                                     |
| **Platform**  | macOS only                                                     |
| **Mechanism** | Main App → XPC → Helper Process → Secure child → stdout/stderr |

### 5. Memory Management

| Pattern              | Implementation                                                         |
| -------------------- | ---------------------------------------------------------------------- |
| **Weak Captures**    | Use `[weak self]` or `[weak viewModel]` in escaping closures           |
| **Callback Cleanup** | Nil closure properties in `onDisappear` (e.g., `onAddReference = nil`) |
| **Nested Tasks**     | Always use `[weak self]` in `Task { }` blocks inside view models       |
| **Debug Logging**    | Add `deinit { print("🗑️ ClassName deallocated") }` during debugging    |

---

## 🎨 Liquid Glass UI

The UI follows the "Liquid Glass" design language with translucent materials, semantic tinting, and fluid animations.

### Design Tokens

```swift
LiquidGlassTokens.Spacing.rowGutter    // 12pt
LiquidGlassTokens.Spacing.sheetInset   // 16pt
LiquidGlassTokens.Radius.control       // 10pt
LiquidGlassTokens.Radius.card          // 16pt
```

### Glass Effect Usage

```swift
// ✅ Correct - Use native modifier
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

// ✅ Interactive elements
.glassEffect(GlassEffect.clear.interactive(), in: .capsule)

// ✅ Tinted glass
.glassEffect(GlassEffect.regular.tint(theme.accent.opacity(0.2)), in: .rect)

// ❌ Never use legacy materials
.background(.ultraThinMaterial)  // DEPRECATED
```

### Key UI Components

| Component           | Purpose                                           |
| ------------------- | ------------------------------------------------- |
| `NeonChatView`      | Main chat interface                               |
| `ChatInputPanel`    | Glass input bar with attachments and tool toggles |
| `NeonMessageBubble` | Message rendering with markdown                   |
| `ToolResultCard`    | Tool execution result display                     |
| `TokenUsageCapsule` | Live token/cost display                           |
| `NeonSidebar`       | Session list and navigation                       |

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
├── App/                    # Entry points
├── Models/                 # Domain models & SwiftData entities
├── Providers/              # LLM API integrations
├── Services/               # Business logic
│   ├── ContextManagement/  # Token estimation & compaction
│   └── ModelFetch/         # Model registry & fetching
├── Support/                # Provider adapters & utilities
├── Theme/                  # Theme definitions
├── Tools/                  # Tool implementations
├── Utilities/              # Helper extensions
├── ViewModels/             # State management
└── Views/                  # SwiftUI interfaces
    ├── Chat/               # Chat UI components
    ├── Components/         # Reusable UI components
    ├── Settings/           # Settings screens
    ├── Sidebar/            # Navigation sidebar
    └── Workbench/          # Workbench window
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

- **MarkdownUI** — Chat message rendering
- **Splash** — Syntax highlighting
- **SwiftCollections** — Efficient data structures

---

_Last Updated: December 2025_
