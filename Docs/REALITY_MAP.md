# Reality Map (Current Implementation)

**Last updated:** 2026-01-14

This document is the authoritative snapshot of what is implemented today. Use it
whenever older docs or speculative plans conflict with reality.

---

## UI Direction (Canvas/Flat)

- Canvas-first layout with matte/flat surfaces (no Liquid Glass styling).
- Root view: `CanvasRootView` in `llmHub/Views/UI/RootView.swift`.
- Transcript: `TranscriptCanvasView` in `llmHub/Views/UI/TranscriptView.swift`.
- Sidebars: `ModernSidebarLeft` and `ModernSidebarRight` in `llmHub/Views/UI/Sidebars/`.
- Styling tokens: `AppColors` + `UIAppearance` in `llmHub/Utilities/UI/`.

---

## Tool System (Current Wiring)

- `ToolRegistry` (actor) owns registered tools.
- `ToolExecutor` runs tool calls with schema validation, availability checks,
  session-scoped LRU caching, and authorization enforcement.
- `ToolAuthorizationService` is default-deny; Settings toggles update global
  permissions. Conversation-scoped APIs exist but are not wired to UI prompts.

### Registered Tools

Registered in `ChatViewModel.ensureChatService()`:

- `CalculatorTool`
- `CodeInterpreterTool` (macOS backend disabled; iOS JS-only)
- `FileReaderTool`
- `FileEditorTool`
- `FilePatchTool`
- `WebSearchTool`
- `HTTPRequestTool`
- `ShellTool` (macOS only)
- `WorkspaceTool`
- `DataVisualizationTool`

### Not Wired / Stubbed

- `MCPToolBridge` exists but is not registered in `ToolRegistry`.
- `Tools/Stubs/` (DatabaseQueryTool, ImageGenerationTool, EmailNotificationTool,
  TaskSchedulerTool, BrowserAutomationTool) are not registered.
- `ShellSession` exists but is not exposed as a tool.

---

## macOS Code Execution Disabled (XPC Backend)

- `ChatViewModel` forces `hasCodeExecutionBackend = false` on macOS due to
  XPC helper entitlements/sandbox issues (see TODO in code).
- The XPC helper (`llmHubHelper`) and `XPCExecutionBackend` exist but are not
  enabled in the current app build.
- iOS uses `iOSJavaScriptExecutionBackend` (JavaScript only).

---

## Known Gaps

- `FileReaderTool.describeImage()` returns a stub string.
- Tool Inspector is partial: `toolInspectorVisible` flag exists, but no
  dedicated per-tool execution inspector UI is wired.
- MCP configuration UI is missing; MCP bridge is not registered.
- Authorization is global-only in UI (no per-conversation prompt flow yet).

---

## Near-Term Milestones (Inferred)

- Fix XPC helper entitlements and re-enable macOS code execution backend.
- Implement image description pipeline for `FileReaderTool`.
- Wire `MCPToolBridge` into `ToolRegistry` and add settings UI for server configs.
- Expand the Tool Inspector to show per-tool call details/history.
