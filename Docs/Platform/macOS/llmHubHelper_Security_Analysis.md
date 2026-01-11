# llmHubHelper Implementation Analysis

## Overview
The llmHubHelper is a macOS XPC (Inter-Process Communication) service that runs **outside the main app sandbox** to execute code in various programming languages. It bridges the sandboxed main app with system interpreters.

---

## 1. SUPPORTED LANGUAGES

The system supports **5 programming languages**:

1. **Swift**
   - Interpreters: `swift`
   - File extension: `.swift`
   - Execution: Direct script execution

2. **Python**
   - Interpreters: `python3`, `python` (in that order)
   - File extension: `.py`
   - Execution: With `-u` flag for unbuffered output

3. **JavaScript**
   - Interpreters: `node`, `nodejs`
   - File extension: `.js`
   - Execution: Direct script execution

4. **TypeScript**
   - Interpreters: `ts-node`, `npx` (fallback)
   - File extension: `.ts`
   - Execution: Via `ts-node` or `npx ts-node`

5. **Dart**
   - Interpreters: `dart`
   - File extension: `.dart`
   - Execution: Via `dart run` command

**Language Detection:**
- The system provides methods to detect language from file extension
- Extensions can be with or without leading dot: `.py` or `py`

---

## 2. IMPORT RESTRICTIONS & BLOCKED MODULES

### Current Status: **NO MODULE BLOCKING**

**Critical Finding:** There are **NO import restrictions or blocked module lists** implemented.

This means:
- Users can import ANY library/module available on the system
- Python scripts can use `os`, `subprocess`, `socket`, `requests`, etc.
- JavaScript/Node can require any npm package
- **No whitelist or blacklist of modules**
- **No code scanning for dangerous imports**

### Security Implications:
- Python: Can execute system commands via `os.system()`, `subprocess`, access files
- JavaScript/Node: Can access filesystem, environment variables, execute child processes
- All languages: Full access to interpreter capabilities and system resources

---

## 3. ENTITLEMENTS & SANDBOX CONFIGURATION

### llmHubHelper Entitlements (`llmHubHelper.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

**Key Configuration:**
- `com.apple.security.app-sandbox = false` → **NOT sandboxed**
- XPC helper runs with **FULL system access**
- Can access all system interpreters, libraries, and files
- No file path restrictions
- No network restrictions
- No environment restrictions

### Architecture:
1. **Main App** (sandboxed) → uses XPC to communicate with helper
2. **llmHubHelper XPC Service** (NOT sandboxed) → executes code

This design allows the sandboxed main app to execute code by delegating to an unrestricted helper process.

---

## 4. EXECUTION FLOW & SECURITY MEASURES

### Process Execution Flow:

1. **Interpreter Discovery** (`findInterpreter`)
   - Uses `which` command to locate interpreter
   - Results cached for performance
   - Caches maintained in memory (per app launch)

2. **Code File Creation**
   - Written to temporary directory: `/var/tmp/llmHub-helper/<UUID>/main<ext>`
   - File permissions set to `0o700` (owner read/write/execute only)
   - Automatically cleaned up after 5 seconds

3. **Process Execution**
   - Uses Swift's `Process` class
   - Launches interpreter with code file as argument
   - Configurable timeout (passed by caller)
   - Pipes stdout and stderr

4. **Timeout Handling**
   - Process is terminated with `SIGTERM` if timeout exceeded
   - Timeout checked via `terminationReason == .uncaughtSignal && status == SIGTERM`

5. **Output Handling**
   - Stdout and stderr captured and returned
   - Exit code preserved
   - Execution time measured

### Current Security Measures:
- File permissions: `0o700` (restrictive)
- Automatic temp cleanup: 5 seconds after execution
- Timeout enforcement: kills runaway processes
- No home directory access in sandbox mode

---

## 5. SANDBOX MODE IMPLEMENTATION

### SandboxManager Features:

**Creating Sandboxed Execution:**
```swift
// When securityMode == .sandbox
workingDirectory = try await sandboxManager.createSandbox(for: request.id)
```

**Sandbox Properties:**
- Base directory: `/var/tmp/llmHub-sandbox/<UUID>/`
- Permissions: `0o700` (owner only)
- Isolated from main temp directory

**Environment Variable Restrictions:**
```swift
HOME = <sandbox_path>
TMPDIR = <sandbox_path>
XDG_CACHE_HOME = <sandbox_path>

// Removed:
SSH_AUTH_SOCK      // SSH key access
GPG_AGENT_INFO     // GPG key access
```

**Output File Handling:**
- Can capture generated files (images, json, text, etc.)
- File extensions monitored: `["png", "jpg", "jpeg", "gif", "svg", "json", "txt"]`
- Auto-cleanup after execution

**Limitations of Sandbox Mode:**
- Execution still happens in **non-sandboxed XPC helper**
- Helper can theoretically access any file on system
- Home/TMPDIR restrictions only affect child environment variables
- Code can still use absolute paths to access system files

---

## 6. KNOWN ISSUES & SECURITY CONCERNS

### Security Concerns (Critical):

1. **NO CODE VALIDATION**
   - Code is executed as-is without analysis
   - No malicious pattern detection
   - No dangerous function detection

2. **FULL SYSTEM ACCESS IN HELPER**
   - XPC helper not sandboxed (app-sandbox=false)
   - Can access any file, run any command
   - No restrictions on subprocess execution
   - Can modify user's home directory, system files, etc.

3. **NO MODULE/IMPORT RESTRICTIONS**
   - Python: Can import `os`, `subprocess`, run shell commands
   - JavaScript: Full Node.js access including `require('child_process')`
   - All interpreters: Full access to their capabilities

4. **ENVIRONMENT EXPOSURE**
   - All parent process environment variables inherited
   - Could expose: credentials, API keys, SSH keys (if not removed)
   - Sandbox mode removes SSH_AUTH_SOCK and GPG_AGENT_INFO, but others remain

5. **XPC SERVICE NAME EXPOSURE**
   - Service identifier: `"Syntra.llmHub.CodeExecutionHelper"`
   - Available to all processes on system
   - Any process could potentially connect to it

6. **TIMEOUT AS ONLY RUNAWAY CONTROL**
   - Infinite loops are only stopped by timeout
   - Default timeout: 30 seconds (user-configurable)
   - Resource exhaustion (memory, CPU) not limited

7. **TEMPORARY FILE CLEANUP DELAY**
   - 5-second delay before cleanup
   - Temp files readable during this window
   - Could be exploited if timing is controlled

### Known TODOs/Limitations:

- **REPL Support**: Not implemented (placeholder returns error)
- **Remote Execution**: iOS/iPadOS would need separate remote API (not implemented)
- **No Static Analysis**: No code scanning or pattern validation
- **No Capability Restrictions**: No syscall filtering or capability dropping

---

## 7. CAN IT RUN ARBITRARY CODE?

### **YES - UNRESTRICTED**

**Summary:**
- ✅ Can run ANY code in supported languages
- ✅ Full access to system interpreters and their capabilities
- ✅ Can execute arbitrary commands (via `os.system()`, `subprocess`, etc.)
- ✅ Can read/write any file accessible to the user
- ✅ Can make network connections
- ✅ Can spawn child processes
- ✅ Can access environment variables
- ✅ No whitelist - all code is executed

**Trust Model:**
- System relies on **user trust** - if user copies code into UI, it runs
- No approval mechanism (approval mode just requires user confirmation)
- Approval mode = user says "yes, execute this"

**Attack Scenarios:**
1. User copies malicious Python code → executes `os.system("rm -rf ~")`
2. User executes JavaScript → accesses environment variables with API keys
3. Malicious prompt injection → LLM generates harmful code → executes

---

## 8. XPC PROTOCOL & DATA FLOW

### XPC Interface Definition:

```swift
protocol CodeExecutionXPCProtocol {
    func executeCode(
        _ code: String,
        language: String,
        timeout: Int,
        workingDirectory: String?,
        reply: @escaping (Data?, Error?) -> Void
    )
    
    func checkInterpreter(
        _ language: String,
        reply: @escaping (String?, String?, Error?) -> Void
    )
    
    func getVersion(reply: @escaping (String) -> Void)
    func ping(reply: @escaping (Bool) -> Void)
}
```

### Data Types:

**XPCExecutionResult:**
```swift
struct XPCExecutionResult: Codable {
    let id: String              // UUID of execution
    let language: String        // Language identifier
    let stdout: String          // Process output
    let stderr: String          // Process errors
    let exitCode: Int32         // Process exit code
    let executionTimeMs: Int    // Execution duration
    let interpreterPath: String?// Path to interpreter used
}
```

**Errors:**
- `interpreterNotFound(String)` - Language not available
- `timeout(Int)` - Execution exceeded timeout
- `processLaunchFailed(String)` - Failed to start process
- `invalidLanguage(String)` - Unsupported language
- `fileWriteFailed(String)` - Couldn't write code file
- `connectionFailed` - XPC connection issue
- `invalidResponse` - Bad response format

---

## 9. ARCHITECTURE SUMMARY

```
Main App (Sandboxed)
    ↓ (XPC)
XPCExecutionBackend (Sandboxed)
    ↓ (XPC IPC)
llmHubHelper (NOT Sandboxed)
    ↓ (Process::run)
System Interpreter (python3, node, swift, etc.)
    ↓
Returns stdout/stderr to app
```

### Security Boundary:
- **Sandbox boundary:** Between main app and XPC helper
- **No security boundary:** Between XPC helper and interpreter
- **Actual execution:** In native interpreter with full system access

---

## 10. RECOMMENDATIONS

### High Priority Issues:

1. **Implement Code Analysis**
   - Scan for dangerous imports/modules
   - Detect suspicious patterns
   - Warn before executing dangerous code

2. **Separate File Access Control**
   - Even in sandbox mode, restrict file access
   - Implement path whitelisting for file operations
   - Block access to sensitive directories (~/.ssh, ~/.gnupg, etc.)

3. **Environment Variable Filtering**
   - Remove sensitive vars: AWS_*, GITHUB_*, GOOGLE_*, etc.
   - Whitelist only necessary env vars
   - Document which vars are available

4. **Subprocess Restrictions**
   - Consider blocking subprocess execution entirely
   - Or whitelist specific commands
   - Prevent shell injection attacks

5. **Resource Limits**
   - Add memory limits (not just timeout)
   - Add CPU limits
   - Add file descriptor limits

6. **Capability Dropping**
   - Drop capabilities on sandboxed processes
   - Use seccomp-style filtering if available on macOS

7. **Approval Mechanism**
   - Current "approval mode" only requires user confirmation
   - Implement proper approval flow with code review
   - Show what interpreter/libraries will be used

---

## Summary Table

| Aspect | Status | Details |
|--------|--------|---------|
| **Languages** | 5 supported | Swift, Python, JavaScript, TypeScript, Dart |
| **Module Blocking** | None | Can import ANY module |
| **Sandbox** | Partial | Main app sandboxed, helper not |
| **Arbitrary Code** | Yes | Full execution allowed |
| **Code Validation** | None | No analysis or scanning |
| **Timeout Control** | Yes | Configurable per execution |
| **File Access** | Unrestricted | Can read/write any user file |
| **Network Access** | Unrestricted | Full internet access |
| **Environment** | Partially filtered | SSH/GPG removed in sandbox mode |
| **Resource Limits** | Timeout only | No memory/CPU limits |
| **Trust Model** | User trust | User confirms execution in approval mode |

