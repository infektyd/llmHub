# llmHub Architecture

> **SYSTEM NOTE**: This file serves as the authoritative architectural reference for the `llmHub` project. It consolidates previous documentation from `AGENTS.md`.

---

## 🎯 Vision Statement

**llmHub** is a native macOS and iOS IDE designed to bridge chat interfaces with powerful agentic workflows. It prioritizes:

1.  **Frontier Model Integration**: Support for all major providers (OpenAI, Anthropic, Gemini, Mistral, xAI).
2.  **Liquid Glass UI**: A state-of-the-art translucent interface using modern SwiftUI and `GlassEffect` APIs.
3.  **Brain/Hand/Loop Architecture**: Strict separation between reasoning (Brain), execution (Hand), and orchestration (Loop).
4.  **Secure Execution**: Sandboxed code execution on macOS via XPC.

---

## 🏗 System Architecture: "Brain/Hand/Loop"

### 1. The Brain (Providers)

- **Role**: Intent processing and text generation.
- **Protocol**: `LLMProvider`
- **Implementations**: `OpenAIManager`, `AnthropicManager`, `GeminiManager`, `MistralManager`, `XAIManager`, `OpenRouterManager`.
- **Pattern**: Providers are stateless wrappers around APIs; state is managed by `ChatService`.

### 2. The Hand (Tools)

- **Role**: Deterministic execution of capabilities.
- **Protocol**: `Tool` (and `LegacyTool` for migration).
- **Pattern**: Tools are `Sendable` and deterministically execute via `ToolRegistry`.
- **Capabilities**:
  - **Core**: Calculator, File Parsing, Web Search.
  - **System**: Shell (macOS), Code Execution (Swift/Python via XPC).
  - **Cloud**: HTTP Requests, MCP Bridge.

### 3. The Loop (Orchestrator)

- **Role**: Coordinates the recursive interaction.
- **Component**: `ChatService`.
- **Flow**: `User Input` → `Brain` → `tool_calls` → `Hand` → `Tool Result` → `Brain` → `Final Response`.
- **Persistence**: Handled via `SwiftData` (`ChatSession`, `ChatMessage` entities) and "Brain Swapping" logic (persistence of model choice per session).

### 4. The Sandbox (Execution)

- **Role**: Securely execute user-generated code.
- **Component**: `llmHubHelper` (XPC Service).
- **Mechanism**: Main App sends code → XPC connection → Helper Process spawns secure child process → Returns stdout/stderr.
- **Platform**: macOS only.

---

## 🎨 Liquid Glass UI

The UI follows the "Liquid Glass" design language, characterized by translucent materials, vibrant semantic tinting, and fluid animations.

### Core Primitives

- **`GlassEffect`**: Custom SwiftUI modifier replacing standard `.background(.ultraThinMaterial)`.
- **`GlassEffectContainer`**: Groups adjacent glass elements for specialized merging/rendering (future-proofing).
- **`LiquidGlassTokens`**: Central source of truth for spacing, radius, and colors (`NeonTheme.swift`).

### Key Components

- **`NeonChatView`**: The main chat interface.
- **`ChatInputPanel`**: A glass capsule input bar with `AttachmentChip` and `ToolIconToggle`.
- **`TokenUsageCapsule`**: Displays live token counts (Input/Output) and cost.
- **`AttachmentChip`**: Represents file attachments (Images, Text, PDF) with preview capabilities.

---

## 💾 Persistence & State Management

### SwiftData

- **Entities**: `ChatSessionEntity`, `ChatMessageEntity`, `ChatFolderEntity`, `ChatTagEntity`.
- **Migration**: Automatic schema migration enabled.

### "Brain Swapping"

- **Concept**: Each chat session remembers its last used Model and Provider.
- **Mechanism**:
  - `ChatViewModel` observes model/provider changes.
  - Updates `ChatSessionEntity.providerID` and `.model` immediately.
  - On session load (`hydrateState`), the view model restores the specific provider configuration for that session context.

---

## 🛠 Build & Environment

### Platforms

- **macOS**: Target 15.0+ (Liquid Glass APIs shimmied for backward compatibility where needed).
- **iOS**: Target iOS 18.0+.

### Dependencies

- **MarkdownUI**: For rendering chat messages.
- **Splash**: For syntax highlighting.
- **SwiftCollections**: For efficient data structures.

### Known Build Configurations

- **DerivedData**: Ignored in `.gitignore`.
- **Build Fixes**: Recently resolved `lstat` errors by ensuring clean dependency copying and correct `AttachmentType` definitions in `ChatModels.swift`.

---

## 📂 File Structure Highlights

- **`App/`**: Entry points (`llmHubApp`).
- **`Models/`**: SwiftData entities and shared types (`ChatModels.swift`, `SharedTypes.swift`).
- **`ViewModels/`**: State management (`ChatViewModel`, `WorkbenchViewModel`).
- **`Views/`**: SwiftUI interfaces (`Chat/`, `Main/`).
- **`Services/`**: Business logic (`ChatService`, `ToolRegistry`, `ModelRegistry`).
- **`Providers/`**: LLM API integrations.
- **`Tools/`**: Tool implementations.
- **`Docs/`**: Project documentation.

---

_Last Updated: December 2025_
