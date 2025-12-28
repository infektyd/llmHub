# HTTP Request Diagnostics and Tool Timeouts

**Date:** December 15, 2025  
**Status:** Implemented (Steps 0-3 complete, Step 4-5 in progress)

## Summary

This document details the implementation of structured telemetry for the `http_request` tool, orchestration-level timeouts for all tools, and throttled UI timers to prevent perceived freezing during long-running tool operations.

## Step 0: Execution Environment Verification

### Findings

**Execution Context:**
- http_request executes in the **main app process** (using `URLSession.shared`)
- Bundle ID: `com.syntra.llmHub` (or similar, logged at runtime)
- Process: `llmHub` (main app, not XPC helper)

**Entitlements Verification:**
- **Main App** (`llmHub.entitlements`):
  - ✅ `com.apple.security.app-sandbox`: `true`
  - ✅ `com.apple.security.network.client`: `true`
  - ✅ `com.apple.security.network.server`: `true`
  
- **XPC Helper** (`llmHubHelper.entitlements`):
  - `com.apple.security.app-sandbox`: `false` (not sandboxed)
  - No explicit network entitlements (not needed as it's unsandboxed)

**Conclusion:**  
The app has correct network entitlements. http_request runs in-app, so it has access to outbound network connections. If failures occur, they're likely due to:
1. DNS/connectivity issues
2. ATS blocking cleartext HTTP
3. URLSession timeout/error handling

## Step 1: Structured Telemetry

### Changes to `HTTPRequestTool.swift`

**Added Logging:**
1. **Execution context** (at start):
   ```swift
   let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
   let processName = ProcessInfo.processInfo.processName
   let pid = ProcessInfo.processInfo.processIdentifier
   context.logger.info("🌐 http_request executing in: \(bundleID) (process: \(processName), PID: \(pid))")
   ```

2. **Request details** (redacted headers):
   ```swift
   let redactedHeaders = resolvedHeaders.mapValues { value in
       return value.contains("Bearer") || value.contains("Basic") ? "[REDACTED]" : value
   }
   context.logger.info("📤 Request: \(method) \(urlString), timeout: \(timeout)s, headers: \(redactedHeaders)")
   ```

3. **Response details** (success):
   ```swift
   context.logger.info("📥 Response: \(httpResponse.statusCode), bytes: \(data.count), url: \(httpResponse.url?.absoluteString ?? urlString)")
   ```

4. **Error details** (failure):
   ```swift
   let errorDomain = (error as NSError).domain
   let errorCode = (error as NSError).code
   let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
   context.logger.error("❌ URLError: domain=\(errorDomain), code=\(errorCode), description=\(error.localizedDescription)")
   if let underlying = underlyingError {
       context.logger.error("  Underlying: domain=\(underlying.domain), code=\(underlying.code)")
   }
   ```

5. **ATS diagnostics**:
   ```swift
   if error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
       context.logger.error("⚠️ ATS blocked cleartext HTTP. Use https:// or run: nscurl --ats-diagnostics \(urlString)")
   }
   ```

6. **Cancellation support**:
   ```swift
   let (data, response) = try await withTaskCancellationHandler {
       try await httpSession.data(for: request)
   } onCancel: {
       Task {
           httpSession.getAllTasks { tasks in
               tasks.forEach { $0.cancel() }
           }
       }
   }
   ```

**Metadata Enhancement:**
- Added `bytesReceived` to success metadata
- Added `process` (bundle ID) to success metadata
- Structured failure messages include domain/code/URL

## Step 2: Orchestration-Level Timeouts

### Changes to `ToolExecutor.swift`

**Timeout Wrapper:**
```swift
private func withTimeout<T>(
    seconds: Int,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw ToolError.timeout(after: TimeInterval(seconds))
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

**Applied to Tool Execution:**
```swift
let timeoutSeconds = 300  // Hard deadline: 5 minutes
let result = try await withTimeout(seconds: timeoutSeconds) {
    try await tool.execute(arguments: arguments, context: context)
}
```

**Timeout Handling:**
```swift
if case .timeout(let duration) = error {
    metrics.errorClass = .timeout
    logger.error("⏱️ \(call.name) timed out after \(duration)s")
    let timeoutMessage = "Tool execution timed out after \(duration) seconds. The operation was cancelled."
    return ToolCallResult(
        id: call.id,
        toolName: call.name,
        result: .failure(timeoutMessage, metrics: metrics, errorClass: .timeout)
    )
}
```

**Behavior:**
- Timeout cancels the Task running the tool
- Agent loop continues after timeout (doesn't break/throw)
- Timeout result is returned as a structured failure

**Cancellation Per Tool:**
- `http_request`: Cancels URLSessionTask via `withTaskCancellationHandler`
- `shell`: Already has per-tool timeout (30-120s), orchestration timeout (300s) acts as hard deadline
- Other tools: Cancellation is cooperative (Task cancellation propagates)

## Step 3: UI Timer with Throttled Updates

### Changes to `ChatViewModel.swift`

**State Properties:**
```swift
/// STEP 3: Elapsed seconds for each running tool (keyed by toolCallID)
var toolExecutionElapsedSeconds: [String: Int] = [:]

/// STEP 3: Cancel handlers for running tools (keyed by toolCallID)
var toolExecutionCancelHandlers: [String: () -> Void] = [:]

/// STEP 3: Timer for updating elapsed time (1 Hz)
private var toolTimerTask: Task<Void, Never>?
```

**Timer Management:**
```swift
func startToolTimer(toolCallID: String, cancelHandler: @escaping () -> Void) {
    toolExecutionElapsedSeconds[toolCallID] = 0
    toolExecutionCancelHandlers[toolCallID] = cancelHandler
    
    if toolTimerTask == nil || toolTimerTask?.isCancelled == true {
        toolTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Update all active tool timers (throttled to 1 Hz)
                for toolCallID in toolExecutionElapsedSeconds.keys {
                    toolExecutionElapsedSeconds[toolCallID, default: 0] += 1
                }
            }
        }
    }
}

func stopToolTimer(toolCallID: String) {
    toolExecutionElapsedSeconds.removeValue(forKey: toolCallID)
    toolExecutionCancelHandlers.removeValue(forKey: toolCallID)
    
    if toolExecutionElapsedSeconds.isEmpty {
        toolTimerTask?.cancel()
        toolTimerTask = nil
    }
}

func cancelToolExecution(toolCallID: String) {
    if let cancelHandler = toolExecutionCancelHandlers[toolCallID] {
        cancelHandler()
        stopToolTimer(toolCallID: toolCallID)
    }
}
```

**Update Throttling:**
- Updates occur at **1 Hz only** (1-second intervals)
- Updates only active tools (no unnecessary state changes)
- Timer task automatically stops when no tools are running
- All updates are MainActor-bound to prevent "multiple times per frame" errors

## Configuration

**Timeout Values:**
- Orchestration timeout: **300s** (5 minutes) - hard deadline for all tools
- http_request tool-level timeout: **30-120s** (configurable per request)
- shell tool-level timeout: **30-120s** (configurable per command)

**Timeout Hierarchy:**
- Orchestration timeout >= tool-level timeout (ensures graceful exit)
- Tool-level timeout: soft advisory (tool-specific cleanup)
- Orchestration timeout: hard deadline (kills task)

## Testing Checklist

- [ ] http_request logs execution context (bundle ID, process, PID)
- [ ] http_request logs redacted request headers
- [ ] http_request logs response details (status, bytes)
- [ ] http_request logs structured errors (domain, code, description)
- [ ] ATS diagnostic message appears for cleartext HTTP
- [ ] Cancellation handler fires when Task is cancelled
- [ ] Tool execution times out after 300s
- [ ] Timeout doesn't block agent loop
- [ ] UI timer updates at 1 Hz (not per-frame)
- [ ] Timer stops when all tools complete
- [ ] Cancel button works and doesn't corrupt state

## Next Steps (In Progress)

### Step 4: Token Audit
- Add "Provider usage (reported)" vs "Local estimate (for context)" labels
- Ensure OpenAI provider correctly parses `usage` object
- Never show unlabeled token counts
- Document token contract in code

### Step 5: Integration Tests
- Unit tests: URLProtocol mocking for deterministic telemetry validation
- Smoke test: Real HTTPS GET to https://example.com (behind flag)
- Validate entitlements on failure

## Known Issues

None at this time.

## References

- Plan: `/Users/hansaxelsson/llmHub/plan-httpRequestToolTimeoutsTokenAudit.prompt.md`
- Apple ATS Diagnostics: `nscurl --ats-diagnostics <url>`
- Entitlement verification: `codesign -d --entitlements :- <binary>`
