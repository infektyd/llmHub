# Previews (Xcode Canvas) Diagnostics

## Opening Canvas

1. Open any SwiftUI file (e.g. `llmHub/Views/Canvas2/CanvasRootView.swift`).
2. Enable Canvas:
   - Xcode menu: `Editor > Canvas`
3. Choose a preview variant from the `#Preview("…")` blocks at the bottom of the file.

## Preview crash/failure report

If a preview fails to render:

1. Open Canvas diagnostics:
   - `Editor > Canvas > Diagnostics > Generate Report`
2. Inspect the report for:
   - Missing environment (`ModelContainer`, `EnvironmentObject`, etc.)
   - SwiftData model/container failures
   - Runtime-only work being triggered in preview

## Preview safety rules used in llmHub

- **Preview detection**: `PreviewMode.isRunning` uses:\n  `ProcessInfo.processInfo.environment[\"XCODE_RUNNING_FOR_PREVIEWS\"] == \"1\"`\n- **Preview gating**: runtime-only work must be skipped in previews, including:\n  - Provider initialization\n  - Network calls\n  - Tool execution\n  - Long-running timers\n  - Heavy SwiftData reads/writes\n+
Common places to add guards:

- `.task {}` and `.onAppear {}` blocks
- ViewModel service initialization entry points
- Async loaders (e.g. remote images)

