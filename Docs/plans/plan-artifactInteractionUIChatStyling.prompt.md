## Plan: Artifact Detail + Transcript Polish

Implement user-only message bubbles, cleaned model names, configurable user emote, AFM-selected assistant emote, and an artifact detail inspector with comment-to-chat flow. Use existing llmHub patterns: `AppColors` tokens, transcript view-model mapping in `TranscriptCanvasSessionView`, settings via `SettingsManager`, and artifact payload generation via `ArtifactService`. Prefer a single cross-platform sheet presenter first (macOS + iOS), with an optional macOS window upgrade if desired.

### Steps
1. Add `AppColors.userBubble` in [llmHub/Utilities/AppColors.swift](llmHub/Utilities/AppColors.swift) (Dark/Light + adaptive static).
2. Apply user-only bubble styling around `TextualMessageView` in `TranscriptRow` inside [llmHub/Views/UI/Transcript/MessageRow.swift](llmHub/Views/UI/Transcript/MessageRow.swift), ensuring header (`roleLabel`) stays outside.
3. Implement model display cleanup: update `TranscriptCanvasSessionView.providerLabel()` in [llmHub/Views/UI/TranscriptView.swift](llmHub/Views/UI/TranscriptView.swift) to prefer registry `displayName`, fallback to a new `cleanModelName` utility in [llmHub/Utilities/ModelNameFormatter.swift](llmHub/Utilities/ModelNameFormatter.swift); then route `TranscriptRowViewModel.headerLabel` in [llmHub/Views/UI/Transcript/Models.swift](llmHub/Views/UI/Transcript/Models.swift) through the cleaned name.
4. Add `userEmote` to `AppSettings` in [llmHub/Models/Core/AppSettings.swift](llmHub/Models/Core/AppSettings.swift), bind a picker/grid in `AppearanceSection` in [llmHub/Views/Settings/SettingsView.swift](llmHub/Views/Settings/SettingsView.swift), and prepend it to the user header label where `mapToViewModel` currently sets `"You"` in [llmHub/Views/UI/TranscriptView.swift](llmHub/Views/UI/TranscriptView.swift).
5. Expand AFM emoji options in [llmHub/Services/Conversation/ConversationClassificationService.swift](llmHub/Services/Conversation/ConversationClassificationService.swift), then inject `session.afmEmoji` into assistant header construction in `TranscriptCanvasSessionView.mapToViewModel` in [llmHub/Views/UI/TranscriptView.swift](llmHub/Views/UI/TranscriptView.swift), defaulting to a stable fallback when missing.
6. Build artifact inspection: add `ArtifactComment` model in [llmHub/ViewModels/Models/ArtifactTypes.swift](llmHub/ViewModels/Models/ArtifactTypes.swift) (or a new model file), create [llmHub/Views/UI/Artifacts/ArtifactDetailView.swift](llmHub/Views/UI/Artifacts/ArtifactDetailView.swift), wire tap from [llmHub/Views/UI/Transcript/ArtifactCardView.swift](llmHub/Views/UI/Transcript/ArtifactCardView.swift) to a selection state + sheet presenter in [llmHub/Views/UI/RootView.swift](llmHub/Views/UI/RootView.swift), and implement comment submission to send a new user message via the existing send path in [llmHub/ViewModels/Core/ChatViewModel.swift](llmHub/ViewModels/Core/ChatViewModel.swift).

### Further Considerations
1. macOS artifact presentation: start with sheet first (cross-platform). Non-modal window is a nice-to-have later.
2. Comment flow: send immediately per submit (simpler, matches chat).
3. Default `userEmote`: use `"🧑‍💻"`.
