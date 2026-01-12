# Anthropic Tool Result Orphan Bug - Fix Documentation


## Problem Summary

**Issue**: HTTP 400 errors from Anthropic API with message:

```text
"unexpected tool_use_id found in tool_result blocks [...] 
Each tool_result block must have a corresponding tool_use block in the previous message."
```

**Root Cause**: Conversation history contains orphaned `tool_result` blocks whose corresponding `tool_use` blocks are missing, causing API validation failures.


## Solution Implemented

### Location
`/Users/hansaxelsson/llmHub/llmHub/Providers/Anthropic/AnthropicProvider.swift`

### Changes Made

#### 1. Sanitization Function (`sanitizeToolResults`)

- **Purpose**: Removes orphaned `tool_result` blocks before sending to Anthropic API
- **Algorithm**:
  1. First pass: Collect all `tool_use` IDs from assistant messages
  2. Second pass: Filter out `tool_result` blocks that don't have matching `tool_use_id`
  3. Remove empty user messages after filtering
- **Location**: Lines 389-436

#### 2. Validation Function (`validateToolPairing`)

- **Purpose**: Diagnostic logging to detect orphaned tool_results
- **Output**: Console logs showing:
  - All tool_use registrations
  - Valid tool_result pairings
  - Orphaned tool_results (with IDs and message indices)
- **Location**: Lines 342-387

#### 3. Integration Point

- **Location**: Line 159-160 in `buildRequest` method
- **Flow**:

  ```swift
  let sanitizedMessages = sanitizeToolResults(messages: anthropicMessages)
  validateToolPairing(messages: sanitizedMessages)
  ```

## How It Works

### Before Fix

```text
Assistant Message [0]: "Let me use a tool" + tool_use(id: "toolu_abc123")
User Message [1]: tool_result(tool_use_id: "toolu_abc123", content: "result")
[User deletes Assistant Message [0]]
Assistant Message [0]: "New response"
User Message [1]: tool_result(tool_use_id: "toolu_abc123", content: "result") ❌ ORPHANED
→ API returns HTTP 400
```

### After Fix

```text
Assistant Message [0]: "Let me use a tool" + tool_use(id: "toolu_abc123")
User Message [1]: tool_result(tool_use_id: "toolu_abc123", content: "result")
[User deletes Assistant Message [0]]
→ Sanitization detects orphan and removes it
Assistant Message [0]: "New response"
[User Message [1] removed - empty after filtering]
→ API request succeeds ✅
```

## Console Output Examples

### Valid Conversation

```text
🔍 [ToolValidation] ========== VALIDATING CONVERSATION ==========

🔍 [Message 0] Role: assistant
  [0] ✅ Registered tool_use: toolu_01abc123

🔍 [Message 1] Role: user
  [0] ✅ Valid tool_result for: toolu_01abc123

✅ [ToolValidation] All tool_result blocks have matching tool_use blocks
🔍 [ToolValidation] =============================================
```

### Orphaned Result (Before Sanitization)

```text
🔍 [ToolValidation] ========== VALIDATING CONVERSATION ==========

🔍 [Message 0] Role: assistant
  [0] Type: text (New response...)

🔍 [Message 1] Role: user
  [0] ❌ ORPHANED tool_result for: toolu_01abc123

❌ [ToolValidation] FOUND 1 ORPHANED TOOL RESULTS:
  - tool_use_id: toolu_01abc123 in message[1]
⚠️ [ToolValidation] This will cause HTTP 400 from Anthropic!
🔍 [ToolValidation] =============================================
```

### Sanitization in Action

```text
⚠️ [Sanitize] Removing orphaned tool_result: toolu_01abc123
⚠️ [Sanitize] Skipping empty message after filtering
```

## Potential Causes of Orphaned Results

1. **Message Deletion**: User deletes assistant message containing `tool_use`
2. **Failed Tool Execution**: Tool throws error but `tool_result` still created
3. **Persistence Race**: `tool_result` saved to SwiftData but `tool_use` message lost
4. **Context Compaction**: Rolling summary removes old messages including `tool_use`

## Testing Protocol

### Test 1: Orphan Detection

```text
1. Run app with existing conversation history
2. Check console for "🔍 [ToolValidation]" logs
3. Verify no orphaned tool_results reported
```

### Test 2: Tool Execution

```text
1. Send message that triggers tool use
2. Verify tool_use and tool_result are paired
3. Check console shows "✅ Valid tool_result"
```

### Test 3: Message Deletion (Manual)

```text
1. Create conversation with tool use
2. Manually delete assistant message in database
3. Send new message
4. Verify sanitization removes orphaned result
5. Verify no HTTP 400 error
```

## Performance Impact

- **Minimal**: Two passes over message array (O(n) + O(n))
- **Only runs**: Before each Anthropic API request
- **Typical conversation**: 10-50 messages = negligible overhead

## Future Improvements

1. **Prevent at Source**: Add cascade delete rules in SwiftData
2. **Context Manager Integration**: Ensure compaction preserves tool pairing
3. **UI Warning**: Alert user when deleting messages with tool_use blocks
4. **Metrics**: Track orphan frequency to identify root causes

## Related Files

- `AnthropicProvider.swift` - Main fix location
- `ChatService.swift` - Tool execution and message creation
- `ToolExecutor.swift` - Tool execution engine
- `ChatModels.swift` - Message entity definitions

## Verification Commands

```bash
# Search for orphaned tool_results in logs
grep "ORPHANED tool_result" ~/Library/Logs/llmHub/*.log

# Count sanitization events
grep "Sanitize.*Removing orphaned" ~/Library/Logs/llmHub/*.log | wc -l
```

## Status

✅ **Implemented**: 2026-01-11
✅ **Tested**: Validation and sanitization logic
⏳ **Monitoring**: Awaiting production usage data

## Notes

- This is a **defensive fix** - it treats the symptom (orphaned results) rather than preventing the root cause
- The validation logging helps identify where orphans originate
- Consider this a temporary solution until root cause is addressed
