# Design Spec: Hybrid Transcript System (Neon & Liquid Glass)

## 1. High-Level Intent
- **Unified Pipeline**: Single `NeonChatView` + `NeonMessageRow` engine.
- **Bubbleless**: Message rows have **zero** background fill.
- **Strict Tokenization**: Runtime switching via `AppTheme` and `LiquidGlassTokens`.
- **Content-First**: Tool interactions and streaming text take priority.

## 2. Component Map
- **TranscriptSurface**: Infinite scroll container.
- **MessageRow**: Single logical message block (No bubbles).
- **RoleMarker**: Vertical bar/icon to the left.
- **ToolResultCard**: The only "card" allowed.

## 3. Token Dictionary (Critical)
- **NEON**: Font: SF Mono. Background: Hex #050505. Accent: Electric Cyan.
- **LIQUID**: Font: SF Pro. Background: Native Glass. Accent: Translucent Teal.
- **Layout**: Left-align ALL messages. Use Spacing, not containers.

## 4. Implementation Plan
1. Create `LiquidGlassTokens` struct to handle theme switching.
2. Refactor `NeonMessageRow.swift` to remove bubbles.
3. Implement "Role Marker" sidebar.
