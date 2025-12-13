# LLMHub UI Tool Wiring & Architecture Map

## 1. Executive Summary

This document provides a technical overview of the UI architecture and tool execution pipeline within `llmHub`. It is designed to help external reviewers and developers understand how tool calls are orchestrated, rendered, and managed from the front-end down to the core services.

**Key Findings:**

- **Architecture:** The system follows a clean MVVM pattern (`NeonChatView` -> `ChatViewModel` -> `ChatService`).
- **Tool Execution:** Handled primarily by an autonomous agent loop within `ChatService.streamCompletion`, which executes tools recursively and feeds results back to the LLM.
- **Rendering:** Tool outputs are currently rendered as separate chat bubbles (appearing similar to Assistant messages) or embedded in the stream text. There is no distinct "Tool Result Card" UI component yet.
- **Permissions:** Managed via `ChatInputPanel` toggles, persisted by `ToolAuthorizationService`.

---

## 2. Core Architecture Components

### 2.1 View Layer

| Component               | File Path                                         | Responsibility                                                                                                                                  |
| ----------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **`NeonChatView`**      | `llmHub/Views/Chat/NeonChatView.swift`            | Main entry point. Binds specific session data to the UI. Manages the message list scroll state and overall layout.                              |
| **`NeonMessageBubble`** | `llmHub/Views/Chat/NeonMessageBubble.swift`       | Renders individual messages. **Critically**, it treats all non-user messages (Role: `.assistant`, `.tool`) similarly, using Markdown rendering. |
| **`ChatInputPanel`**    | `llmHub/Views/Chat/ChatInputPanel.swift`          | Handles user input, file attachments, and **tool permission toggles** via the `ToolsListView`.                                                  |
| **`NeonToolInspector`** | `llmHub/Views/Components/NeonToolInspector.swift` | A side panel for visualizing active tool states (controlled by `WorkbenchViewModel`).                                                           |

### 2.2 ViewModel Layer

| Component                | File Path                                    | Responsibility                                                                                                                                                                  |
| ------------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`ChatViewModel`**      | `llmHub/ViewModels/ChatViewModel.swift`      | Manages transient UI state (`stagedAttachments`, `toolToggles`). Hydrates tool lists from `ToolRegistry` and `ToolAuthorizationService`. Proxies send actions to `ChatService`. |
| **`WorkbenchViewModel`** | `llmHub/ViewModels/WorkbenchViewModel.swift` | Global app state. Manages `activeToolExecution` which drives the `NeonToolInspector`.                                                                                           |

### 2.3 Service Layer

| Component          | File Path                            | Responsibility                                                                                                                         |
| ------------------ | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| **`ChatService`**  | `llmHub/Services/ChatService.swift`  | **The Brain.** Manages the `streamCompletion` agent loop. Detects `.toolUse`, calls `ToolExecutor`, and appends `.tool` role messages. |
| **`ToolExecutor`** | `llmHub/Services/ToolExecutor.swift` | Handles the actual execution of tools (e.g., shell commands, HTTP requests) in a sandboxed environment.                                |
| **`ToolRegistry`** | `llmHub/Services/ToolRegistry.swift` | Source of truth for all available `Tool` implementations.                                                                              |

---

## 3. End-to-End Tool Calling Flow

### Step 1: Initialization & Injection

1. **`ChatViewModel.ensureChatService(...)`**: Initializes the service stack.
2. **`ChatService.streamCompletion(...)`**:
   - Fetches tools from `ToolRegistry`.
   - Filters tools based on `ToolAuthorizationService` (user toggles).
   - Converts to `ToolDefinition`.
   - Inject into LLM context via `provider.buildRequest(..., tools: toolDefs)`.

### Step 2: The Agent Loop (`ChatService`)

The `streamCompletion` method runs a `while` loop (max 10 iterations) to handle autonomous tool use:

1. **Request:** Sends current message history (including prior tool results) to the LLM Provider.
2. **Stream Handling:**
   - Listens for `.toolUse(id, name, inputs)` events from the provider.
   - Yields these events to the UI stream (so `ChatViewModel` knows something is happening).
   - Accumulates tool calls in `accumulatedToolCalls`.
3. **Execution:**
   - If `accumulatedToolCalls` is not empty, it calls `executor.execute()`.
   - **UI Feedback:** Yields `.toolExecuting(name)` and a pseudo-token `\n[Tool Result: ...]\n` to the text stream.
4. **Persistence:**
   - Creates a new `ChatMessage` with `role: .tool` containing the output.
   - Appends it to the `ChatSession`.
5. **Recursion:** The loop continues, sending the new `.tool` message back to the LLM for the final response.

### Step 3: Rendering (`NeonChatView`)

1. The **Streaming Assistant Message** (`NeonMessageBubble`) displays the text progress.
   - _Note:_ It may display raw tool result text if the provider yields it as tokens.
2. The **Tool Result Message** (`ChatMessage` with `role: .tool`) is persisted.
   - `NeonChatView` iterates over `session.messages`.
   - `NeonMessageBubble` checks `isUser` (False for tools).
   - **Result:** The tool output renders effectively as an Assistant message bubble, usually containing the JSON or text output of the tool.

---

## 4. "Edit Points" for Future Improvements

To implement distinct UI features for tools, the following files require modification:

### A. dedicated Tool Call Cards

**Goal:** Render tool inputs and outputs as distinct, rich UI cards instead of generic markdownText.

- **Target:** `llmHub/Views/Chat/NeonMessageBubble.swift`
- **Action:**
  1.  Update `isUser` logic or add a specific `isTool` check.
  2.  In `body`, add a `case .tool:` branch or `if message.role == .tool` block.
  3.  Create a `ToolResultView` subview to parse and display the tool content (e.g., Syntax highlighted JSON, Data Table, Image).

### B. Interactive Tool Playground

**Goal:** Allow users to manually configure and run tools.

- **Target:** `llmHub/Views/Components/NeonToolInspector.swift` (and `ChatViewModel`)
- **Action:**
  1.  Current implementation in `ChatViewModel.triggerTool` is a simulation/stub.
  2.  Wire `NeonToolInspector` buttons to call a real `ChatService.executeTool(...)` method (needs to be exposed).

### C. Enhanced Permissions UI

**Goal:** More granular control than simple toggles.

- **Target:** `llmHub/Views/Chat/ChatInputPanel.swift` -> `ToolsListView`
- **Action:**
  1.  The `ToolsListView` struct currently uses `UIToolToggleItem`.
  2.  Expand `UIToolToggleItem` to include configuration parameters (e.g., "Allow specific domains" for WebSearch).
  3.  Update `onToggle` to support configuration sheets.

---

## 5. Critical Data Models (`ChatModels.swift`)

Understanding the `ChatMessage` struct is vital for UI rendering logic:

```swift
enum MessageRole: String, Codable, Equatable {
    case user
    case assistant
    case system
    case tool  // <--- The key differentiator
}

struct ChatMessage: Identifiable, ... {
    let id: UUID
    let role: MessageRole
    var content: String

    // Tool-specific properties
    var toolCallID: String?      // Links result to the request
    var toolCalls: [ToolCall]?   // The request itself (Assistant role)
}
```

The UI (`NeonMessageBubble`) currently conflates `.tool` and `.assistant` roles. Splitting this logic is the primary step for any "Tool Card" UI work.
