## 2024-05-24 - Accessibility labels for Icon Buttons\n**Learning:** The application uses `.help()` heavily for both macOS hover tooltips and VoiceOver accessibility labels on icon-only buttons instead of `.accessibilityLabel()`. \n**Action:** Ensure all new icon-only buttons receive a `.help()` modifier by default when building or modifying UI.

## 2026-05-07 - Sidebar Icon Button Accessibility
**Learning:** Sidebars (like `ModernSidebarLeft.swift`) often use raw SwiftUI buttons with icons but without `.help()`, missing out on accessibility features and hover tooltips.
**Action:** When adding or modifying icon buttons in sidebars, explicitly add `.help()` for accessibility and UX consistency.

## 2024-05-14 - Accessibility labels for Password/API Key Toggles
**Learning:** Icon-only buttons used for toggling visibility of secure fields (like `isKeyVisible.toggle()`) need explicit accessibility labels to announce their function to VoiceOver, and tooltips on hover. Without them, screen readers may just announce "button", making it hard to interact with secure fields effectively.
**Action:** When creating password/API key fields with visibility toggles, always add `.help(isVisible ? "Hide" : "Show")` modifiers to the toggle buttons.

## 2024-05-30 - Expand/Collapse Chevron Accessibility
**Learning:** Chevron toggle buttons for expandable content blocks (like `ArtifactCardView`'s `isExpanded` toggles) sometimes lack accessibility labels. This causes VoiceOver to only read "button" without context.
**Action:** When creating or modifying expand/collapse chevron toggles, always add a descriptive state-aware accessibility label like `.help(isExpanded ? "Collapse <Item>" : "Expand <Item>")`.

## 2024-05-30 - Expand/Collapse Chevron Accessibility in SettingsView
**Learning:** Found an expand/collapse chevron button in the SettingsView (specifically ProviderRow) that did not have an accessibility label. VoiceOver would simply announce "button".
**Action:** When creating or reviewing UI with expand/collapse chevron buttons, ensure that `.help()` modifiers are applied to provide context to screen readers, like `.help(isExpanded ? "Collapse <Name>" : "Expand <Name>")`.
