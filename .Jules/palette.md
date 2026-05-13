## 2024-05-24 - Accessibility labels for Icon Buttons\n**Learning:** The application uses `.help()` heavily for both macOS hover tooltips and VoiceOver accessibility labels on icon-only buttons instead of `.accessibilityLabel()`. \n**Action:** Ensure all new icon-only buttons receive a `.help()` modifier by default when building or modifying UI.

## 2026-05-07 - Sidebar Icon Button Accessibility
**Learning:** Sidebars (like `ModernSidebarLeft.swift`) often use raw SwiftUI buttons with icons but without `.help()`, missing out on accessibility features and hover tooltips.
**Action:** When adding or modifying icon buttons in sidebars, explicitly add `.help()` for accessibility and UX consistency.

## 2024-06-25 - Refresh Agent Button Accessibility
**Learning:** Found an icon-only button without an accessibility label in the `AgentRosterSidebarView` which triggers agent discovery. Users using screen readers or relying on tooltips would not know what this `arrow.clockwise` button does.
**Action:** Always verify custom icon-only buttons in the UI for a `.help()` modifier to ensure hover tooltips and VoiceOver labels are present.
