# llmHub

**llmHub** is a native macOS and iOS AI Workbench, designed to bridge the gap between chat interfaces and powerful agentic workflows. It features a modular "Brain/Hand/Loop" architecture, a Canvas-first flat UI, Model Context Protocol (MCP) scaffolding, and a unified tool system.

## 🚀 Features

- **Multi-Provider Support**: Seamlessly switch between major LLM providers:
  - OpenAI (GPT-4o, o1, o3, GPT-4 Turbo)
  - Anthropic (Claude 4 Opus, Sonnet, Haiku)
  - Google Gemini (Gemini 2.5 Pro/Flash)
  - Mistral AI (Mistral Large, Codestral, Pixtral)
  - xAI (Grok 4.1, Grok 4)
  - OpenRouter (Aggregator for 100+ models)
- **Canvas/Flat UI**:
  - Canvas-first layout with matte surfaces and minimal decoration
  - Built for clarity, dense information, and low-ornament workflows
  - Shared design language across macOS and iOS
- **Unified Tool System**:
  - Actor-based `ToolRegistry` + concurrent `ToolExecutor` + `ToolAuthorizationService`
  - Current tools: Calculator, CodeInterpreter, FileReader, FileEditor, FilePatch, WebSearch, HTTPRequest, Shell (macOS only), Workspace, DataVisualization, ArtifactList, ArtifactOpen, ArtifactReadText, ArtifactDescribeImage
  - Permission-based authorization and session-scoped LRU caching for eligible tools
- **"Brain Swapping" Persistence**:
  - Automatically saves the selected Model and Provider for each session
  - Seamlessly restores context when switching between conversations
- **Context Management**:
  - Intelligent token estimation and context compaction
  - Smart truncation strategies to stay within model limits
  - Emergency fallback to preserve system prompt and newest messages
- **Code Execution Backend**:
  - XPC helper (`llmHubHelper`) exists but is currently disabled on macOS due to entitlements issues
  - iOS uses a JavaScriptCore-backed engine (JavaScript only)
- **Model Context Protocol (MCP)**:
  - First-class support for the MCP standard
  - Connect to external MCP servers to expand tool capabilities
  - Bridge external tools seamlessly into the agent workflow

## 🛠️ Architecture

llmHub follows the **Valon/Modi/Core** principles:

- **Brain**: Pluggable LLM backends (`llmHub/Providers/`).
- **Hand**: Deterministic tools (`llmHub/Tools/`).
- **Loop**: The `ChatService` orchestration layer.

## 📦 Installation & Setup

### Prerequisites

- **macOS**: macOS 26.2+ (Sequoia) or later
- **iOS**: iOS 26.0+ for iPhone and iPad
- **Xcode**: 17.0+ for building
- **Swift**: 6.2+ with strict concurrency enabled

### Building from Source

1. Clone the repository.
2. Open `llmHub.xcodeproj` in Xcode.
3. Select target:
   - **llmHub (macOS)** for Mac builds
   - **llmHub (iOS)** for iPhone/iPad builds
4. **macOS only**: The project includes a helper XPC service (`llmHubHelper`) for sandboxed code execution. The helper builds, but execution is currently disabled (see `Docs/REALITY_MAP.md`).
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
- **Execution**: The workbench surfaces execution results when the backend is available. (macOS backend is currently disabled.)

### Code Execution (Current Status)

- **macOS**: XPC backend is temporarily disabled due to sandbox/entitlements issues. Code interpreter requests will report unavailable.
- **iOS**: JavaScript-only execution via JavaScriptCore.

### File Operations

The agent can read and modify files with your explicit permission. A diff preview is shown before any modification, ensuring you have full control over the changes.

## 🎯 Platform-Specific Features

### macOS

- XPC helper present, but execution backend is disabled (see `Docs/REALITY_MAP.md`)
- Multi-window support
- Dedicated Settings window
- File system access with permission dialogs
- Terminal integration

### iOS

- Touch-optimized Canvas/flat UI
- Settings accessible via gear icon in navigation bar
- Keyboard behavior follows iOS defaults
- Native iOS navigation patterns
- Full API key management in-app

**Shared Features**: Both platforms share the same LLM providers, chat interface, model selection, and data storage using SwiftData.

## 🤝 Contributing

This project uses **Swift 6.2** with strict concurrency and **SwiftData** for persistence. The UI is Canvas-first and flat; see [`Docs/REALITY_MAP.md`](Docs/REALITY_MAP.md) and [`Docs/AGENTS.md`](Docs/AGENTS.md) when contributing.

> **🤖 AI Assistants**: Please read [`Docs/ONBOARDING_AGENTS.md`](Docs/ONBOARDING_AGENTS.md) for critical context and operational parameters.

### Architecture Guidelines

- **Brain/Hand/Loop**: Providers (LLM) → Tools (Actions) → ChatService (Orchestrator)
- **Swift 6 Concurrency**: All UI types, ViewModels, and Providers use `@MainActor`
- **Canvas First**: Use the Canvas/flat styling (AppColors, matte surfaces) and avoid legacy glass-specific modifiers.
- **Platform Awareness**: Use `#if os(iOS)` and `#if os(macOS)` for platform-specific code
- **No Placeholders**: Production-quality implementations only (see user rules)

### Key Directories

- `llmHub/Models`: Data models for chat, tools, and execution (SwiftData entities)
- `llmHub/Providers`: LLM API implementations (OpenAI, Anthropic, Gemini, Mistral, xAI, OpenRouter)
- `llmHub/Services`: Core business logic (ChatService, ToolRegistry, ContextManagement, MCP)
- `llmHub/Tools`: Tool implementations (core tools + integrations + stubs)
- `llmHub/ViewModels`: UI state management using `@Observable`
- `llmHub/Views`: SwiftUI views with Canvas/flat styling
- `llmHub/Services/ContextManagement`: Token estimation and context compaction
- `llmHubHelper`: The sandboxed XPC service for code execution (macOS only)

### Documentation

All public APIs are fully documented. Please ensure new code includes comprehensive docstrings following the Swift documentation standards.

## 📄 License

[License Type] - See LICENSE file for details.
