# OpenAI Responses API Tool Result Role Mapping Fix

## Issue
When using OpenAI's Responses API (gpt-5*, o1*, o3*, o4* models), tool result messages with role "tool" were being rejected with error: **"Invalid value: 'tool'"**.

The Responses API requires tool outputs to use role "user" instead of "tool" for agentic continuation, while the legacy Chat Completions API expects role "tool".

## Solution
Modified `OpenAIProvider.swift` to detect which API endpoint is being used and map tool result message roles accordingly:
- **Responses API** (gpt-5*, o1*, etc.): Map role "tool" → "user"
- **Chat Completions API** (gpt-4o, etc.): Keep role "tool" unchanged

## Changes

### File: `llmHub/Support/OpenAIProvider.swift`

#### 1. Added OSLog import and logger instance
```swift
import OSLog

private nonisolated let logger = Logger(subsystem: "com.llmhub", category: "OpenAIProvider")
```

#### 2. Modified `buildRequest` method to detect endpoint and map roles
```swift
let endpoint = ModelRouter.endpoint(for: model)
let isResponsesAPI = (endpoint == .responses)

// Map messages
let openAIMessages = messages.map { msg -> OpenAIChatMessage in
    // Handle tool role messages - Responses API requires "user" role instead of "tool"
    if msg.role == .tool {
        let mappedRole: String
        if isResponsesAPI {
            // Responses API (gpt-5*, o1*, etc.) requires tool results as "user" role
            mappedRole = "user"
            logger.debug("OpenAIProvider: Mapped tool result message to 'user' role for Responses API (model: \(model))")
        } else {
            // Chat Completions API uses "tool" role
            mappedRole = "tool"
        }
        return OpenAIChatMessage(
            role: mappedRole,
            content: .text(msg.content),
            toolCallId: msg.toolCallID
        )
    }
    // ... rest of message mapping
}
```

## Technical Details

### Endpoint Detection
Uses `ModelRouter.endpoint(for: model)` which routes models based on patterns:
- Models containing "gpt-5" → `.responses`
- Models starting with "gpt-4.1" → `.responses`
- Models starting with "o" followed by a number (o1, o3, o4) → `.responses`
- All other models → `.chatCompletions`

### Content Type Handling
The existing `OpenAIManager.makeResponsesRequest` already correctly handles the content type mapping:
- When role is `.user` (mapped from `.tool`), it sets content type to "input_text"
- When role is `.assistant`, it sets content type to "output_text"

### Message Flow
1. **ChatService.swift**: Creates tool result message with role `.tool` (lines 614-626)
2. **OpenAIProvider.swift**: Maps role based on endpoint:
   - Responses API: `.tool` → "user"
   - Chat Completions API: `.tool` → "tool"
3. **OpenAIManager.makeResponsesRequest**: Converts string role to `MessageRole` enum
4. **OpenAIResponseContent.Text**: Sets correct content type based on role ("input_text" for user/tool)

## Validation

### Build Status
✅ Project builds successfully with no compilation errors

### Testing Recommendations
1. **Manual Testing**: 
   - Create GPT-5.2 session
   - Send prompt that triggers multiple tool calls
   - Verify tool execution succeeds
   - Verify continuation (next LLM turn) succeeds without "Invalid value: 'tool'" error
   
2. **Regression Testing**:
   - Test with gpt-4o model (Chat Completions path)
   - Verify tool execution still works correctly
   - Confirm role "tool" is still used for legacy API

### Debug Logging
When a tool result is mapped for Responses API, debug log outputs:
```
OpenAIProvider: Mapped tool result message to 'user' role for Responses API (model: <model_name>)
```

## Compliance
- ✅ Swift 6.2 concurrency safe (nonisolated logger)
- ✅ Sendable conformance maintained
- ✅ Matches existing code patterns
- ✅ Minimal surgical changes
- ✅ No changes to tool call emission (downstream)
- ✅ Recursive loop continues with correct history

## Files Modified
- `llmHub/Support/OpenAIProvider.swift`

## Files Analyzed (No Changes Required)
- `llmHub/Services/ChatService.swift` - Tool result creation logic unchanged
- `llmHub/Providers/OpenAIManager.swift` - Already handles role mapping correctly
- `llmHub/Support/OpenAIEndpoint.swift` - Endpoint detection logic unchanged
- `llmHub/Models/ChatModels.swift` - MessageRole enum unchanged
