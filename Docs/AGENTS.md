# Agent Architecture

This document defines the "Brain" (LLM) and "Hand" (Tool) interaction model for LLMHub, following the "Valon/Modi/Core" principles.

## Core Concepts

### 1. The Brain (LLMProvider)
The **Brain** is responsible for:
- Processing user intent.
- Determining if a **Tool** is needed.
- Generating arguments for the tool.
- Synthesizing the final response after tool execution.

### 2. The Hand (Tool)
The **Hand** is a deterministic function that:
- Takes structured input (JSON).
- Performs a specific action (e.g., Calculator, Web Search, File Access).
- Returns a structured string result (or JSON).

### 3. The Loop (ChatService)
The **Loop** coordinates the Brain and Hand:
1.  **User Turn**: User sends message.
2.  **Brain Turn**: LLM generates response (Text OR Tool Call).
3.  **Hand Turn** (if needed):
    *   Service detects Tool Call.
    *   Service executes Tool.
    *   Service appends `ToolResult` to history.
    *   Service triggers **Brain Turn** again (Recursion).
4.  **Completion**: LLM generates final text response.

## Protocol Definitions

### Tool Protocol
```swift
protocol Tool: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONSchema { get }
    
    func execute(input: [String: Any]) async throws -> String
}
```

### Tool Registry
The `ToolRegistry` maintains the list of available tools for the current context.

## Data Flow

1.  **User**: "What is 5 * 5?"
2.  **LLM**: `ToolCall(id: "call_1", name: "calculator", input: { "expression": "5 * 5" })`
3.  **Service**:
    *   Parses `ToolCall`.
    *   Finds `CalculatorTool`.
    *   Executes `CalculatorTool.execute(input: ...)` -> "25".
    *   Appends `ChatMessage(role: .tool, content: "25", toolCallID: "call_1")`.
4.  **LLM**: "The answer is 25."
5.  **UI**: Displays "The answer is 25."

## Future Expansions
- **MCP Support**: Integration with Model Context Protocol for external tools.
- **Sandbox**: Running tools in isolated environments.
- **Human-in-the-Loop**: UI prompts for tool approval.

