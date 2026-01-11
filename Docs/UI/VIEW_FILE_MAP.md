# llmHub View → File Map

**Last Updated:** December 26, 2025  
**Purpose:** Quick reference for "I see this on screen → which file do I edit?"

---

## 🗺️ Visual Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        llmHubApp.swift (entry point)                    │
│                               ↓                                         │
│                        ContentView.swift (wrapper)                      │
│                               ↓                                         │
│                     NeonWorkbenchWindow.swift                           │
│    ┌──────────────────────┼─────────────────────────────────────┐      │
│    │                      │                                      │      │
│    ▼                      ▼                                      ▼      │
│ SIDEBAR              MAIN CONTENT                          TOOL PANEL   │
│ NeonSidebar.swift    NeonChatView.swift                    NeonTool-    │
│                      (or NeonWelcomeView.swift)            Inspector    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📱 Platform Layouts

### macOS: 3-Column Layout
```
┌─────────────┬──────────────────────────────┬───────────────┐
│   SIDEBAR   │         CHAT AREA            │ TOOL INSPECTOR│
│             │                              │   (optional)  │
│ NeonSidebar │  NeonToolbar (top)           │ NeonTool-     │
│   .swift    │  NeonChatView (messages)     │ Inspector     │
│             │  ChatInputPanel (bottom)     │   .swift      │
└─────────────┴──────────────────────────────┴───────────────┘
```

### iOS: 2-Column Layout (NavigationSplitView)
```
┌─────────────────────┐     ┌─────────────────────┐
│      SIDEBAR        │ ──▶ │     CHAT DETAIL     │
│                     │     │                     │
│   NeonSidebar.swift │     │  NeonChatView.swift │
│                     │     │  (nav bar + chat)   │
└─────────────────────┘     └─────────────────────┘
                                    │
                            (sheet) ▼
                           NeonToolInspector.swift
```

---

## 🎯 Quick Reference: What You See → Which File

### Main Window Structure

| What You See | File | Path |
|-------------|------|------|
| **App entry point** | `llmHubApp.swift` | `llmHub/App/` |
| **Root view wrapper** | `ContentView.swift` | `llmHub/App/` |
| **Main 3-column layout** | `NeonWorkbenchWindow.swift` | `llmHub/Views/Workbench/` |

### Sidebar (Left Panel)

| What You See | File | Path |
|-------------|------|------|
| **Entire sidebar** | `NeonSidebar.swift` | `llmHub/Views/Sidebar/` |
| **Session rows / grouping** | `SidebarComponents.swift` | `llmHub/Views/Sidebar/` |
| **"New Chat" button** | `NeonSidebar.swift` | `llmHub/Views/Sidebar/` |
| **Cleanup banner** | `CleanupBannerView.swift` | `llmHub/Views/Sidebar/` |
| **Cleanup review sheet** | `CleanupReviewSheet.swift` | `llmHub/Views/Sidebar/` |
| **Search bar** | `NeonSidebar.swift` | `llmHub/Views/Sidebar/` |
| **Session grouping picker** | `NeonSidebar.swift` | `llmHub/Views/Sidebar/` |

### Chat Area (Center)

| What You See | File | Path |
|-------------|------|------|
| **Entire chat view** | `NeonChatView.swift` | `llmHub/Views/Chat/` |
| **Top toolbar (macOS)** | `NeonToolbar.swift` | `llmHub/Views/Chat/` |
| **Message list/scroll** | `NeonChatView.swift` | `llmHub/Views/Chat/` |
| **Individual message bubble** | `NeonMessageBubble.swift` | `llmHub/Views/Components/` |
| **Tool result cards** | `ToolResultCard.swift` | `llmHub/Views/Chat/` |
| **Input bar (bottom)** | `ChatInputPanel.swift` | `llmHub/Views/Chat/` |
| **Send button** | `ChatInputPanel.swift` | `llmHub/Views/Chat/` |
| **Tool toggles popup** | `ChatInputPanel.swift` | `llmHub/Views/Chat/` |
| **Attachment strip** | `ChatInputPanel.swift` | `llmHub/Views/Chat/` |
| **"Thinking..." indicator** | `ThinkingIndicatorView.swift` | `llmHub/Views/Components/` |
| **Streaming dots animation** | `NeonMessageBubble.swift` | `llmHub/Views/Components/` |
| **Selectable text** | `SelectableMessageText.swift` | `llmHub/Views/Chat/` |
| **Markdown rendering** | `LiquidMarkdownTheme.swift` | `llmHub/Views/Chat/` |
| **Transcript surface** | `GlassTranscriptSurface.swift` | `llmHub/Views/Chat/` |

### Welcome Screen (No Chat Selected)

| What You See | File | Path |
|-------------|------|------|
| **Welcome view** | `NeonWelcomeView.swift` | `llmHub/Views/Components/` |

### Model Picker

| What You See | File | Path |
|-------------|------|------|
| **Model button in toolbar** | `NeonModelPickerButton.swift` | `llmHub/Views/Components/` |
| **Model picker dropdown** | `NeonModelPicker.swift` | `llmHub/Views/Components/` |
| **Model picker panel** | `NeonModelPickerPanel.swift` | `llmHub/Views/Components/` |
| **Model picker sheet (iOS)** | `NeonModelPickerSheet.swift` | `llmHub/Views/Components/` |

### Tool Inspector (Right Panel)

| What You See | File | Path |
|-------------|------|------|
| **Tool inspector panel** | `NeonToolInspector.swift` | `llmHub/Views/Components/` |
| **Tool icon toggle** | `ToolIconToggle.swift` | `llmHub/Views/Components/` |

### Settings

| What You See | File | Path |
|-------------|------|------|
| **Settings window/sheet** | `SettingsView.swift` | `llmHub/Views/Settings/` |
| **API Keys tab** | `SettingsView.swift` (APIKeysSettingsView) | `llmHub/Views/Settings/` |
| **Appearance tab** | `SettingsView.swift` (AppearanceSettingsView) | `llmHub/Views/Settings/` |
| **General tab** | `SettingsView.swift` (GeneralSettingsView) | `llmHub/Views/Settings/` |

### File Operations

| What You See | File | Path |
|-------------|------|------|
| **File approval dialog** | `FileOperationApprovalView.swift` | `llmHub/Views/` |
| **Approval components** | `Approval/` folder | `llmHub/Views/Approval/` |

### Terminal / Workbench

| What You See | File | Path |
|-------------|------|------|
| **Terminal output** | `TerminalOutputView.swift` | `llmHub/Views/` |
| **Terminal views** | `Terminal/` folder | `llmHub/Views/Terminal/` |

### Glass / Theme Components

| What You See | File | Path |
|-------------|------|------|
| **Glass colors** | `GlassColors.swift` | `llmHub/Views/Components/` |
| **Glass toolbar base** | `GlassToolbar.swift` | `llmHub/Views/Components/` |
| **Liquid Glass tokens** | `LiquidGlassTokens.swift` | `llmHub/Views/Components/` |
| **Adaptive backgrounds** | `AdaptiveGlassBackground.swift` | `llmHub/Views/Components/` |
| **Window background** | `WindowBackgroundStyle.swift` | `llmHub/Views/Components/` |

### Status / Stats

| What You See | File | Path |
|-------------|------|------|
| **Token usage capsule** | `TokenUsageCapsule.swift` | `llmHub/Views/Components/` |
| **Streaming stats** | `StreamingStatsCapsule.swift` | `llmHub/Views/Components/` |
| **Status bar (bottom)** | `NeonWorkbenchWindow.swift` | `llmHub/Views/Workbench/` |

### Debug / Diagnostics

| What You See | File | Path |
|-------------|------|------|
| **Tools debug sheet** | `ToolsAvailableDebugSheet.swift` | `llmHub/Views/Chat/` |
| **AFM diagnostics** | `AFMDiagnosticsView.swift` | `llmHub/Views/Components/` |

### Artifacts

| What You See | File | Path |
|-------------|------|------|
| **Artifact cards** | `ArtifactCard.swift` | `llmHub/Views/Components/` |

---

## 🧩 ViewModels (State Management)

| ViewModel | Manages State For | Path |
|-----------|------------------|------|
| `ChatViewModel` | Chat messages, streaming, tool toggles | `llmHub/ViewModels/Core/` |
| `WorkbenchViewModel` | Window layout, tool inspector, selected session | `llmHub/ViewModels/Features/` |
| `SidebarViewModel` | Sidebar grouping, search, selection | `llmHub/ViewModels/Features/` |
| `SettingsViewModel` | Settings tabs, API key management | `llmHub/ViewModels/Features/` |
| `ModelFavoritesManager` | Favorite models persistence | `llmHub/ViewModels/Managers/` |
| `ChatInteractionController` | Input handling, sending messages | `llmHub/ViewModels/Core/` |

---

## 📁 Full Views Directory Tree

```
llmHub/Views/
├── Approval/                    # File operation approval dialogs
├── Chat/
│   ├── ChatInputPanel.swift     # Bottom input bar
│   ├── GlassTranscriptSurface.swift
│   ├── LiquidMarkdownTheme.swift
│   ├── NeonChatView.swift       # ⭐ Main chat view
│   ├── NeonMessageRow.swift
│   ├── NeonToolbar.swift        # Top toolbar (macOS)
│   ├── SelectableMessageText.swift
│   ├── ToolResultCard.swift     # Tool execution results
│   └── ToolsAvailableDebugSheet.swift
├── Components/
│   ├── AFMDiagnosticsView.swift
│   ├── AdaptiveGlassBackground.swift
│   ├── ArtifactCard.swift
│   ├── GlassColors.swift
│   ├── GlassToolbar.swift
│   ├── LiquidGlassTokens.swift  # Design system tokens
│   ├── NeonMessageBubble.swift  # ⭐ Message rendering
│   ├── NeonModelPicker*.swift   # Model selection (4 files)
│   ├── NeonToolInspector.swift  # Right panel
│   ├── NeonWelcomeView.swift    # Welcome screen
│   ├── StreamingStatsCapsule.swift
│   ├── ThinkingIndicatorView.swift
│   ├── TokenUsageCapsule.swift
│   ├── ToolIconToggle.swift
│   └── WindowBackgroundStyle.swift
├── Legacy/                      # Old/deprecated views
├── Settings/
│   └── SettingsView.swift       # ⭐ All settings tabs
├── Sidebar/
│   ├── CleanupBannerView.swift
│   ├── CleanupReviewSheet.swift
│   ├── NeonSidebar.swift        # ⭐ Session list
│   └── SidebarComponents.swift
├── Terminal/                    # Terminal/console views
├── Workbench/
│   └── NeonWorkbenchWindow.swift # ⭐ Root layout
├── FileOperationApprovalView.swift
└── TerminalOutputView.swift
```

---

## 🔑 Key Entry Points (Start Here)

1. **Changing overall layout?** → `NeonWorkbenchWindow.swift`
2. **Changing chat appearance?** → `NeonChatView.swift`
3. **Changing message bubbles?** → `NeonMessageBubble.swift`
4. **Changing input bar?** → `ChatInputPanel.swift`
5. **Changing sidebar?** → `NeonSidebar.swift`
6. **Changing settings?** → `SettingsView.swift`
7. **Changing model picker?** → `NeonModelPickerButton.swift` / `NeonModelPicker.swift`
8. **Changing glass/theme?** → `LiquidGlassTokens.swift`, `GlassColors.swift`

---

## 🎨 Platform-Specific Code Locations

Many views have `#if os(iOS)` / `#if os(macOS)` blocks:

- **NeonWorkbenchWindow.swift** - `iosLayout` vs `macosLayout` computed properties
- **NeonChatView.swift** - iOS nav bar toolbar vs macOS NeonToolbar
- **ChatInputPanel.swift** - Keyboard handling differences
- **SettingsView.swift** - Window sizing

---

## 💡 Tips

1. **Use Cmd+Shift+O** in Xcode to quick-open files by name
2. **Use Cmd+Shift+J** to reveal current file in navigator
3. **Search for `struct ViewName:`** to find view definitions
4. **Files are named after their main view** (e.g., `NeonChatView.swift` contains `struct NeonChatView`)
