# Agent Context Injection: llmHub

> **SYSTEM NOTE**: This file contains the authoritative architectural state of the `llmHub` project. Use this context to ground all future code generation and reasoning.

## 1. Project Summary
**llmHub** is a native macOS IDE for interacting with LLMs. It moves beyond simple chat by implementing a "Brain/Hand" architecture where the LLM (Brain) can deterministically invoke Tools (Hand) to perform actions like code execution, file manipulation, and web search.

## 2. Architecture: "Valon/Modi/Core"
The system follows a strict separation of concerns:

### The Brain (Providers)
- **Role**: Intent processing and response generation.
- **Protocol**: `LLMProvider` (`LLMProviderProtocol.swift`)
- **Implementations**:
  - `OpenAIManager` (GPT-4o, o1)
  - `AnthropicManager` (Claude 3.5 Sonnet)
  - `GeminiManager` (Google AI)
  - `MistralManager` (Mistral AI)
  - `XAIManager` (Grok)
  - `OpenRouterManager` (Aggregator)

### The Hand (Tools)
- **Role**: Deterministic execution of capabilities.
- **Protocol**: `Tool` (`ToolRegistry.swift`)
- **Core Tools**:
  - `CodeInterpreterTool`: Swift/Python execution via Sandboxed XPC.
  - `FileEditorTool` / `FileReaderTool`: Local filesystem access.
  - `MCPToolBridge`: Bridges external Model Context Protocol servers.

### The Loop (Orchestrator)
- **Role**: Coordinates the recursive Brain/Hand interaction.
- **Component**: `ChatService` (`ChatService.swift`)
- **Flow**:
  1. User Input -> `ChatService`
  2. `ChatService` -> `LLMProvider` (Request)
  3. `LLMProvider` -> `ToolCall` (Response)
  4. `ChatService` -> `ToolRegistry` -> `Tool.execute()`
  5. Tool Result -> `ChatService` -> `LLMProvider` (Recursive Call)
  6. `LLMProvider` -> Final Text Response

### The Sandbox (Execution)
- **Role**: Securely execute generated code.
- **Mechanism**: XPC Service (`llmHubHelper`)
- **Protocol**: `CodeExecutionXPCProtocol` (`CodeExecutionXPCProtocol.swift`)
- **Structure**:
  - `llmHub` (Main App) sends code -> `XPCConnection`
  - `llmHubHelper` (XPC Service) receives code -> Spawns Process (`swift`, `python3`) -> Captures `stdout`/`stderr` -> Returns Result.

## 3. Key File Map

| Component | Path | Description |
|-----------|------|-------------|
| **Loop** | `llmHub/Services/ChatService.swift` | Main orchestration loop. Handles state, persistence, and recursion. |
| **Brain** | `llmHub/Providers/LLMProviderProtocol.swift` | Base protocol for all LLM providers. |
| **Hand** | `llmHub/Services/ToolRegistry.swift` | Manages available tools and routing. |
| **Execution** | `llmHub/Services/CodeExecutionEngine.swift` | Main app side of code execution. |
| **XPC** | `llmHubHelper/CodeExecutionHandler.swift` | Helper side implementation of execution logic. |
| **UI** | `llmHub/Views/Main/NeonWorkbenchWindow.swift` | Primary UI container. |
| **MCP** | `llmHub/Services/MCPClient.swift` | Model Context Protocol client implementation. |

## 4. Current State
- **MCP**: Implemented. App can connect to MCP servers and expose their tools to the LLM.
- **Sandbox**: Implemented. `llmHubHelper` is a separate XPC target.
- **Persistence**: `SwiftData` is used for storing `ChatSession`, `ChatMessage`, etc.
- **Streaming**: Fully supported via `AsyncThrowingStream` in `LLMProvider`.

## 5. Coding Conventions
- **Swift 6**: Use `Task`, `await`, `Sendable` everywhere.
- **SwiftData**: Use `@Model` for persistence. Context is passed to `ChatService`.
- **Reference IDs**: Use `ReferenceFormatter.newReferenceID()` for user-facing IDs (e.g., `#A1B2`).
- **XPC**: Always use `CodeExecutionXPCProtocol` for communicating with the helper. Do not run `Process` directly in the main app (Sandbox violation).
- **Tool Protocol**:
  ```swift
  protocol Tool: Sendable {
      var id: String { get }
      var name: String { get }
      var description: String { get }
      var inputSchema: [String: Any] { get }
      func execute(input: [String: Any]) async throws -> String
  }
  ```
