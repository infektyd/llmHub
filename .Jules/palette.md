## 2024-05-24 - Accessibility labels for Icon Buttons\n**Learning:** The application uses `.help()` heavily for both macOS hover tooltips and VoiceOver accessibility labels on icon-only buttons instead of `.accessibilityLabel()`. \n**Action:** Ensure all new icon-only buttons receive a `.help()` modifier by default when building or modifying UI.

## 2026-05-05 - Accessibility labels for Window and Sidebar Controls
**Learning:** Sidebar toggle, close, and project creation icon-only buttons often miss `.help()` labels in their initial state.
**Action:** Audit sidebar control areas for missing `.help()` modifiers when introducing new toolbars or layouts.
