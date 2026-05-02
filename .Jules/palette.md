## 2024-05-02 - Icon-Only Button Accessibility
**Learning:** Icon-only buttons (like Send, Stop, Attach, Sidebar toggle, and Settings) in `Composer.swift` and `ArtifactPreviewChip`/`AttachmentPreviewChip` lack accessibility labels, making them difficult to use with screen readers and providing no visual tooltips on hover for macOS users.
**Action:** Use `.help("Descriptive Text")` on icon-only buttons in SwiftUI to simultaneously provide visual tooltips and improve VoiceOver accessibility.
