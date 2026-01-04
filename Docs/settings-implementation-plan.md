# Settings & Theme System Implementation Plan

## Overview

This document outlines the complete implementation of the Settings subsystem for llmHub, including persistence, theme system, and UI integration.

## Architecture

### 1. Data Model (`AppSettings.swift`)

- **Location**: `llmHub/Models/Core/AppSettings.swift`
- **Structure**: Codable struct containing all app-wide settings
- **Persistence**: UserDefaults with automatic encoding/decoding
- **Thread-safety**: @MainActor accessor methods

#### Settings Categories

**Appearance**

- `colorScheme: ColorSchemeChoice` (.system, .light, .dark)
- `compactMode: Bool` (reduces vertical spacing)
- `showTokenCounts: Bool` (display token/cost in message headers)
- `fontSize: CGFloat` (scale factor, default 1.0, range 0.8–1.5)

**Tools & Behavior**

- `defaultToolPermissions: [String: Bool]` (per-tool enable/disable)
- `autoScroll: Bool` (follows newest messages)
- `streamingThrottle: Int` (max updates per second, default 10)
- `contextCompactionEnabled: Bool`

**Provider Defaults**

- `defaultProviderID: String`
- `defaultModel: String`

**Workspace**

- `recentSessionLimit: Int` (default 20)
- `autoSaveInterval: Double` (seconds, default 30)

**Advanced**

- `networkTimeout: TimeInterval`
- `maxContextTokens: Int`
- `summaryGenerationEnabled: Bool`

### 2. Persistence Layer (`SettingsManager.swift`)

- **Location**: `llmHub/Support/SettingsManager.swift`
- **Responsibilities**:
  - Load/save AppSettings from/to UserDefaults
  - Validate setting ranges on load
  - Provide Observable wrapper for SwiftUI
  - Auto-save on property changes

### 3. Theme System (Enhanced `AppColors.swift`)

- **Current State**: AppColors has adaptive light/dark colors
- **Enhancement Needed**: Add support for explicit theme override
  - Create `ColorSchemeChoice` enum (.system, .light, .dark)
  - Add method to get colors for specific scheme
  - Integrate with Settings preferredScheme value

### 4. Settings UI

**Modal Structure**:

- Min size: 600×500pt
- Max size: 900×700pt
- Centered presentation
- Sidebar navigation (140pt) + content pane

**Sections** (already implemented in SettingsView.swift):

- ✅ Providers (API key management)
- ✅ Tools (capability toggles)
- ✅ Appearance (basic settings)
- ✅ About (app info)
- ✅ Diagnostics (DEBUG only)

**Enhancements Needed**:

- Add Advanced section
- Integrate AppSettings for persistence
- Add font size slider
- Add more appearance options

### 5. Integration Points

**RootView** → Settings Modal

- Add `.sheet()` modifier for settings presentation
- Pass SettingsManager via environment

**AppColors** → ColorScheme Override

- Read ColorSchemeChoice from SettingsManager
- Apply `.preferredColorScheme()` modifier at root

**TranscriptView** → Compact Mode & Token Display

- Read `compactMode` to adjust spacing
- Read `showTokenCounts` to show/hide token badges

**ComposerBar** → Tool Visibility

- Read `defaultToolPermissions` to filter tool list

**ChatViewModel** → Auto-scroll & Streaming

- Read `autoScroll` for scroll behavior
- Read `streamingThrottle` for throttling logic

## Implementation Checklist

- [ ] Create `llmHub/Models/Core/AppSettings.swift`
- [ ] Create `llmHub/Support/SettingsManager.swift`
- [ ] Enhance `llmHub/Utilities/AppColors.swift` for theme override
- [ ] Create `llmHub/Views/Settings/AdvancedSettingsView.swift`
- [ ] Update `llmHub/Views/Settings/SettingsView.swift` to integrate AppSettings
- [ ] Update `llmHub/Views/UI/RootView.swift` to add settings modal
- [ ] Wire settings to UI components (Transcript, Composer, etc.)
- [ ] Add keyboard navigation & accessibility labels
- [ ] Test persistence across app launches

## Design Principles

1. **No Glass Effects**: Flat matte surfaces with simple 1pt strokes
2. **AppColors System**: All colors from AppColors enum
3. **Responsive**: Modal scales gracefully 600–900w
4. **Live Preview**: Settings changes propagate instantly
5. **UserDefaults Only**: No SwiftData for settings (lightweight data)
6. **Validation**: Range validation on load with safe defaults

## File Manifest

### New Files

1. `llmHub/Models/Core/AppSettings.swift` — Complete data model
2. `llmHub/Support/SettingsManager.swift` — Persistence & observable wrapper
3. `llmHub/Views/Settings/AdvancedSettingsView.swift` — Advanced settings UI

### Modified Files

1. `llmHub/Utilities/AppColors.swift` — Add theme override support
2. `llmHub/Views/Settings/SettingsView.swift` — Integrate SettingsManager
3. `llmHub/Views/UI/RootView.swift` — Add settings sheet presentation
4. `llmHub/Views/Settings/AppearanceSettingsView.swift` — Enhanced appearance options

## Next Steps

1. Create AppSettings model with all properties
2. Create SettingsManager with UserDefaults persistence
3. Enhance AppColors for explicit theme selection
4. Update SettingsView to use SettingsManager
5. Add settings button to RootView
6. Wire settings to affected UI components
