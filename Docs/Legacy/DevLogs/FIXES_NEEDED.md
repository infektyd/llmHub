# Build Fixes Required

## Files to Fix

### 1. GoogleAIProvider.swift
**Location:** `llmHub/Support/GoogleAIProvider.swift`
**Fix:** Add `@MainActor` before struct declaration

```swift
// Change from:
struct GoogleAIProvider: LLMProvider {

// To:
@MainActor
struct GoogleAIProvider: LLMProvider {
```

---

### 2. MistralProvider.swift
**Location:** `llmHub/Support/MistralProvider.swift`
**Fix:** Add `@MainActor` before struct declaration

```swift
// Change from:
struct MistralProvider: LLMProvider {

// To:
@MainActor
struct MistralProvider: LLMProvider {
```

---

### 3. OpenAIProvider.swift
**Location:** `llmHub/Support/OpenAIProvider.swift`
**Fix:** Add `@MainActor` before struct declaration

```swift
// Change from:
struct OpenAIProvider: LLMProvider {

// To:
@MainActor
struct OpenAIProvider: LLMProvider {
```

---

### 4. OpenRouterProvider.swift
**Location:** `llmHub/Support/OpenRouterProvider.swift`
**Fix:** Add `@MainActor` before struct declaration

```swift
// Change from:
struct OpenRouterProvider: LLMProvider {

// To:
@MainActor
struct OpenRouterProvider: LLMProvider {
```

---

### 5. XAIProvider.swift
**Location:** `llmHub/Support/XAIProvider.swift`
**Fix:** Add `@MainActor` before struct declaration

```swift
// Change from:
struct XAIProvider: LLMProvider {

// To:
@MainActor
struct XAIProvider: LLMProvider {
```

---

### 6. CodeExecutionModels.swift
**Location:** `llmHub/Models/CodeExecutionModels.swift`
**Fix:** Make `errorDescription` nonisolated and use nonisolated accessors

**Line 203-205**, replace:

```swift
case .interpreterNotFound(let lang):
    return "Interpreter for \(lang.displayName) not found. Please install \(lang.interpreterName)."
```

**With:**

```swift
case .interpreterNotFound(let lang):
    let display = getNonisolatedDisplayName(for: lang)
    let interpreter = getNonisolatedInterpreterName(for: lang)
    return "Interpreter for \(display) not found. Please install \(interpreter)."
```

**Add these helper functions to `SupportedLanguage` enum:**

```swift
/// Nonisolated accessor for display name
nonisolated var displayNameValue: String {
    switch self {
    case .swift: return "Swift"
    case .python: return "Python"
    case .typescript: return "TypeScript"
    case .javascript: return "JavaScript"
    case .dart: return "Dart"
    }
}

/// Nonisolated accessor for interpreter name
nonisolated var interpreterNameValue: String {
    switch self {
    case .swift: return "swift"
    case .python: return "python3"
    case .typescript: return "ts-node"
    case .javascript: return "node"
    case .dart: return "dart"
    }
}
```

**Update the error description:**

```swift
var errorDescription: String? {
    switch self {
    case .interpreterNotFound(let lang):
        return "Interpreter for \(lang.displayNameValue) not found. Please install \(lang.interpreterNameValue)."
    // ... rest remains the same
    }
}
```

---

### 7. MCPToolBridge.swift
**Location:** `llmHub/Tools/MCPToolBridge.swift`
**Fix:** Make input parameter explicitly Sendable

**Line 232**, change:

```swift
nonisolated func execute(input: [String: Any]) async throws -> String {
```

**To:**

```swift
nonisolated func execute(input: [String: Any]) async throws -> String {
    // Ensure input is captured safely
    let capturedInput = input as [String: Any]
    
    logger.info("Calling MCP tool: \(self.name)")

    do {
        let result = try await client.callTool(name: name, arguments: capturedInput)
```

**OR** better yet, if MCPClient.callTool accepts a Sendable type, cast it:

```swift
nonisolated func execute(input: [String: Any]) async throws -> String {
    logger.info("Calling MCP tool: \(self.name)")

    do {
        // Use assumeIsolated or ensure the dictionary is Sendable
        let result = try await client.callTool(name: name, arguments: input as [String: Sendable])
```

---

## Build Steps After Fixes

1. **Clean Build Folder**: ⇧⌘K (Shift + Cmd + K)
2. **Clean Derived Data** (Optional but recommended):
   - Close Xcode
   - Delete: `~/Library/Developer/Xcode/DerivedData/llmHub-*`
   - Reopen project
3. **Build**: ⌘B (Cmd + B)

---

## Why These Fixes Work

### Main Actor Isolation
Swift 6's strict concurrency checking requires that types conforming to `Identifiable` in SwiftUI contexts must be main-actor isolated. Since these providers are used in SwiftUI views and conform to `LLMProvider: Identifiable`, they need the `@MainActor` annotation.

### Nonisolated Properties
The `errorDescription` property is accessed from non-isolated contexts (when errors are thrown from actors). By providing `nonisolated` computed properties on the enum, we can safely access values without crossing actor boundaries.

### Sendable Dictionaries
`[String: Any]` is not `Sendable` because `Any` could contain non-sendable types. By explicitly handling this at the call site, we acknowledge the data race risk and handle it appropriately.

---

## Expected Result

After applying all fixes:
- ✅ 0 errors
- ✅ Swift 6 concurrency compliance
- ✅ Clean build
