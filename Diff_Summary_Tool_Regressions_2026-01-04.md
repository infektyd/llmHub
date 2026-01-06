# Diff Summary — Tool Regressions (2026-01-04)

This summary covers the working tree changes related to:
- `web_search` schema validation accepting numeric strings for `num_results`
- `shell` tool ~30s stall fix for trivial commands
- Regression tests for both

## Status
- Unit tests passed (llmHubTests only):
  - `xcodebuild test -project llmHub.xcodeproj -scheme llmHub -destination 'platform=macOS' -only-testing:llmHubTests`

## Changed Files (tracked)
- llmHub.xcodeproj/project.pbxproj
- llmHub/Services/Tools/Execution/ToolExecutor.swift
- llmHub/Tools/ShellSession.swift
- llmHub/Tools/ShellTool.swift
- llmHub/Tools/WebSearchTool.swift

## Added Files (untracked / new)
- Tests/llmHubTests/ToolRegressionTests.swift

## Diffstat (tracked)
```text
5 files changed, 68 insertions(+), 28 deletions(-)

 llmHub.xcodeproj/project.pbxproj                   |  2 ++
 llmHub/Services/Tools/Execution/ToolExecutor.swift |  7 +++++++
 llmHub/Tools/ShellSession.swift                    | 43 +++++++++++++++++++++++++++---------------
 llmHub/Tools/ShellTool.swift                       | 42 +++++++++++++++++++++++++++++------------
 llmHub/Tools/WebSearchTool.swift                   |  2 +-
```

## What Changed

### Tool schema validation: accept numeric strings
- Location: `llmHub/Services/Tools/Execution/ToolExecutor.swift`
- Change: Schema matching now accepts numeric strings for:
  - `.number` if `Double(trimmedString)` parses
  - `.integer` if either `Int(trimmedString)` parses **or** `Double(trimmedString)` parses to an integer-valued double (e.g. `"2.0"`).
- Intent: Prevent early schema-validation rejection when a model emits numbers as JSON strings.

### WebSearch: clamp `num_results`
- Location: `llmHub/Tools/WebSearchTool.swift`
- Change: Clamp to `1...10` (instead of only enforcing the upper bound).

### Shell: avoid hangs/timeouts by draining pipes concurrently
- Locations:
  - `llmHub/Tools/ShellTool.swift`
  - `llmHub/Tools/ShellSession.swift`
- Changes:
  - Invoke zsh as ` /bin/zsh -f -c <command>` to avoid login/startup file overhead.
  - Close parent-side pipe write handles after `process.run()`.
  - Drain stdout/stderr concurrently (tasks reading `readToEnd()`) while waiting for `waitUntilExit()`, preventing pipe-buffer deadlocks.

### Tests: regressions
- Location: `Tests/llmHubTests/ToolRegressionTests.swift` (untracked/new)
- Covers:
  - `web_search` accepts `"num_results":"2"` and `"2.0"`
  - `web_search` rejects `"num_results":"2.5"`
  - `shell` echo completes quickly and returns stdout

