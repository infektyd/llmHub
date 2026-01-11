# iOS Quick Reference Guide

Quick guide for iOS-specific patterns used in llmHub.

---

## Settings Access Pattern

### Implementation Location
`llmHub/Views/Chat/NeonChatView.swift`

### Code Pattern
```swift
// State management
#if os(iOS)
@State private var showingSettings = false
@EnvironmentObject private var modelRegistry: ModelRegistry
#endif

// Toolbar button
#if os(iOS)
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .foregroundColor(.neonElectricBlue)
        }
    }
}
#endif

// Sheet presentation
#if os(iOS)
.sheet(isPresented: $showingSettings) {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingSettings = false
                    }
                }
            }
            .environmentObject(modelRegistry)
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
}
#endif
```

### Key Points
- Always wrap iOS-specific UI in `#if os(iOS)`
- Use `.sheet()` for modal presentations
- Include "Done" button in top-right for dismissal
- Pass environment objects explicitly to sheets
- Use `.presentationDetents([.large])` for full-screen modals

---

## Keyboard Dismiss Pattern

### Interactive Dismiss (ScrollView)

**Location**: `llmHub/Views/Chat/NeonChatView.swift`

```swift
ScrollView {
    // content
}
#if os(iOS)
.scrollDismissesKeyboard(.interactively)
#endif
```

### Explicit Dismiss Button

**Location**: `llmHub/Views/Chat/NeonChatInput.swift`

```swift
// Use existing @FocusState
@FocusState private var isInputFocused: Bool

// Conditional button in HStack
#if os(iOS)
if isInputFocused {
    keyboardDismissButton
}
#endif

// Button definition
#if os(iOS)
private var keyboardDismissButton: some View {
    Button(action: { isInputFocused = false }) {
        Image(systemName: "keyboard.chevron.compact.down")
            .frame(width: 32, height: 32)
            .background(keyboardDismissButtonBackground)
    }
    .transition(.scale.combined(with: .opacity))
}
#endif
```

### Key Points
- Use `.scrollDismissesKeyboard(.interactively)` on scrollable content
- Leverage `@FocusState` to track keyboard visibility
- Show dismiss button conditionally when focused
- Use smooth transitions for button appearance/disappearance
- Match theme styling (glass effects, colors)

---

## Cross-Platform View Sizing

### Pattern
```swift
.frame(width: someWidth, height: someHeight)
```

### Make It Conditional
```swift
#if os(macOS)
.frame(width: 600, height: 500)
#endif
// iOS: No fixed frame, fills available space
```

### Example
`llmHub/Views/Settings/SettingsView.swift`:
```swift
TabView {
    // tabs...
}
#if os(macOS)
.frame(width: 600, height: 500)
#endif
.background(Color.neonMidnight)
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

### Title Display Modes
- `.inline`: Small title in navigation bar (most common)
- `.large`: Large title that shrinks on scroll
- `.automatic`: System decides based on context

---

## Environment Objects in Sheets (iOS)

### Problem
Environment objects don't automatically propagate to sheets on iOS.

### Solution
Explicitly pass environment objects:
```swift
.sheet(isPresented: $showingSheet) {
    NavigationStack {
        SomeView()
            .environmentObject(modelRegistry)
            .environment(\.theme, themeManager.current)
    }
}
```

---

## Sheet Presentation Styles (iOS)

### Common Detents
```swift
.presentationDetents([.medium])           // Half screen
.presentationDetents([.large])            // Full screen
.presentationDetents([.medium, .large])   // Resizable
```

### Drag Indicator
```swift
.presentationDragIndicator(.visible)   // Show swipe indicator
.presentationDragIndicator(.hidden)    // Hide indicator
```

### Background Interaction
```swift
.presentationBackgroundInteraction(.enabled) // Can interact with background
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

### Dismiss Keyboard
```swift
// Option 1: Set focus to false
isInputFocused = false

// Option 2: Global dismiss (use sparingly)
#if os(iOS)
UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
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

### Runtime Check (avoid if possible)
```swift
#if canImport(UIKit)
// iOS/iPadOS/tvOS
#elseif canImport(AppKit)
// macOS
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

### 3. Window Management
```swift
// ❌ iOS doesn't have NSWindow
NSApp.keyWindow?.close()

// ✅ Use environment dismiss
@Environment(\.dismiss) var dismiss
dismiss()
```

---

## Testing Checklist for iOS Features

Before considering an iOS feature complete:

- [ ] Builds without errors on iOS target
- [ ] No compiler warnings
- [ ] Wrapped in `#if os(iOS)` appropriately
- [ ] Works on both iPhone and iPad
- [ ] Handles both portrait and landscape
- [ ] Respects safe areas (notch, Dynamic Island)
- [ ] Keyboard interactions smooth
- [ ] Sheet presentations animate correctly
- [ ] Environment objects passed correctly
- [ ] Dark mode support
- [ ] Accessibility labels present
- [ ] VoiceOver navigable

---

## Resources

### Related Files
- `llmHub/Views/Chat/NeonChatView.swift` - iOS navigation, settings access
- `llmHub/Views/Chat/NeonChatInput.swift` - Keyboard handling
- `llmHub/Views/Settings/SettingsView.swift` - Cross-platform settings
- `llmHub/App/llmHubApp.swift` - Platform-specific app scenes

### Documentation
- `Docs/IOS_SETTINGS_KEYBOARD_IMPLEMENTATION.md` - Implementation details
- `Docs/iOS_Test_Plan.md` - Comprehensive testing guide
- `AGENTS.md` - Code style and architecture
- `CLAUDE.md` - Overall architecture

### Apple Documentation
- [Human Interface Guidelines - iOS](https://developer.apple.com/design/human-interface-guidelines/ios)
- [SwiftUI Platform Differences](https://developer.apple.com/documentation/swiftui/platform-differences)
- [Sheet Presentations](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:))
