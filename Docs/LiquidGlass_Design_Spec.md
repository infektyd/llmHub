# Design Spec: Hybrid Transcript System (Neon & Liquid Glass)

## 1. High-Level Intent

- **Unified Pipeline**: A single rendering engine (`NeonChatView` + `NeonMessageRow`) powers both aesthetics. No `if style == .A` conditionals in the view hierarchy; strictly token-driven.
- **Immersive Glass (Light)**: The "Liquid Glass" style treats the app window as a refractive pane over the user's wallpaper (macOS) or a blurred surface (iOS), with content floating directly on top.
- **Bubbleless Surface (Dark)**: The "Neon" style treats the app as a deep, void-like surface where content is anchored by high-contrast neon accents, completely removing container boundaries for a terminal-like flow.
- **Rows are Layers, Not Boxes**: In both styles, message rows have **zero** background fill. Content is grouped by alignment, spacing, and left-hand "Role Markers" rather than bubble containers.
- **Strict Tokenization**: Runtime switching is achieved by observing an `AppTheme` object that swaps these specific token values, instantly repainting the view tree.
- **Content-First**: Tool interactions and streaming text take priority. Layout shifts are forbidden during streaming; tokens must enforce fixed line heights and monospaced consistency where applicable.

## 2. Component Map

| Component             | Responsibility                                              | Style Hooks                                                    |
| :-------------------- | :---------------------------------------------------------- | :------------------------------------------------------------- |
| **TranscriptSurface** | The infinite scroll container backing the chat.             | `backgroundMaterial`, `edgeBlurRadius`, `verticalPadding`      |
| **MessageRow**        | A single logical message block (User or Assistant).         | `gutterWidth`, `verticalSpacing`, `isHoverable`                |
| **RoleMarker**        | The vertical bar/icon to the left of the text.              | `indicatorWidth`, `indicatorTint`, `iconScale`                 |
| **MarkdownBody**      | The rendered text content (Text / Codespans / Blocks).      | `bodyFont`, `codeBlockBackground`, `linkColor`, `headingScale` |
| **ToolResultCard**    | A discrete card for tool outputs (the only "card" allowed). | `cardBorder`, `cardShadow`, `headerBackground`, `glassOpacity` |
| **Composer**          | The input field and attachment staging area.                | `fieldBackground`, `activeStroke`, `sendButtonTint`            |
| **RoleAccent**        | Dynamic coloring for distinct generic agents/roles.         | `userTint`, `assistantTint`, `systemTint`, `toolTint`          |

## 3. Token Dictionary

### Layout

| Token Name             | Type    | Neon Dark (Bubbleless)      | Liquid Glass Light           |
| :--------------------- | :------ | :-------------------------- | :--------------------------- |
| `rowHorizontalPadding` | CGFloat | `16` (Tight, terminal-like) | `24` (Airy, editorial)       |
| `rowVerticalSpacing`   | CGFloat | `16`                        | `28` (Distinct separation)   |
| `markerGutterWidth`    | CGFloat | `14`                        | `18`                         |
| `maxContentWidth`      | CGFloat | `850`                       | `720` (Readable measure)     |
| `composerBottomInset`  | CGFloat | `0`                         | `20` (Floating above bottom) |
| `cornerRadiusToolCard` | CGFloat | `4`                         | `16`                         |

### Surface & Background

| Token Name         | Type           | Neon Dark                        | Liquid Glass Light                       |
| :----------------- | :------------- | :------------------------------- | :--------------------------------------- |
| `appBackground`    | Material/Color | `Color(hex: 050505)` (Deep Void) | `.ultraThinMaterial` + `white/0.4` blend |
| `surfaceBorder`    | Stroke         | `None`                           | `white/0.2` inner stroke                 |
| `blurRadius`       | CGFloat        | `0` (Sharp)                      | `40` (Heavy frosted)                     |
| `scrollerGradient` | Gradient       | `clear` to `black` (Hard fade)   | `clear` to `white/0.1` (Subtle mask)     |

### Typography

| Token Name      | Type   | Neon Dark                    | Liquid Glass Light  |
| :-------------- | :----- | :--------------------------- | :------------------ |
| `bodyFont`      | Font   | `SF Mono` @ 13pt             | `SF Pro` @ 15pt     |
| `headingWeight` | Weight | `.semibold`                  | `.bold` (Editorial) |
| `primaryText`   | Color  | `white` (100%)               | `black` (85%)       |
| `secondaryText` | Color  | `white` (50%)                | `black` (60%)       |
| `codeFont`      | Font   | `JetBrainsMono` or `Courier` | `SF Mono`           |

### Role Markers

| Token Name      | Type    | Neon Dark                | Liquid Glass Light          |
| :-------------- | :------ | :----------------------- | :-------------------------- |
| `markerWidth`   | CGFloat | `3`                      | `4`                         |
| `markerRadius`  | CGFloat | `1` (Sharp)              | `2` (Soft)                  |
| `userTint`      | Color   | `Neon Purple` (Electric) | `Slate Blue` (Muted)        |
| `assistantTint` | Color   | `Neon Cyan` (Electric)   | `Glassy Teal` (Translucent) |
| `toolTint`      | Color   | `Neon Pink`              | `Burnt Orange`              |

### Markdown

| Token Name             | Type   | Neon Dark     | Liquid Glass Light |
| :--------------------- | :----- | :------------ | :----------------- |
| `codeBlockBackground`  | Color  | `white/0.08`  | `black/0.05`       |
| `codeBlockBorder`      | Stroke | `white/0.15`  | `black/0.05`       |
| `inlineCodeForeground` | Color  | `Neon Yellow` | `Dark Magenta`     |
| `quoteBorderColor`     | Color  | `white/0.2`   | `black/0.2`        |

### Tool Cards

| Token Name         | Type     | Neon Dark    | Liquid Glass Light               |
| :----------------- | :------- | :----------- | :------------------------------- |
| `cardBackground`   | Material | `black/0.6`  | `white/0.4` (Frosted)            |
| `cardStroke`       | Stroke   | `white/0.1`  | `white/0.4`                      |
| `cardShadow`       | Shadow   | `None`       | `Radius: 12, Y: 4, Opacity: 0.1` |
| `headerBackground` | Color    | `white/0.05` | `black/0.03`                     |

### Interaction

| Token Name          | Type   | Neon Dark        | Liquid Glass Light |
| :------------------ | :----- | :--------------- | :----------------- |
| `focusRing`         | stroke | `Neon Cyan` Glow | `Blue` native ring |
| `textSelection`     | Color  | `Neon Blue/0.3`  | `System Blue/0.2`  |
| `hoverStateOverlay` | Color  | `white/0.05`     | `black/0.03`       |

## 4. Layout Rules

1.  **Continuous Surface**: The `TranscriptSurface` must use `ScrollView(..., ignoresSafeArea: true)` to ensure content flows behind the glass toolbars on both macOS and iOS.
2.  **Bubbleless Rendering**:
    - `ForEach(messages) { NeonMessageRow(...) }`.
    - `NeonMessageRow` must have `.background(Color.clear)`.
    - Visual separation is handled solely by `rowVerticalSpacing` and the `RoleMarker`.
3.  **Role/User Distinction**:
    - **User**: Role Marker + Bold Text. Left aligned.
    - **Assistant**: Role Marker + Regular Text. Left aligned.
    - _Note_: No right-alignment for User. The "Conversation" feels like a single script.
4.  **Streaming Updates**:
    - The streaming chunk must be rendered in a view that `.id()` matches the persistent message ID to prevent view regeneration.
    - Avoid `.animation()` on the height of the streaming text container to prevent "bouncy" text.
5.  **Parity**:
    - **macOS**: Uses `NSVisualEffectView` backing for "Liquid Glass". Window opacity can be < 1.0.
    - **iOS**: Uses `UIVisualEffectView` (`.ultraThinMaterial`). Window is opaque. Use `LinearGradient` masks to simulate transparency depth.

## 5. Edge Cases & QA Checklist

- **[ ] Contrast**: Verify `Neon Yellow` inline code against `Neon Dark` background meets accessibility standards (often too bright/low contrast).
- **[ ] Dynamic Type**: `bodyFont` must support scaling. Tokens like `rowVerticalSpacing` should be `scaledMetric`.
- **[ ] Tool Stacking**: If 3 tools run in sequence, ensuring the `spacing` between cards is distinct from `spacing` between messages (use `LiquidGlassTokens.Spacing.nestedTool` vs `rowVerticalSpacing`).
- **[ ] Long URLs**: Ensure the `MarkdownBody` forces word wrapping on character for long unbroken strings to prevent horizontal scroll injection.
- **[ ] Streaming Jitter**: Verify that the "Thinking..." indicator transitions to text without jumping the scroll position.

---

## Engineer Handoff: Hybrid Transcript Implementation

**Objective**: Implement a dual-theme transcript engine (Neon/Dark and Liquid/Light) using a shared `NeonMessageRow` component.

**Theme Engine**:

- Create `struct LiquidGlassTokens` with static accessors that return values based on `AppTheme.current`.
- Define properties for `rowSpacing`, `bodyFont`, `markerTint`, and `surfaceBackground`.

**View Structure**:

- `TranscriptSurface`: Logic to toggle `.background(.black)` vs `.background(.ultraThinMaterial)`.
- `NeonMessageRow`: Remove ALL bubble backgrounds. Implement the "Role Marker" sidebar (width: 3-4px).
- `ToolResultCard`: The only element with a border/shadow.

**Critical Constants**:

- **NEON**: Font: SF Mono. Background: Hex #050505. Accent: Electric Cyan.
- **LIQUID**: Font: SF Pro. Background: Native Glass. Accent: Translucent Teal.
- **Layout**: Left-align ALL messages. Use Spacing, not containers, to separate.

**Reference**: See `Docs/LiquidGlass_Design_Spec.md` for specific hex values.

---

## 6. Glass Patterns (Code Standards)

### Interactive Glass Usage

Use `.interactive()` **only** on:

- **Tap targets**: Buttons, toolbar items, clickable chips
- **Draggable surfaces**: Resizable panels, drag handles
- **Hover-responsive elements**: Cards that react to hover state

**Do NOT use** `.interactive()` on:

- Static backgrounds (use `AdaptiveGlassBackground` instead)
- Scroll container backgrounds
- Message content areas

### Standard Patterns

```swift
// ✅ Buttons / Toolbar Items
.glassEffect(GlassEffect.regular.tint(.glassAccent).interactive(), in: .circle)

// ✅ Clickable Cards / Chips
.glassEffect(GlassEffect.regular.tint(.glassBackground).interactive(), in: RoundedRectangle(...))

// ✅ Regional Backgrounds (user-tunable)
.background(AdaptiveGlassBackground(target: .chatArea))

// ✅ One-off static glass
.glassEffect(GlassEffect.regular.tint(.glassTool), in: RoundedRectangle(...))
```

### Deprecated (Banned)

The following patterns are banned and will fail CI lint:

- `GlassEffectContainer` — was a no-op wrapper
- `glassEffectID` — was a no-op
- `GlassEffectIntensity.native()` — use `GlassEffect.regular.tint()` directly

---

_Last Updated: December 2025_
