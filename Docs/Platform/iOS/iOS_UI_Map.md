# iOS UI Element Map - Settings & Keyboard Features

Visual reference for where iOS-specific UI elements appear in llmHub.

---

## Chat View Layout (iOS)

```
┌─────────────────────────────────────┐
│  ⚙️   Chat Session Title     ⋯    │  ← Navigation Bar
│                                     │
├─────────────────────────────────────┤
│                                     │
│   ┌─────────────────────────────┐  │
│   │  Message from Assistant     │  │
│   └─────────────────────────────┘  │
│                                     │
│        ┌────────────────────┐      │
│        │  Your Message      │      │  ← Messages Area
│        └────────────────────┘      │     (swipe down dismisses keyboard if enabled)
│                                     │
│   ┌─────────────────────────────┐  │
│   │  Assistant Response         │  │
│   └─────────────────────────────┘  │
│                                     │
├─────────────────────────────────────┤
│ ┌───────────────┬──┬──┬──┬──┬──┐  │
│ │ Message...    │🔽│🔼│            │  ← Input Bar
│ └───────────────┴──┴──┴──┴──┴──┘  │
└─────────────────────────────────────┘

Legend:
⚙️ = Settings button (NEW)
⋯ = Menu button (existing)
🔽 = Keyboard dismiss button (future/optional)
🔼 = Send button (existing)
```

---

## Navigation Bar Detail

```
┌──────────────────────────────────────────┐
│  ⚙️  Settings     Chat Title        ⋯   │
│  ↑                                   ↑   │
│  New iOS button               Menu button│
│  (leading)                    (trailing) │
└──────────────────────────────────────────┘

Tap ⚙️ → Opens Settings Modal ↓
```

---

## Settings Modal (iOS)

```
┌─────────────────────────────────────┐
│        Settings            Done     │  ← Navigation Bar
├─────────────────────────────────────┤
│                                     │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │
│  ┃ 🔑 API Keys                  ┃  │
│  ┃                              ┃  │
│  ┃  OpenAI                      ┃  │
│  ┃  ┌──────────────┐ 👁️ 💾 🗑️  ┃  │
│  ┃  │ sk-...       │           ┃  │  ← API Keys Tab
│  ┃  └──────────────┘           ┃  │
│  ┃                              ┃  │
│  ┃  Anthropic                   ┃  │
│  ┃  ┌──────────────┐ 👁️ 💾     ┃  │
│  ┃  │ sk-ant-...   │           ┃  │
│  ┃  └──────────────┘           ┃  │
│  ┃                              ┃  │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │
│                                     │
├─────────────────────────────────────┤
│  🔑 API Keys | 🎨 Appearance | ⚙️   │  ← Tab Bar
└─────────────────────────────────────┘

Swipe down modal → Dismisses
Tap Done → Dismisses
```

---

## Input Bar States

### State 1: Keyboard Hidden (Default)

```
┌─────────────────────────────────────┐
│ ┌─────────────────────────┬──────┐ │
│ │ Message...              │  🔼  │ │
│ └─────────────────────────┴──────┘ │
└─────────────────────────────────────┘

Input field | Send button
```

### State 2: Keyboard Visible & Focused (future)

```
┌─────────────────────────────────────┐
│ ┌───────────────┬─────┬──────┐     │
│ │ Typing text...│ 🔽 │  🔼  │     │  ← Keyboard dismiss button (if implemented)
│ └───────────────┴─────┴──────┘     │
└─────────────────────────────────────┘
        ↑           ↑         ↑
    Input field   Dismiss   Send
                   (NEW)

Tap 🔽 → Keyboard slides down
Focus lost → 🔽 disappears
```

---

## Keyboard Interaction Flow

```
┌─────────────────────────────────────┐
│                                     │
│         Chat Messages               │
│         (scrollable)                │
│                                     │
│              👇 Swipe down          │
│         (dismisses keyboard if enabled) │
│                                     │
├─────────────────────────────────────┤
│ ┌───────────────┬─────┬──────┐     │
│ │ Message...    │ 🔽 │  🔼  │     │
│ └───────────────┴─────┴──────┘     │
├─────────────────────────────────────┤
│                                     │
│         iOS Keyboard                │
│   q w e r t y u i o p               │
│    a s d f g h j k l                │
│      z x c v b n m                  │
│                                     │
└─────────────────────────────────────┘

Two ways to dismiss (if enabled):
1. Swipe down on chat messages ↑
2. Tap 🔽 button in input bar
```

---

## Menu Button (Existing - iOS)

```
┌──────────────────────────────────────┐
│  ⚙️  Chat Title                  ⋯  │
└──────────────────────────────────────┘
                                    ↑
                               Tap to open ↓

    ┌──────────────────────────────┐
    │  🔧 Tool Inspector (stub)   │
    ├──────────────────────────────┤
    │  🌐 Provider ▸              │
    │     ┌──────────────────────┐│
    │     │ 🧠 OpenAI            ││
    │     │ 🧠 Anthropic         ││
    │     │ 🧠 Google AI         ││
    │     │ 🧠 Mistral AI        ││
    │     │ 🧠 xAI               ││
    │     │ 🧠 OpenRouter        ││
    │     └──────────────────────┘│
    └──────────────────────────────┘
```

---

## Settings Modal - API Keys Tab Detail

```
┌────────────────────────────────────────┐
│         Settings               Done    │
├────────────────────────────────────────┤
│  API Keys                              │
│  Configure API keys for each LLM...    │
│                                        │
│  ╔══════════════════════════════════╗ │
│  ║  OpenAI                ✓ Config  ║ │  ← Green badge when key saved
│  ║  ┌─────────────────────────────┐ ║ │
│  ║  │ sk-••••••••••••••••••••••••• │ ║ │  ← Secure field (masked)
│  ║  └─────────────────────────────┘ ║ │
│  ║  [👁️ Show/Hide] [💾 Save] [🗑️]  ║ │  ← Action buttons
│  ║  🔗 Get API key from OpenAI      ║ │  ← Documentation link
│  ╚══════════════════════════════════╝ │
│                                        │
│  ╔══════════════════════════════════╗ │
│  ║  Anthropic                       ║ │
│  ║  ┌─────────────────────────────┐ ║ │
│  ║  │ Enter API key               │ ║ │  ← Empty field
│  ║  └─────────────────────────────┘ ║ │
│  ║  [👁️] [💾 Save (disabled)]      ║ │
│  ║  🔗 Get API key from Anthropic   ║ │
│  ╚══════════════════════════════════╝ │
│                                        │
│  [Similar rows for other providers]   │
├────────────────────────────────────────┤
│  🔑 API Keys | 🎨 Appearance | ⚙️     │
└────────────────────────────────────────┘
```

---

## Settings Modal - Appearance Tab Detail

```
┌────────────────────────────────────────┐
│         Settings               Done    │
├────────────────────────────────────────┤
│  Appearance                            │
│  Customize the look and feel          │
│                                        │
│  Color Scheme: [System | Light | Dark] │
│  Font Size:     100% ━━━━━━━◉━━        │
│  Compact Mode:  [toggle]              │
│  Show Tokens:   [toggle]              │
│  Avatar:        👤 🧑‍💻 🤖 ...         │
├────────────────────────────────────────┤
│  🔑 API Keys | 🎨 Appearance | ⚙️     │
└────────────────────────────────────────┘
```

---

## Color Reference

### Canvas/Flat Palette (iOS)

- Use `AppColors` tokens from `Utilities/UI/AppColors.swift`
- Keep surfaces matte; avoid legacy glass materials

### Button States

```swift
// Settings button (leading)
Image(systemName: "gearshape")
    .foregroundColor(AppColors.accent)  // Accent color

// Keyboard dismiss button (when focused)
Image(systemName: "keyboard.chevron.compact.down")
    .foregroundColor(AppColors.textPrimary)
    // Background: matte circle

// Send button (enabled)
Image(systemName: "arrow.up")
    .foregroundColor(AppColors.textPrimary)
    // Background: accent tint
```

---

## Accessibility Labels (Recommended)

```swift
// Settings button
.accessibilityLabel("Settings")
.accessibilityHint("Open settings to configure API keys")

// Keyboard dismiss button
.accessibilityLabel("Dismiss keyboard")
.accessibilityHint("Hides the keyboard")

// API key fields
.accessibilityLabel("OpenAI API key")
.accessibilityHint("Enter your OpenAI API key")

// Save button
.accessibilityLabel("Save API key")
.accessibilityHint("Saves the API key to secure storage")
```

---

## Animation Specifications

### Settings Modal
- **Open**: Slide up from bottom, 0.3s ease-out
- **Close**: Slide down, 0.25s ease-in
- **Drag**: Interactive swipe-to-dismiss

### Keyboard Dismiss Button
- **Appear**: Scale from 0.8 to 1.0 + fade in, 0.2s spring
- **Disappear**: Scale to 0.8 + fade out, 0.15s ease-out
- **Tap**: Slight scale down feedback

### Keyboard Itself
- **Dismiss via swipe**: Interactive follow gesture
- **Dismiss via button**: Standard iOS slide down

---

## Safe Area Handling

```
┌─────────────────────────────────────┐
│    🔔 Dynamic Island / Notch        │  ← Safe area top
├─────────────────────────────────────┤
│  ⚙️  Chat Title               ⋯    │  ← Navigation bar (in safe area)
│                                     │
│        Content Area                 │
│                                     │
│        (respects safe area)         │
│                                     │
│ ┌───────────────┬─────┬──────┐     │  ← Input bar (above keyboard)
│ │ Message...    │ 🔽 │  🔼  │     │
│ └───────────────┴─────┴──────┘     │
├─────────────────────────────────────┤
│         iOS Keyboard                │
├─────────────────────────────────────┤
│         Home Indicator              │  ← Safe area bottom
└─────────────────────────────────────┘

All UI elements automatically respect:
- Status bar area (notch/Dynamic Island)
- Home indicator area
- Keyboard safe area
```

---

## Touch Targets

All interactive elements meet iOS minimum touch target:

- **Gear icon**: 44pt × 44pt (navigation bar standard)
- **Keyboard dismiss button (if implemented)**: 32pt × 32pt circle (with 44pt touchable area)
- **Send button**: 32pt × 32pt circle (with 44pt touchable area)
- **API key action buttons**: 44pt × 44pt
- **Tab bar items**: Standard iOS height (49pt)

---

## Platform Comparison

### macOS vs iOS Layout

```
┌───────────────────────────────────────────────────────┐
│ macOS                          │ iOS                  │
├───────────────────────────────────────────────────────┤
│ Settings in menu bar           │ ⚙️ button in nav bar│
│ Settings → Settings...         │ Tap ⚙️ → modal      │
│                                │                      │
│ Keyboard dismissal             │ Swipe or iOS default│
│                                │                      │
│ Fixed window size              │ Full screen layouts  │
│ 600×500 settings window        │ Adaptive sizing      │
│                                │                      │
│ Header bar visible             │ Toolbar in menu ⋯   │
└───────────────────────────────────────────────────────┘
```

---

## Quick Reference: Finding UI Elements

| Element | Location | Platform |
|---------|----------|----------|
| Settings gear icon | Top-left navigation bar | iOS only |
| Settings menu | Menu bar → llmHub → Settings | macOS only |
| Keyboard dismiss button (optional) | Input bar (when focused) | iOS only |
| Settings modal | Full-screen sheet | iOS |
| Settings window | Separate window | macOS |
| Tool inspector (stub) | Menu ⋯ → Tool Inspector | iOS |
| Tool inspector | Right sidebar (ModernSidebarRight) | macOS |

---

## Icon Reference

All system SF Symbols used:

| Icon | Symbol Name | Usage |
|------|-------------|-------|
| ⚙️ | `gearshape` | Settings button |
| 🔽 | `keyboard.chevron.compact.down` | Keyboard dismiss (optional) |
| 🔼 | `arrow.up` | Send message |
| ⋯ | `ellipsis.circle` | More menu |
| 🔑 | `key.fill` | API Keys tab |
| 🎨 | `paintbrush` | Appearance tab |
| 👁️ | `eye.fill` / `eye.slash.fill` | Show/hide password |
| 💾 | `arrow.down.circle.fill` | Save |
| 🗑️ | `trash.fill` | Delete |
| 🔗 | `arrow.up.right.square` | External link |
| ✓ | `checkmark.circle.fill` | Configured badge |
| 🧠 | `brain` | Provider menu items |
| 🔧 | `wrench.and.screwdriver` | Tool inspector |

---

This UI map serves as a visual reference for developers and designers working on llmHub's iOS interface.




















