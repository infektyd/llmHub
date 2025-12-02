# llmHub

**llmHub** is a native macOS IDE for Large Language Models, designed to bridge the gap between chat interfaces and powerful agentic workflows. It features a modular "Brain/Hand" architecture, securely sandboxed code execution, and Model Context Protocol (MCP) integration.

## 🚀 Features

- **Multi-Provider Support**: Seamlessly switch between major LLM providers:
  - OpenAI (GPT-4o, o1)
  - Anthropic (Claude 3.5 Sonnet/Opus)
  - Google Gemini (1.5 Pro/Flash)
  - Mistral AI
  - xAI (Grok)
  - OpenRouter (Aggregator)
- **Sandboxed Code Execution**: 
  - Runs generated code (Swift/Python/JS) in a secure, isolated XPC service (`llmHubHelper`).
  - Protects the host system while allowing complex data analysis and logic execution.
- **Model Context Protocol (MCP)**:
  - First-class support for the MCP standard.
  - Connect to external MCP servers to expand tool capabilities.
- **Agentic Tools**:
  - `CodeInterpreterTool`: Execute code safely.
  - `FileEditorTool` / `FileReaderTool`: Manipulate project files with permission.
  - `WebSearchTool`: Retrieve real-time information.
- **Neon Workbench UI**: A modern, futuristic interface built with SwiftUI.

## 🛠️ Architecture

llmHub follows the **Valon/Modi/Core** principles:
- **Brain**: Pluggable LLM backends (`Providers/`).
- **Hand**: Deterministic tools (`Tools/`).
- **Loop**: The `ChatService` orchestration layer.

## 📦 Installation & Setup

### Prerequisites
- macOS 14.0+ (Sonoma) or later.
- Xcode 15.0+ for building.

### Building from Source
1. Clone the repository.
2. Open `llmHub.xcodeproj` in Xcode.
3. Ensure the **llmHub** target is selected.
4. The project includes a helper XPC service (`llmHubHelper`). Ensure this target builds successfully and is embedded in the main app bundle.
5. Build and Run (Cmd+R).

## 💡 Usage

### Configuration
1. Launch llmHub.
2. Navigate to Settings (or use the initial setup flow).
3. Enter your API keys for the desired providers. Keys are stored securely in the macOS Keychain.

### Chat & Workbench
- **Chat**: Create new sessions, select models, and interact with the "Brain".
- **Tools**: The agent will automatically invoke tools (like Code Execution) when asked to perform tasks requiring computation or file access.
- **Execution**: Code runs in the workbench panel, showing real-time logs and output.

### Code Execution
llmHub supports executing code in multiple languages within a secure sandbox:
- **Python**: Full support for data analysis and scripting.
- **Swift**: Native execution for macOS-specific tasks.
- **JavaScript/TypeScript**: Supported via Node.js integration.

### File Operations
The agent can read and modify files with your explicit permission. A diff preview is shown before any modification, ensuring you have full control over the changes.

## 🤝 Contributing

This project uses **Swift 6** and **SwiftData**. Please adhere to the architecture defined in `Docs/AGENTS.md` when contributing.

### Key Directories
- `llmHub/Models`: Data models for chat, tools, and execution.
- `llmHub/Providers`: LLM API implementations (OpenAI, Anthropic, etc.).
- `llmHub/Services`: Core business logic (Chat, Execution, MCP).
- `llmHub/Tools`: Tool definitions and implementations.
- `llmHub/ViewModels`: UI state management.
- `llmHub/Views`: SwiftUI views.
- `llmHubHelper`: The sandboxed XPC service for code execution.

### Documentation
All public APIs are fully documented. Please ensure new code includes comprehensive docstrings following the Swift documentation standards.

## 📄 License

[License Type] - See LICENSE file for details.
