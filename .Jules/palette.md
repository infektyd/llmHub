## 2024-05-24 - Accessibility labels for Icon Buttons\n**Learning:** The application uses `.help()` heavily for both macOS hover tooltips and VoiceOver accessibility labels on icon-only buttons instead of `.accessibilityLabel()`. \n**Action:** Ensure all new icon-only buttons receive a `.help()` modifier by default when building or modifying UI.

## 2026-05-07 - Sidebar Icon Button Accessibility
**Learning:** Sidebars (like `ModernSidebarLeft.swift`) often use raw SwiftUI buttons with icons but without `.help()`, missing out on accessibility features and hover tooltips.
**Action:** When adding or modifying icon buttons in sidebars, explicitly add `.help()` for accessibility and UX consistency.

## 2024-06-25 - Workspace and Action Button Accessibility
**Learning:** Found several icon-only buttons in modern sidebars (like `ModernSidebarRight.swift` and `AgentRosterSidebarView.swift`) used for critical actions (refreshing agents, adding files, cancelling executions, running tools) that lacked `.help()` modifiers. This makes them difficult to understand for new users and inaccessible to screen readers.
**Action:** Always verify that interactive `Button` or `Menu` components using only an `Image(systemName:)` have a descriptive `.help()` modifier. This is crucial for both hover tooltips on macOS and VoiceOver accessibility.
