# Context Compaction Migration Plan

## Current State
- No context management in ChatService
- Long conversations may exceed context limits
- API errors on overflow

## Target State
- Automatic compaction before API calls
- Multiple strategies based on use case
- Seamless user experience

## Migration Steps

### Phase 1: Token Estimation (Jan 5-12)
1. [ ] Activate TokenEstimator.swift
2. [ ] Add token count display to UI (optional)
3. [ ] Log token counts in ChatService

### Phase 2: Basic Compaction (Jan 12-19)
1. [ ] Activate ContextCompactor.swift
2. [ ] Implement truncateOldest strategy
3. [ ] Integrate with ChatService.streamCompletion()
4. [ ] Add user preference for auto-compaction

### Phase 3: Smart Compaction (Jan 19-26)
1. [ ] Implement summarizeOldest strategy
2. [ ] Add summary model selection
3. [ ] Store summaries in SwiftData for persistence

## Integration Point
In ChatService.swift, before API call:
```swift
let compacted = try await compactor.compact(
    messages: session.messages,
    config: .init(maxTokens: model.contextWindow ?? 128000)
)
```
