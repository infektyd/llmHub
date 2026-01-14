# llmHub View → File Map

**Last Updated:** January 2026  
**Purpose:** Quick reference for "I see this on screen → which file do I edit?"

---

## 🗺️ Visual Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        llmHubApp.swift (entry point)                    │
│                               ↓                                         │
│                        ContentView.swift (wrapper)                      │
│                               ↓                                         │
│                     CanvasRootView (RootView.swift)                     │
│    ┌──────────────────────┼─────────────────────────────────────┐      │
│    │                      │                                      │      │
│    ▼                      ▼                                      ▼      │
│ SIDEBAR              MAIN CONTENT                          INSPECTOR    │
│ ModernSidebarLeft    TranscriptCanvasView                   ModernSidebar│
│ .swift               (TranscriptView.swift)                 Right.swift  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📱 Platform Layouts

### macOS: 3-Column Layout
```
┌─────────────┬──────────────────────────────┬────────────────────┐
│   SIDEBAR   │         CHAT AREA            │    INSPECTOR       │
│             │                              │   (optional)       │
│ Modern-     │  ChatHeaderBar (top)         │  ModernSidebar-    │
│ SidebarLeft │  TranscriptCanvasView        │  Right             │
│ .swift      │  Composer (bottom)           │  .swift            │
└─────────────┴──────────────────────────────┴────────────────────┘
```

### iOS: NavigationSplitView
```
┌─────────────────────┐     ┌──────────────────────────┐
│      SIDEBAR        │ ──▶ │     CHAT DETAIL          │
│                     │     │                          │
│ ModernSidebarLeft   │     │  CanvasRootView          │
│ .swift              │     │  (Transcript + Composer) │
└─────────────────────┘     └──────────────────────────┘
```

---

## 🎯 Quick Reference: What You See → Which File

### Main Window Structure

| What You See | File | Path |
|-------------|------|------|
| **App entry point** | `llmHubApp.swift` | `llmHub/App/` |
| **Root view wrapper** | `ContentView.swift` | `llmHub/Views/` |
| **Main layout (Canvas)** | `RootView.swift` | `llmHub/Views/UI/` |

### Sidebar (Left Panel)

| What You See | File | Path |
|-------------|------|------|
| **Entire sidebar** | `ModernSidebarLeft.swift` | `llmHub/Views/UI/Sidebars/` |
| **Session rows / grouping** | `ModernSidebarLeft.swift` | `llmHub/Views/UI/Sidebars/` |
| **"New Chat" button** | `ModernSidebarLeft.swift` | `llmHub/Views/UI/Sidebars/` |
| **Search bar** | `ModernSidebarLeft.swift` | `llmHub/Views/UI/Sidebars/` |

### Chat Area (Center)

| What You See | File | Path |
|-------------|------|------|
| **Transcript surface** | `TranscriptView.swift` | `llmHub/Views/UI/` |
| **Message rows** | `MessageRow.swift` | `llmHub/Views/UI/Transcript/` |
| **Message content (Markdown)** | `MessageContent.swift` | `llmHub/Views/UI/Transcript/` |
| **Tool result artifacts** | `ArtifactCardView.swift` | `llmHub/Views/UI/Transcript/` |
| **Header toolbar** | `ChatHeaderBar.swift` | `llmHub/Views/UI/Header/` |
| **Input bar (Composer)** | `Composer.swift` | `llmHub/Views/UI/Composer/` |

### Model Picker

| What You See | File | Path |
|-------------|------|------|
| **Model picker sheet** | `ModelPickerSheet.swift` | `llmHub/Views/UI/Header/` |
| **Picker trigger** | `ChatHeaderBar.swift` | `llmHub/Views/UI/Header/` |

### Tool Inspector (Right Panel)

| What You See | File | Path |
|-------------|------|------|
| **Inspector panel + tool toggles** | `ModernSidebarRight.swift` | `llmHub/Views/UI/Sidebars/` |

### Settings

| What You See | File | Path |
|-------------|------|------|
| **Settings window/sheet** | `SettingsView.swift` | `llmHub/Views/Settings/` |
| **Appearance tab** | `SettingsView.swift` (`AppearanceSection`) | `llmHub/Views/Settings/` |
| **Tools tab** | `SettingsView.swift` (`ToolsSection`) | `llmHub/Views/Settings/` |

### File Operations

| What You See | File | Path |
|-------------|------|------|
| **File approval dialog** | `FileOperationApprovalView.swift` | `llmHub/Views/Components/System/` |

### Artifacts

| What You See | File | Path |
|-------------|------|------|
| **Artifact cards** | `ArtifactCardView.swift` | `llmHub/Views/UI/Transcript/` |
| **Artifact library list** | `ArtifactLibraryView.swift` | `llmHub/Views/Components/Artifacts/` |
| **Artifact detail view** | `ArtifactDetailView.swift` | `llmHub/Views/UI/Artifacts/` |

### System / Diagnostics

| What You See | File | Path |
|-------------|------|------|
| **AFM diagnostics (debug)** | `AFMDiagnosticsView.swift` | `llmHub/Views/Components/System/` |
| **Terminal output** | `TerminalOutputView.swift` | `llmHub/Views/Components/System/` |

### Canvas Theme Components

| What You See | File | Path |
|-------------|------|------|
| **Color tokens** | `AppColors.swift` | `llmHub/Utilities/UI/` |
| **Appearance helpers** | `UIAppearance.swift` | `llmHub/Utilities/UI/` |

---

## 🧩 ViewModels (State Management)

| ViewModel | Manages State For | Path |
|-----------|------------------|------|
| `ChatViewModel` | Chat messages, streaming, tool toggles | `llmHub/ViewModels/Core/` |
| `WorkbenchViewModel` | Window layout, tool inspector visibility | `llmHub/ViewModels/Features/` |
| `SidebarViewModel` | Sidebar grouping, search, selection | `llmHub/ViewModels/Features/` |
| `SettingsViewModel` | Settings tabs, API key management | `llmHub/ViewModels/Features/` |
| `ModelFavoritesManager` | Favorite models persistence | `llmHub/ViewModels/Managers/` |

---

## 📁 Full Views Directory Tree

```
llmHub/Views/
├── Components/
│   ├── Artifacts/
│   │   ├── ArtifactCard.swift
│   │   ├── ArtifactLibraryView.swift
│   │   ├── ArtifactPreviewChip.swift
│   │   └── AttachmentPreviewChip.swift
│   ├── Chat/
│   │   ├── AgentStepLimitConfigSheet.swift
│   │   └── MemoryIndicatorView.swift
│   └── System/
│       ├── AFMDiagnosticsView.swift
│       ├── FileOperationApprovalView.swift
│       └── TerminalOutputView.swift
├── Settings/
│   ├── AdvancedSettingsView.swift
│   ├── MemoryViewerView.swift
│   └── SettingsView.swift
├── UI/
│   ├── Artifacts/
│   │   ├── ArtifactDetailView.swift
│   │   └── OpenArtifactDetailAction.swift
│   ├── Composer/
│   │   └── Composer.swift
│   ├── Header/
│   │   ├── ChatHeaderBar.swift
│   │   └── ModelPickerSheet.swift
│   ├── Previews/
│   │   ├── Fixtures.swift
│   │   └── PreviewHelpers.swift
│   ├── RootView.swift
│   ├── Sidebars/
│   │   ├── ModernSidebarLeft.swift
│   │   └── ModernSidebarRight.swift
│   ├── Transcript/
│   │   ├── ArtifactCardView.swift
│   │   ├── ImageCache.swift
│   │   ├── ImageLoader.swift
│   │   ├── ImageResolver.swift
│   │   ├── MessageContent.swift
│   │   ├── MessageRow.swift
│   │   └── Models.swift
│   └── TranscriptView.swift
└── ContentView.swift
```
