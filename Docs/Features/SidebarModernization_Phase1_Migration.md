# Sidebar Modernization Phase 1 — Migration Notes

## Scope
Phase 1 introduces SwiftData models and classification plumbing for a hierarchical sidebar with Projects, Artifacts, and AFM metadata fallback via Gemini 2.0 Flash.

## SwiftData changes
- `ChatSessionEntity`
  - New optional fields default to `nil`: `pinnedSymbol`, `parentProjectID`, `afmCategory`, `afmIntent`, `afmTitle`, `afmEmoji`, `afmClassifiedAt`, plus lifecycle fields.
  - `afmTopics` is now a typed `[String]` API backed by JSON storage (`afmTopicsData`) with `@Attribute(originalName: "afmTopics")` to read existing persisted data.
- New entities
  - `ProjectEntity`: project grouping for sessions.
  - `ArtifactEntity`: persisted artifacts with binary `content` stored via `@Attribute(.externalStorage)`.

## Existing conversations
- Existing sessions will simply have the new fields unset (`nil`) until classification runs.
- No automatic “reclassification sweep” is performed for existing data.
- Existing sessions with no `afmCategory` remain in the "Uncategorized" area of the sidebar until manually reclassified.

## Classification trigger behavior
- Automatic classification is scheduled after message #3.
- Classification is debounced so only one in-flight classification task runs per conversation.
- Classification work runs on a background task (`Task.detached(priority: .utility)`) and results are persisted on the MainActor.

## Notes
- Legacy folder support (`ChatFolderEntity`) remains alongside `ProjectEntity` to keep migrations incremental.
