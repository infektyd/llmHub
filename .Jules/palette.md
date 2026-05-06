## 2024-05-24 - Accessibility labels for Icon Buttons\n**Learning:** The application uses `.help()` heavily for both macOS hover tooltips and VoiceOver accessibility labels on icon-only buttons instead of `.accessibilityLabel()`. \n**Action:** Ensure all new icon-only buttons receive a `.help()` modifier by default when building or modifying UI.

## 2026-05-06 - Adding Missing Accessibility Labels for Sidebars
**Learning:** Found multiple icon-only `Button` components in `ModernSidebarLeft.swift` and `ModernSidebarRight.swift` that were missing `.help()` modifiers, which meant they lacked VoiceOver labels and hover tooltips.
**Action:** Add `.help()` to all icon-only buttons as a standard practice, specifically ensuring right sidebar (inspector) components receive proper labels.
