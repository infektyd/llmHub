# Settings System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          llmHubApp.swift                             │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  @State private var settingsManager = SettingsManager()       │  │
│  │                                                                 │  │
│  │  ContentView()                                                  │  │
│  │    .environment(\.settingsManager, settingsManager)            │  │
│  │    .preferredColorScheme(settingsManager.settings.colorScheme) │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Environment injection
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      SwiftUI Environment                             │
│                 (Available to all child views)                       │
└─────────────────────────────────────────────────────────────────────┘
                    │                        │                    │
        ┌───────────┘                        │                    └───────────┐
        │                                    │                                │
        ▼                                    ▼                                ▼
┌──────────────┐                  ┌──────────────────┐          ┌────────────────┐
│ SettingsView │                  │   RootView       │          │  Other Views   │
│              │                  │  (Canvas UI)     │          │                │
│  Advanced    │                  │                  │          │ - Transcript   │
│  Appearance  │                  │ @Environment(\   │          │ - Composer     │
│  Providers   │◀─────reads──────▶│  \.settingsMan..│◀────────▶│ - MessageRow   │
│  Tools       │                  │                  │          │ - etc.         │
│  About       │                  │  Applies:        │          │                │
│              │                  │  - Theme         │          │  Read settings │
└──────────────┘                  │  - Font scale    │          │  for behavior  │
        │                         │  - Spacing       │          └────────────────┘
        │ User changes            └──────────────────┘
        │ settings
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      SettingsManager.swift                           │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  @Observable                                                    │  │
│  │  class SettingsManager {                                        │  │
│  │    var settings: AppSettings { didSet { saveSettings() } }     │  │
│  │  }                                                              │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                │                                     │
│                                │ On change (debounced 500ms)         │
│                                ▼                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  private func saveSettings() {                                  │  │
│  │    // Debounce with Task                                        │  │
│  │    Task {                                                        │  │
│  │      try? await Task.sleep(nanoseconds: 500_000_000)           │  │
│  │      saveSettingsImmediately()                                  │  │
│  │    }                                                            │  │
│  │  }                                                              │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                │                                     │
│                                │ JSON encode                         │
│                                ▼                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  UserDefaults.standard.set(data, forKey: settingsKey)          │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ Persists to disk
                                ▼
        ┌───────────────────────────────────────────────┐
        │         UserDefaults (plist on disk)          │
        │                                               │
        │  "llmHub.appSettings.v1" = {                  │
        │    colorScheme: "system",                     │
        │    fontSize: 1.0,                             │
        │    compactMode: false,                        │
        │    showTokenCounts: true,                     │
        │    autoScroll: true,                          │
        │    streamingThrottle: 10,                     │
        │    ...                                        │
        │  }                                            │
        └───────────────────────────────────────────────┘
                                │
                                │ On app launch
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       AppSettings.swift                              │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  struct AppSettings: Codable {                                  │  │
│  │    var colorScheme: ColorSchemeChoice = .system                │  │
│  │    var fontSize: CGFloat = 1.0                                 │  │
│  │    var compactMode: Bool = false                               │  │
│  │    var showTokenCounts: Bool = true                            │  │
│  │    // ... 11 more settings                                     │  │
│  │                                                                 │  │
│  │    mutating func validate() {                                  │  │
│  │      fontSize = max(0.8, min(1.5, fontSize))                   │  │
│  │      // ... validate all settings                              │  │
│  │    }                                                            │  │
│  │  }                                                              │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Initialization (App Launch)

```
llmHubApp.swift
  └─> SettingsManager.init()
       └─> Load from UserDefaults
            └─> JSON decode to AppSettings
                 └─> Validate ranges
                      └─> Ready for use
```

### 2. Reading Settings (Any View)

```
View
  └─> @Environment(\.settingsManager) var manager
       └─> manager.settings.fontSize
            └─> Returns: 1.0 (or user's value)
```

### 3. Updating Settings (Settings View)

```
User slides font size slider
  └─> Binding updates settingsManager.settings.fontSize
       └─> didSet triggers saveSettings()
            └─> Task sleeps 500ms (debounce)
                 └─> JSON encode AppSettings
                      └─> Write to UserDefaults
                           └─> Persist to disk
```

### 4. Theme Application (RootView)

```
llmHubApp.swift reads settingsManager.settings.colorScheme
  └─> .preferredColorScheme(.dark)
       └─> SwiftUI applies dark mode to entire app
            └─> AppColors.Dark palette is used
```

### 5. Live Updates (Reactive)

```
Settings change
  └─> SettingsManager is @Observable
       └─> SwiftUI detects dependency
            └─> Re-renders affected views
                 └─> User sees immediate change
```

## Thread Safety

```
┌─────────────────────────────────────┐
│     All access on @MainActor        │
│                                     │
│  SettingsManager: @MainActor        │
│  ├─ settings: AppSettings           │
│  ├─ saveSettings() @MainActor       │
│  └─ resetToDefaults() @MainActor    │
│                                     │
│  Views: Implicitly @MainActor       │
│  └─ @Environment(\.settingsManager) │
└─────────────────────────────────────┘
```

## Key Components

### AppSettings.swift

- **Role**: Data model
- **Type**: Struct (value type)
- **Protocol**: Codable (for JSON)
- **Validation**: Built-in range clamping

### SettingsManager.swift

- **Role**: Persistence layer
- **Type**: Class (reference type)
- **Protocol**: @Observable
- **Thread**: @MainActor
- **Pattern**: Singleton via Environment

### AppColors.swift

- **Role**: Theme system
- **Enhancement**: palette(for:) method
- **Support**: Explicit color scheme override
- **Return**: Palette struct with all colors

### SettingsView.swift

- **Role**: UI presentation
- **Pattern**: Section-based navigation
- **Update**: Uses SettingsManager
- **Platform**: macOS (Settings window) + iOS (modal)

### llmHubApp.swift

- **Role**: App entry point
- **Injection**: SettingsManager to environment
- **Application**: .preferredColorScheme() modifier
- **Availability**: App-wide via environment

## Settings Categories Tree

```
Settings
├── Appearance (AppearanceSection)
│   ├── Color Scheme (system/light/dark)
│   ├── Font Size (0.8-1.5)
│   ├── Compact Mode (toggle)
│   └── Show Token Counts (toggle)
│
├── Tools (ToolsSection)
│   └── Per-tool toggles
│
├── Advanced (AdvancedSettingsView) ★ NEW
│   ├── Auto-scroll (toggle)
│   ├── Streaming Throttle (5-20)
│   ├── Context Compaction (toggle)
│   ├── Max Context Tokens (1K-200K)
│   ├── Recent Session Limit (10-50)
│   ├── Auto-save Interval (10-300s)
│   ├── Network Timeout (10-120s)
│   └── Summary Generation (toggle)
│
├── Providers (ProvidersSection)
│   ├── OpenAI
│   ├── Anthropic
│   ├── Google
│   ├── Mistral
│   ├── xAI
│   └── OpenRouter
│
├── About (AboutSection)
│   ├── Version info
│   ├── Build number
│   └── Links
│
└── Diagnostics (DiagnosticsSection) [DEBUG only]
    └── AFM status & testing
```

## Integration Map

```
Settings Property         →  Affected Component(s)
────────────────────────────────────────────────────
colorScheme              →  llmHubApp (root theme)
fontSize                 →  All text views
compactMode              →  TranscriptView, Cards
showTokenCounts          →  MessageRow headers
autoScroll               →  TranscriptView scroll logic
streamingThrottle        →  ChatViewModel streaming
contextCompactionEnabled →  ChatViewModel context building
maxContextTokens         →  ChatViewModel context limits
recentSessionLimit       →  SidebarView query
autoSaveInterval         →  WorkbenchViewModel auto-save
networkTimeout           →  All LLM providers
summaryGenerationEnabled →  Session save logic
defaultProviderID        →  RootView initial selection
defaultModel             →  RootView initial selection
defaultToolPermissions   →  ComposerBar tool filtering
```

## Validation Flow

```
User Input (unclamped)
         │
         │ Setting property setter
         ▼
    Immediate validation
    (in SettingsManager)
         │
         │ Clamped value
         ▼
  AppSettings property
         │
         │ On save
         ▼
    validate() method
    (double-check)
         │
         │ Guaranteed valid
         ▼
    JSON encode
         │
         ▼
  UserDefaults
```

## Example: Font Size Change

```
[User drags slider to 2.0]
         │
         ▼
AdvancedSettingsView
  Binding(set: { settingsManager.settings.fontSize = $0 })
         │
         ▼
SettingsManager
  settings.fontSize = max(0.8, min(1.5, 2.0))  // Clamped to 1.5
         │
         ▼
  didSet { saveSettings() }
         │
         ▼
  Task { sleep 500ms → saveSettingsImmediately() }
         │
         ▼
  JSONEncoder().encode(settings)
         │
         ▼
  UserDefaults.standard.set(data, forKey: "llmHub.appSettings.v1")
         │
         ▼
[Persisted to disk]
         │
         ▼
[@Observable triggers SwiftUI update]
         │
         ▼
[All views using fontSize re-render with 1.5]
```

---

This architecture provides:
✅ Centralized settings management  
✅ Type-safe access  
✅ Automatic persistence  
✅ Reactive UI updates  
✅ Thread-safe operations  
✅ Validation and safety  
✅ Easy testing and debugging  
✅ Scalable for future settings
