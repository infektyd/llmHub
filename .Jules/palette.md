## 2024-05-24 - Accessibility labels for Icon Buttons\n**Learning:** The application uses `.help()` heavily for both macOS hover tooltips and VoiceOver accessibility labels on icon-only buttons instead of `.accessibilityLabel()`. \n**Action:** Ensure all new icon-only buttons receive a `.help()` modifier by default when building or modifying UI.
## 2024-05-24 - Accessibility labels for Sidebar Icon Buttons
**Learning:** Found multiple icon-only buttons in `ModernSidebarLeft.swift` without accessibility labels/tooltips.
**Action:** Applied `.help()` modifiers with descriptive strings like "New Chat", "Close Sidebar", and "New Project" to improve accessibility and user experience in the left sidebar.
