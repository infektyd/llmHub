# llmHub Development Conventions

**Reality Map (authoritative current-state doc):** `Docs/REALITY_MAP.md`

## Swift 6.2 Strict Concurrency
- `@MainActor` for UI types, providers, view models
- `actor` for isolated state (ToolRegistry, registries)
- All cross-actor types must be `Sendable`
- Use `nonisolated` for properties accessed across isolation boundaries

## Memory Management
- `[weak self]` in all escaping closures
- `[weak viewModel]` in nested Task blocks inside view models
- Nil callback properties in `onDisappear` (e.g., `onAddReference = nil`)
- Add `deinit { print("🗑️ ClassName deallocated") }` during debugging

## Canvas/Flat UI
- Use Canvas-first, matte styling (`AppColors`, `UIAppearance`)
- Prefer existing Canvas layout components in `Views/UI/`
- Avoid legacy glass modifiers and tokens

## Tool System
- All tools conform to unified `Tool` protocol (Sendable)
- Tools are `nonisolated struct` with platform-aware availability
- Register tools in the `ToolRegistry` created in `ChatViewModel`
- Populate `ToolMetrics` (startTime, endTime, durationMs) for observability
- Tool results injected as `role: .tool` messages with `toolCallID`

## Provider Integration
- All providers conform to `@MainActor LLMProvider`
- Use `AsyncThrowingStream<ProviderEvent, Error>` for streaming
- Provider state is stateless; ChatService manages conversation state
- Register in `ProviderRegistry` with canonical ID

## Persistence
- SwiftData entities with `@Model` classes
- Domain models (structs) ↔ Entities via `.asDomain()` / `init(domain:)`
- Complex types JSON-encoded into `Data` fields (e.g., `[ToolCall]`, `[ChatContentPart]`)
- `@Relationship(deleteRule: .cascade)` for parent-child relationships

## Code Execution Backend
- `CodeInterpreterTool` exists, but macOS backend is currently disabled (entitlements/sandbox issue)
- iOS uses JavaScriptCore backend (JavaScript only)
- Timeout enforced, temp file cleanup

## Error Handling
- Tool errors: Inject `.tool` message with error content, continue loop
- Provider errors: Emit `.error(LLMProviderError)` event
- Never crash the agent loop; always inject error and continue

## Code Style
- Prefer `guard let` over force unwrapping
- Avoid nested pyramids; extract helper functions
- Use descriptive variable names (avoid `x`, `tmp`, `data`)
- Comment complex concurrency patterns
