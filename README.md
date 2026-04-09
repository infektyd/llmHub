# llmHub

A native macOS and iOS AI agent platform built on Swift 6 with strict concurrency. llmHub connects to multiple LLM providers through a unified interface, runs multi-agent group chats with named agent identities, executes code in sandboxed environments, and extends functionality through the Model Context Protocol (MCP).

## Architecture

llmHub follows a **Brain / Hand / Loop** design:

```
┌─────────────────────────────────────────────────────────┐
│                        Loop                             │
│         Chat orchestration, agent routing,              │
│      context management, streaming coordination         │
│                                                         │
│  ┌──────────────────┐       ┌────────────────────────┐  │
│  │      Brain       │       │         Hand           │  │
│  │                  │       │                        │  │
│  │  LLM Providers   │◄─────►│   Tool Implementations │  │
│  │  (8 providers)   │       │   (16 tools + MCP)     │  │
│  └──────────────────┘       └────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

- **Brain** — LLM provider implementations behind a shared `LLMProvider` protocol. Each provider handles auth, request building, SSE streaming, and response parsing.
- **Hand** — Tool implementations: code execution, file operations, web search, HTTP requests, artifacts, data visualization, and more. Extended at runtime through MCP tool servers.
- **Loop** — Chat orchestration layer: message routing, context compaction, token estimation, memory retrieval, conversation distillation, and multi-agent coordination.

## Providers

| Provider | Auth | Streaming | Notes |
|----------|------|-----------|-------|
| OpenAI | Keychain | SSE (Chat + Responses API) | Supports `stream_options` for usage tracking |
| Anthropic | Keychain | SSE | Messages API |
| Google Gemini | Keychain | SSE | Pinned model list for stable routing |
| Mistral | Keychain | SSE | Tool manifest sanitization |
| xAI (Grok) | Keychain | SSE | OpenAI-compatible endpoint |
| OpenRouter | Keychain | SSE | Multi-model gateway |
| OpenClaw | Bearer token | SSE | Agent-routed via `openclaw/{agent_id}` |
| Apple Foundation Models | On-device | Native | Local inference, no network required |

## Multi-Agent System

llmHub includes a multi-agent architecture where agents are discovered dynamically from your OpenClaw gateway at runtime via `/v1/models`. Each agent gets a visual identity (name, emoji, color) that's resolved through `AgentIdentityRegistry` — unknown agents receive a deterministic color based on their ID hash.

Agents are routed through OpenClaw with per-agent session keys (`openclaw/{agent_id}`). The `GroupChatOrchestrator` streams responses concurrently (up to 4 agents), and each agent receives a roster of other active participants for context awareness. Users trigger agent routing with `@mentions` in the composer.

Agent configuration (names, roles, models) is defined in your OpenClaw gateway's `openclaw.json` — llmHub discovers and renders whatever agents your gateway exposes.

## Tools

### Built-in

| Tool | Description |
|------|-------------|
| `code_interpreter` | Sandboxed code execution (XPC on macOS, JavaScript on iOS) |
| `shell` | Shell command execution with session persistence |
| `file_reader` | Read files with metadata and size detection |
| `file_editor` | Edit files in the workspace |
| `file_patch` | Apply unified diffs / patches |
| `http_request` | HTTP client with configurable timeouts |
| `web_search` | Web search integration |
| `calculator` | Mathematical calculations |
| `data_visualization` | Generate charts and plots |
| `workspace` | Workspace file management |
| `artifact_list` | List sandbox artifacts |
| `artifact_open` | Open and inspect artifacts |
| `artifact_read_text` | Read text-based artifact content |
| `artifact_describe_image` | Image metadata and analysis |
| `mcp_bridge` | Bridge to external MCP tool servers |

### Tool Policy

Tool availability is governed by `ToolsEnabledPolicy` with three modes:

- **zen** — Minimal tools, relevance-heuristic filtered per message
- **workhorse** — All tools enabled, unlimited budget
- **off** — Tools disabled

A `ToolBudget` caps tool calls per turn. `ToolRelevanceHeuristics` performs keyword analysis to surface only contextually relevant tools in zen mode.

### MCP (Model Context Protocol)

llmHub implements an MCP client (`MCPClient`) that connects to external tool servers over stdio or HTTP. Tools discovered via MCP are bridged into the native tool system through `MCPToolBridge` and appear alongside built-in tools.

## Memory

### Local Memory

- **Memory Retrieval** — Retrieves relevant memory snapshots and injects them as XML context into the system prompt before LLM calls.
- **Memory Management** — Stores, updates, and organizes memory entries per session.
- **Conversation Distillation** — Automatically summarizes long conversations to maintain context within token budgets. Runs on a configurable schedule.

### Sovereign Memory (Optional)

An optional integration with an external [Sovereign Memory](https://github.com/infektyd/sovereign-memory) FastAPI service for persistent cross-session memory:

- **Pre-LLM recall** — Queries the service for relevant context (200ms fail-fast timeout) and injects it as `<sovereign_memory>` tags.
- **Post-LLM processing** — Logs conversation turns and extracts learnings (fire-and-forget, non-blocking).
- **Feature-flagged** — Disabled by default. Enable via `AppSettings.sovereignMemoryEnabled` with configurable base URL (default `http://localhost:8901`).

## Context Management

- **Token Estimation** — Estimates token counts for messages to stay within model context windows.
- **Context Compaction** — Automatically compacts conversation history when approaching token limits, using rolling summaries generated by the active provider.
- **Conversation Classification** — Classifies conversations with debounced heuristics for smart labeling.

## Artifacts

The artifact system provides sandboxed file management for LLM-generated content:

- Import files into a sandboxed directory with manifest tracking
- Preview, read, and describe artifacts through dedicated tools
- Artifact cards in the transcript UI with type-based icons
- Artifact library view for browsing all session artifacts

## iCloud Workspace

`CloudWorkspaceManager` syncs workspaces across devices via iCloud containers with automatic fallback to local storage when iCloud is unavailable.

## Platform Support

| Platform | Min Version | Notes |
|----------|-------------|-------|
| macOS | 26.2 | Full feature set, XPC sandboxed code execution |
| iOS | 26.2 | JavaScript code execution backend, adapted UI |

Built with **Swift 6** (strict concurrency) and **SwiftData** for persistence.

## Project Structure

```
llmHub/
├── App/                    # App entry point, bootstrap
├── Models/                 # Data models (Agent, Chat, Core, Shared)
├── Providers/              # LLM provider implementations
│   ├── Anthropic/
│   ├── Gemini/
│   ├── Mistral/
│   ├── OpenAI/
│   ├── OpenClaw/
│   ├── OpenRouter/
│   ├── XAI/
│   └── Shared/             # LLMProvider protocol, config
├── Services/
│   ├── Artifacts/          # Sandbox and artifact management
│   ├── Chat/               # ChatService, AgentRouting, GroupChat
│   ├── CodeExecution/      # Sandboxed execution backends
│   ├── ContextManagement/  # Token estimation, compaction
│   ├── Conversation/       # Classification, distillation, labeling
│   ├── MCP/                # Model Context Protocol client
│   ├── Memory/             # Local + Sovereign memory services
│   ├── ModelFetch/         # Dynamic model list fetching
│   ├── Tools/              # Tool budget, policy, environment
│   └── Workspace/          # iCloud workspace sync
├── Tools/                  # Tool implementations
├── ViewModels/             # ChatViewModel, feature view models
├── Views/                  # SwiftUI views (Composer, Transcript, Settings)
└── Utilities/              # Colors, helpers

Docs/                       # Architecture, provider guides, platform docs
Tests/                      # Unit and integration tests
Frameworks/                 # Embedded frameworks (Python testbed)
```

## Getting Started

1. Clone the repository
2. Open `llmHub.xcodeproj` in Xcode 26+
3. Add API keys through the in-app Settings (stored in Keychain)
4. Build and run for macOS or iOS

For detailed platform setup, see [`Docs/Platform/`](Docs/Platform/).

## Configuration

Key settings in `AppSettings` (persisted as JSON):

| Setting | Default | Description |
|---------|---------|-------------|
| `maxContextTokens` | Model default | Override context window size |
| `summaryGenerationEnabled` | `false` | Auto-generate conversation summaries |
| `smartRunLabelsEnabled` | `false` | Smart labels for tool run bundles |
| `sovereignMemoryEnabled` | `false` | Enable Sovereign Memory integration |
| `sovereignMemoryBaseURL` | `http://localhost:8901` | Sovereign Memory service URL |

## Documentation

Internal documentation lives in [`Docs/`](Docs/):

- [`Docs/REALITY_MAP.md`](Docs/REALITY_MAP.md) — Current state snapshot of UI and tooling
- [`Docs/AGENTS.md`](Docs/AGENTS.md) — Agent tier guidelines
- [`Docs/CONVENTIONS.md`](Docs/CONVENTIONS.md) — Code style conventions
- [`Docs/Architecture/`](Docs/Architecture/) — System design and analysis
- [`Docs/Providers/`](Docs/Providers/) — Per-provider integration guides
- [`Docs/Security/`](Docs/Security/) — Security audit and implementation docs

## License

MIT — see [License](License) for details.
