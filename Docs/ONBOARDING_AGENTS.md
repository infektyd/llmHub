# Agent Onboarding & Context Protocol

> **READ THIS FIRST**: This document defines the operational parameters, constraints, and state for any AI agent working on the `llmHub` codebase.

**Current Date**: January 2026
**Project Phase**: Optimization & Feature Complete (Maintenance Mode for Core, Active Dev for Features).

---

## 🛑 Critical Directives (Non-Negotiable)

1.  **Liquid Glass UI Only**:

    - **NEVER** use opaque materials, standard lists, or default backgrounds.
    - **ALWAYS** use `.glassEffect()` from `LiquidGlassTokens`.
    - **ALWAYS** respect `LiquidGlassTokens.Spacing` and `Radius`.
    - The UI must look translucent, futuristic, and premium ("Wow" factor).

2.  **Swift 6 Strict Concurrency**:

    - All UI components (Views, ViewModels) **MUST** be `@MainActor`.
    - Services and Providers are typically `actor` or `@MainActor`.
    - Use `Task { @MainActor in }` or `MainActor.run` when hopping back to UI.
    - Avoid `nonisolated` unless strictly necessary for protocol compliance.

3.  **Platform Awareness**:

    - The codebase supports **macOS** and **iOS** in a single target.
    - Use `#if os(macOS)` and `#if os(iOS)` for platform-divergent code.
    - **iOS Restrictions**: No XPC service access, no `Process`, restricted file access.
    - **macOS Features**: `llmHubHelper` (XPC), Window management, Menu bar.

4.  **No Legacy Tools**:
    - **Aider** artifacts (`.aider*`) have been **permanently removed**. Do not attempt to restore them.
    - **Gemini** documentation (`.gemini/`) has been removed. Do not reference it.

---

## 📂 Project Structure Map

**Root**: `/Users/hansaxelsson/llmHub`

| Directory           | Purpose                         | Agent Action   |
| :------------------ | :------------------------------ | :------------- |
| `llmHub/`           | **Main App Source**             | **READ/WRITE** |
| ├── `App/`          | App entry point (@main)         | Monitor        |
| ├── `Views/`        | SwiftUI Views (Glass, Canvas)   | **Active Dev** |
| │   └── `Components/` | Reusable UI (Artifacts/System/Chat) | **Active Dev** |
| ├── `ViewModels/`   | UI Logic & State                | **Active Dev** |
| │   ├── `Core/`     | ChatViewModel & interactions    | **Active Dev** |
| │   ├── `Features/` | Sidebar, Workbench, Settings    | **Active Dev** |
| │   ├── `Managers/` | Favorites, preferences          | Maintain       |
| │   └── `Models/`   | UI data structures              | **Active Dev** |
| ├── `Services/`     | Business logic (Chat, Tools)    | Maintain       |
| │   └── `Support/`  | Cross-cutting services (settings, registries, tracing) | Maintain |
| ├── `Providers/`    | LLM API Wrappers                | Maintain       |
| │   └── `Shared/`   | Provider-agnostic protocol/config | Maintain     |
| ├── `Tools/`        | Tool implementations            | Maintain       |
| ├── `Models/`       | Domain models (Chat, Code, etc) | Caution        |
| │   └── `Shared/`   | Small shared model types        | Caution        |
| `llmHubHelper/`   | **XPC Service (macOS)** | Sandbox Logic  |
| `Docs/`           | **Documentation**       | **READ**       |
| `scritps/`        | Maintenance scripts     | Execute        |
| `Tests/`          | Unit/UI Tests           | Maintain       |

---

## 🧹 Housekeeping Rules

1.  **File Placement**:

    - **Do not** create files in the root. Put them in the appropriate `llmHub/subdir`.
    - If a folder is becoming crowded (e.g., `Views/`), propose sub-organization (like `Views/Sidebar/`).

2.  **Git Disciplines**:

    - **.gitignore** is the source of truth for exclusions.
    - **Archives** (`*.zip`) are ignored. Do not commit large binary blobs.
    - **System Junk** (`.DS_Store`, `.tmp`) is ignored.

3.  **Build Verification**:
    - Always verify with: `xcodebuild -scheme llmHub clean build`
    - If the build fails, **FIX IT** before proceeding. Do not iterate on broken builds.

---

## 🧠 "Brain/Hand/Loop" Architecture Refresher

- **The Brain**: The LLM Provider (`Services/ModelFetch/ModelRegistry.swift` manages them).
- **The Hand**: The Tool System (`llmHub/Tools/`). Tools are strictly typed and sandboxed.
- **The Loop**: `ChatService.swift`. Handles the recursive `Model -> Tool -> Result -> Model` cycle.

---

## 🛠 Active Tools (Jan 2026)

1.  `CalculatorTool`
2.  `CodeInterpreterTool` (macOS XPC)
3.  `FileEditorTool`
4.  `FileReaderTool`
5.  `WebSearchTool`
6.  `ShellTool` (macOS)
7.  ...and others in `llmHub/Tools/`.

---

**End of Briefing.**
