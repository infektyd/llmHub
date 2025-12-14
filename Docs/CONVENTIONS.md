# llmHub Development Conventions

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

## Liquid Glass UI
- Use `.glassEffect()` modifier, never `.ultraThinMaterial`
- Reference `LiquidGlassTokens.Spacing.*` and `LiquidGlassTokens.Radius.*`
- No legacy glass wrapper views
- `.buttonStyle(.glass)` for buttons
- `.interactive()` for touch-responsive elements

## Tool System
- All tools conform to unified `Tool` protocol (Sendable)
- Tools are `nonisolated struct` with platform-aware availability
- Register in `ToolRegistry.shared`
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

## XPC Code Execution (macOS only)
- `CodeInterpreterTool` uses `llmHubHelper` XPC service
- Helper is NOT sandboxed (full system access by design)
- No import restrictions (personal use tool)
- Timeout enforced, temp file cleanup
- Supports: Python, JavaScript, TypeScript, Swift, Dart

## Error Handling
- Tool errors: Inject `.tool` message with error content, continue loop
- Provider errors: Emit `.error(LLMProviderError)` event
- Never crash the agent loop; always inject error and continue

## Code Style
- Prefer `guard let` over force unwrapping
- Avoid nested pyramids; extract helper functions
- Use descriptive variable names (avoid `x`, `tmp`, `data`)
- Comment complex concurrency patterns
