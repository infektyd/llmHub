# iOS Quick Reference Guide

Quick guide for iOS-specific patterns used in llmHub (Canvas/flat UI).

---

## Settings Access Pattern

### Implementation Location
`llmHub/Views/UI/RootView.swift`

### Code Pattern
```swift
// State management
#if !os(macOS)
@State private var showSettings = false
@EnvironmentObject private var modelRegistry: ModelRegistry
#endif

// Sheet presentation
#if !os(macOS)
.sheet(isPresented: $showSettings) {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showSettings = false } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { showSettings = false }
                }
            }
            .environmentObject(modelRegistry)
    }
}
#endif
```

### Key Points
- Keep iOS-specific UI behind `#if !os(macOS)` or `#if os(iOS)`
- Use `.sheet()` for modal presentations
- Include a clear dismissal control
- Pass environment objects explicitly to sheets

---

## Keyboard Behavior

### Current State
- Input focus is managed in `llmHub/Views/UI/Composer/Composer.swift` via `@FocusState`.
- There is **no explicit keyboard dismiss button** wired today.

### Optional Pattern (If Adding Manual Dismiss)
```swift
@FocusState private var isInputFocused: Bool

Button(action: { isInputFocused = false }) {
    Image(systemName: "keyboard.chevron.compact.down")
}
```

---

## Cross-Platform View Sizing

### Pattern
```swift
#if os(macOS)
.frame(width: 600, height: 500)
#endif
// iOS: no fixed frame, fills available space
```

### Example
`llmHub/Views/Settings/SettingsView.swift`:
```swift
#if os(macOS)
.frame(width: 600, height: 500)
#endif
.background(AppColors.backgroundPrimary)
```

---

## Navigation Bar Styling (iOS)

### Standard Pattern
```swift
#if os(iOS)
.navigationTitle("Title")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        // Left button
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        // Right button
    }
}
#endif
```

---

## Environment Objects in Sheets (iOS)

### Solution
Explicitly pass environment objects:
```swift
.sheet(isPresented: $showingSheet) {
    NavigationStack {
        SomeView()
            .environmentObject(modelRegistry)
    }
}
```

---

## Focus Management (iOS)

### Basic Focus State
```swift
@FocusState private var isInputFocused: Bool

TextField("Placeholder", text: $text)
    .focused($isInputFocused)

// Programmatic control
Button("Focus") {
    isInputFocused = true
}
```

---

## Platform Detection

### Conditional Compilation
```swift
#if os(iOS)
// iOS-only code
#elseif os(macOS)
// macOS-only code
#endif
```

---

## Common iOS Gotchas

### 1. Process Not Available
```swift
// ❌ This crashes on iOS
let process = Process()

// ✅ Wrap in platform check
#if os(macOS)
let process = Process()
// ...
#endif
```

### 2. NSSound Not Available
```swift
// ❌ iOS doesn't have NSSound
NSSound.beep()

// ✅ Use UIKit haptics
#if os(iOS)
UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#elseif os(macOS)
NSSound.beep()
#endif
```

---

## Testing Checklist for iOS Features

Before considering an iOS feature complete:

- [ ] Builds without errors on iOS target
- [ ] Wrapped in `#if os(iOS)` appropriately
- [ ] Works on both iPhone and iPad
- [ ] Respects safe areas (notch, Dynamic Island)
- [ ] Sheet presentations animate correctly
- [ ] Environment objects passed correctly
- [ ] Dark mode support
- [ ] Accessibility labels present

---

## Resources

### Related Files
- `llmHub/Views/UI/RootView.swift` - iOS settings sheet
- `llmHub/Views/UI/Composer/Composer.swift` - Input focus handling
- `llmHub/Views/Settings/SettingsView.swift` - Cross-platform settings UI
- `llmHub/App/llmHubApp.swift` - Platform-specific app scenes

### Documentation
- `Docs/Platform/iOS/iOS_Test_Plan.md` - Comprehensive testing guide
- `Docs/AGENTS.md` - Code style and architecture
- `Docs/CLAUDE.md` - Overall architecture

### Apple Documentation
- [Human Interface Guidelines - iOS](https://developer.apple.com/design/human-interface-guidelines/ios)
- [SwiftUI Platform Differences](https://developer.apple.com/documentation/swiftui/platform-differences)
- [Sheet Presentations](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:))
