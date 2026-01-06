# Sidecar model output isolation (no chat-memory cross-contamination)

## Guarantee
Sidecar outputs (AFM sidecar tasks and the Gemini fallback sidecar model) are treated as **ephemeral** only.
They must **not** be persisted into any storage that can influence future chat generations ("chat memory"), and must **not** be included in chat prompting.

## Enforcement points

### Transcript persistence (chat history)
- **Guard**: sidecar-origin `ChatMessage` objects are refused at persistence time.
- Location: [llmHub/Services/Chat/ChatService.swift](llmHub/Services/Chat/ChatService.swift)
  - Function: `appendMessage(_:to:)`
  - Rule: if `message.provenance.channel == .sidecar` → **NO-OP** (skip persist)

### Prompt building (chat generation)
- **Defense-in-depth**: even if sidecar content somehow enters persistence, it is filtered out before building the provider request.
- Location: [llmHub/Services/Chat/ChatService.swift](llmHub/Services/Chat/ChatService.swift)
  - Function: `streamCompletion(for:userMessage:...)`
  - Rule: remove any messages with `provenance.channel == .sidecar` before compaction / request construction

### Memory writes (distilled memory)
- **Hard gate**: memory write operations accept only `provenance.channel == .chat`.
- Location: [llmHub/Services/Memory/ConversationDistillationService.swift](llmHub/Services/Memory/ConversationDistillationService.swift)
  - Function: `persist(memory:modelContext:provenance:)`
  - Rule: if provenance is sidecar → **NO-OP** and log once
- Location: [llmHub/Services/Memory/MemoryManagementService.swift](llmHub/Services/Memory/MemoryManagementService.swift)
  - Functions: `create(_:modelContext:provenance:)`, `update(_:modelContext:provenance:)`

## Sidecar outputs: allowed destinations
- Ephemeral UI artifacts (e.g. temporary artifact cards) or debug logs/telemetry
- Not persisted into SwiftData entities used for chat transcript or memory prompting

## Tests
- [Tests/llmHubTests/llmHubTests.swift](Tests/llmHubTests/llmHubTests.swift)
  - `sidecarAppendMessageIsNotPersisted()`: sidecar messages are not persisted to transcript
  - `sidecarMessagesAreFilteredFromPrompting()`: sidecar messages are filtered out of provider requests
  - `geminiFallbackDistillationDoesNotPersistMemory()`: Gemini fallback distillation runs but does **not** persist to `MemoryEntity`
