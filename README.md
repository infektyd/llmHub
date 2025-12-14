# llmHub

**llmHub** is a native macOS and iOS AI Workbench, designed to bridge the gap between chat interfaces and powerful agentic workflows. It features a modular "Brain/Hand/Loop" architecture, securely sandboxed code execution (macOS), Model Context Protocol (MCP) integration, and a cutting-edge **Liquid Glass** UI design.

## 🚀 Features

- **Multi-Provider Support**: Seamlessly switch between major LLM providers:
  - OpenAI (GPT-4o, o1, o3, GPT-4 Turbo)
  - Anthropic (Claude 4 Opus, Sonnet, Haiku)
  - Google Gemini (Gemini 2.5 Pro/Flash)
  - Mistral AI (Mistral Large, Codestral, Pixtral)
  - xAI (Grok 4.1, Grok 4)
  - OpenRouter (Aggregator for 100+ models)
- **Liquid Glass UI**:
  - State-of-the-art translucent, vibrant interface using iOS 26+ Liquid Glass APIs
  - Glass morphism effects, interactive elements, and morphing transitions
  - Platform-optimized for both macOS and iOS
- **Unified Tool System**:
  - **17+ Tools** with platform-aware availability (iOS vs macOS)
  - Core tools: Calculator, CodeInterpreter, FileEditor, FileReader, WebSearch
  - Extended tools: Shell, HTTP, Database, Task Scheduler, Image Generation, and more
  - Permission-based authorization system
  - Multi-tier caching (Hot/Warm/Cold) for tool data
- **"Brain Swapping" Persistence**:
  - Automatically saves the selected Model and Provider for each session
  - Seamlessly restores context when switching between conversations
- **Context Management**:
  - Intelligent token estimation and context compaction
  - Smart truncation strategies to stay within model limits
  - Emergency fallback to preserve system prompt and newest messages
- **Sandboxed Code Execution** (macOS):
  - Runs generated code (Swift/Python/JavaScript/TypeScript) in a secure, isolated XPC service (`llmHubHelper`)
  - Protects the host system while allowing complex data analysis and logic execution
- **Model Context Protocol (MCP)**:
  - First-class support for the MCP standard
  - Connect to external MCP servers to expand tool capabilities
  - Bridge external tools seamlessly into the agent workflow

## 🛠️ Architecture

llmHub follows the **Valon/Modi/Core** principles:

- **Brain**: Pluggable LLM backends (`Providers/`).
- **Hand**: Deterministic tools (`Tools/`).
- **Loop**: The `ChatService` orchestration layer.

## 📦 Installation & Setup

### Prerequisites

- **macOS**: macOS 26.2+ (Sequoia) or later (for Liquid Glass APIs)
- **iOS**: iOS 26.0+ for iPhone and iPad (for Liquid Glass APIs)
- **Xcode**: 17.0+ for building
- **Swift**: 6.2+ with strict concurrency enabled

### Building from Source

1. Clone the repository.
2. Open `llmHub.xcodeproj` in Xcode.
3. Select target:
   - **llmHub (macOS)** for Mac builds
   - **llmHub (iOS)** for iPhone/iPad builds
4. **macOS only**: The project includes a helper XPC service (`llmHubHelper`) for sandboxed code execution. Ensure this target builds successfully and is embedded in the main app bundle.
5. Build and Run (Cmd+R).

## 💡 Usage

### Configuration

1. Launch llmHub.
2. Navigate to Settings:
   - **macOS**: Settings menu (Cmd+,) or menu bar → llmHub → Settings
   - **iOS**: Tap gear icon (⚙️) in top-left of navigation bar
3. Enter your API keys for the desired providers. Keys are stored securely in the system Keychain.

### Chat & Workbench

- **Chat**: Create new sessions, select models, and interact with the "Brain".
- **Tools**: The agent will automatically invoke tools (like Code Execution) when asked to perform tasks requiring computation or file access.
- **Execution**: Code runs in the workbench panel, showing real-time logs and output.

### Code Execution (macOS only)

llmHub on macOS supports executing code in multiple languages within a secure sandbox:

- **Python**: Full support for data analysis and scripting.
- **Swift**: Native execution for macOS-specific tasks.
- **JavaScript/TypeScript**: Supported via Node.js integration.

**Note**: Code execution is currently only available on macOS due to iOS sandboxing restrictions.

### File Operations

The agent can read and modify files with your explicit permission. A diff preview is shown before any modification, ensuring you have full control over the changes.

## 🎯 Platform-Specific Features

### macOS

- Full code execution environment with XPC sandboxing
- Multi-window support
- Dedicated Settings window
- File system access with permission dialogs
- Terminal integration

### iOS

- Touch-optimized UI with Liquid Glass theme
- Settings accessible via gear icon in navigation bar
- Interactive keyboard dismissal (swipe down on messages)
- Explicit keyboard dismiss button when typing
- Native iOS navigation patterns
- Full API key management in-app

**Shared Features**: Both platforms share the same LLM providers, chat interface, model selection, and data storage using SwiftData.

## 🤝 Contributing

This project uses **Swift 6.2** with strict concurrency, **SwiftData** for persistence, and **Liquid Glass** for all UI. Please adhere to the architecture defined in `Docs/Architecture.md` when contributing.

### Architecture Guidelines

- **Brain/Hand/Loop**: Providers (LLM) → Tools (Actions) → ChatService (Orchestrator)
- **Swift 6 Concurrency**: All UI types, ViewModels, and Providers use `@MainActor`
- **Liquid Glass First**: All new UI must use `.glassEffect()` and `LiquidGlassTokens` for consistency. Do not use wrapper views.
- **Platform Awareness**: Use `#if os(iOS)` and `#if os(macOS)` for platform-specific code
- **No Placeholders**: Production-quality implementations only (see user rules)

### Key Directories

- `llmHub/Models`: Data models for chat, tools, and execution (SwiftData entities)
- `llmHub/Providers`: LLM API implementations (OpenAI, Anthropic, Gemini, Mistral, xAI, OpenRouter)
- `llmHub/Services`: Core business logic (ChatService, ToolRegistry, ContextManagement, MCP)
- `llmHub/Tools`: Tool definitions and implementations (17+ tools)
- `llmHub/ViewModels`: UI state management using `@Observable`
- `llmHub/Views`: SwiftUI views with Liquid Glass styling
- `llmHub/ContextManagement`: Token estimation and context compaction
- `llmHubHelper`: The sandboxed XPC service for code execution (macOS only)

### Documentation

All public APIs are fully documented. Please ensure new code includes comprehensive docstrings following the Swift documentation standards.

## 📄 License

[License Type] - See LICENSE file for details.
