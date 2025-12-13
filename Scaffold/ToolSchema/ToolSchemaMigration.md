# Tool Schema Migration Plan

## Current State
- ToolRegistry.swift has manual tool definitions
- JSON schemas built by hand
- No compile-time validation

## Target State  
- Type-safe tool inputs with ToolInput protocol
- Auto-generated JSON schemas
- Compile-time validation of tool handlers
- Future: Swift macro for schema generation

## Swift 6.2 Considerations
- Full Sendable conformance required
- Actor isolation for tool execution
- Typed throws for better error handling

## Migration Steps

### Phase 1: Schema Types (Jan 12-19)
1. [ ] Activate ToolSchema.swift
2. [ ] Define ToolInput protocol
3. [ ] Create JSONSchema types
4. [ ] Unit test schema generation

### Phase 2: Tool Definitions (Jan 19-26)
1. [ ] Activate BuiltinTools.swift
2. [ ] Port existing tools to new format
3. [ ] Validate schemas match current behavior
4. [ ] A/B test old vs new tool execution

### Phase 3: Registry Refactor (Jan 26 - Feb 2)
1. [ ] Replace ToolRegistry internals
2. [ ] Keep public API stable
3. [ ] Add schema validation on tool calls
4. [ ] Remove old tool definitions

## Terminal vs App Considerations
OpenCode tools run in terminal context with direct filesystem access.
llmHub runs sandboxed - tools need:
- Security-scoped bookmarks for file access
- User permission prompts
- Sandbox-aware path handling

The schema system is portable; the executors are not.
