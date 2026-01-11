# Plan: Fix http_request failures, add tool timeouts, audit token display

**TL;DR:** The http_request tool runs in-app using URLSession but lacks detailed error logging. App sandbox has network entitlements. We'll add structured telemetry to diagnose failures, add orchestration-level tool timeouts with UI timers and cancellation, and audit token display to distinguish local estimates from provider-reported usage with clear labeling.

## Steps

1. **Instrument http_request with structured logging** in [`HTTPRequestTool.swift`](llmHub/llmHub/Tools/Core/HTTPRequestTool.swift): Add request details (URL, method, headers-redacted, timeout), response fields (status, headers, bytes, preview), and error fields (domain, code, description, underlyingError) to both success/failure paths; verify [`llmHub.entitlements`](llmHub/llmHub.entitlements) has `com.apple.security.network.client`; test with https://example.com

2. **Add orchestration-level timeout in ChatService** ([`ChatService.swift`](llmHub/Services/ChatService.swift) tool execution loop ~line 600): Create `withTimeout(seconds:)` helper that races tool task vs timeout; on timeout cancel Task and return `ToolResult.failure` with `errorClass:.timeout`; ensure loop continues after timeout

3. **Add UI timer in ChatViewModel** ([`ChatViewModel.swift`](llmHub/ViewModels/Core/ChatViewModel.swift)): Add `@Published var toolExecutionElapsedSeconds: [String: Int]` (keyed by toolCallID); update every 1s while `executingToolNames` contains tool; add Cancel button that cancels the running tool Task; display elapsed time and timeout message in [`ToolResultCard.swift`](llmHub/Views/Chat/ToolResultCard.swift)

4. **Audit token counting semantics** across [`TokenEstimator.swift`](llmHub/Services/ContextManagement/TokenEstimator.swift), [`TokenUsageCapsule.swift`](llmHub/Views/Components/TokenUsageCapsule.swift), OpenAI/Anthropic providers: Label local estimates as "Local estimate (for context)"; label provider-reported as "Provider usage (reported)"; ensure OpenAI provider parses `usage` object correctly in Responses API streaming chunks; never show unlabeled counts

5. **Add integration test for http_request** in Tests/: Execute GET https://example.com through ToolExecutor; assert success, 200-399 status, non-empty body; validate entitlements on failure; document ATS diagnostics if cleartext http needed (prefer https-only)

---

## Further Considerations

### 1. Shell tool timeout interaction
Shell already has per-tool timeout logic (line 110-126 in [`ShellTool.swift`](llmHub/llmHub/Tools/Core/ShellTool.swift)). **Decision:** Orchestration timeout = hard deadline (kills task), tool-level timeout = soft advisory (tool-specific cleanup). Orchestration timeout should be >= tool timeout to allow graceful exit.

### 2. Token display location
Current UI shows session-level in [`TokenUsageCapsule.swift`](llmHub/Views/Components/TokenUsageCapsule.swift). **Consider:** Per-message inline badge for turn-level accuracy vs cumulative session cost. Defer to post-audit decision based on provider data availability.

### 3. ATS exceptions
If http_request must support cleartext HTTP for local dev servers, add `NSAppTransportSecurity` exception in [`Info.plist`](llmHub/Info.plist). **Recommendation:** Document justification in code comment; default to https-only for production.

### 4. XPC helper network capabilities
If Step 0 reveals http_request runs in XPC helper, verify helper can make outbound connections (may need `com.apple.security.network.client` AND exit-from-sandbox if helper is sandboxed). Consult Apple docs on XPC + networking.

### 5. Timeout configuration
Hard-code timeout values initially (http_request: 120s, shell: 120s, orchestration: 300s). Consider making configurable per-tool in future if needed.

---

## Debugging Checklist

- [ ] Run `codesign -d --entitlements :- <binary>` on app and helper to verify `com.apple.security.network.client`
- [ ] Use `nscurl --ats-diagnostics <url>` to diagnose ATS blocking causes
- [ ] Log OSStatus / NSURLErrorDomain codes verbatim (don't translate to generic strings)
- [ ] Check Console.app for sandbox violation messages during http_request execution
- [ ] Verify URLSessionTask.cancel() actually called when timeout fires (breakpoint or log)
- [ ] Test with intentionally slow endpoint (e.g., `httpbin.org/delay/10`) to validate timeout behavior

---

## Technical Note Template

After implementation, document in `Docs/`:

**Filename:** `http_request_diagnostics_and_timeouts.md`

**Contents:**
- Root cause of http_request failures (entitlement/ATS/DNS/TLS)
- Which binary executes network calls (app vs helper)
- Timeout design (orchestration vs per-tool)
- Cancellation guarantees per tool type
- Token display contract (provider vs estimator)
- Before/after console excerpts
- Screenshots of timeout UI (elapsed timer, cancel button)
- Test results (unit + smoke)
