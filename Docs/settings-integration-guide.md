# Settings Integration Guide

This guide shows how to wire the new SettingsManager to existing UI components.

---

## 1. Font Scaling

### Create Font Extension

```swift
// Add to Utilities/AppColors.swift or create new file Utilities/Font+Scaling.swift

import SwiftUI

extension Font {
    /// Scales a font by the user's fontSize preference
    func scaled(by factor: CGFloat) -> Font {
        // This is a simple multiplier approach
        // For iOS, you might want to use .system(.body).weight(.regular) with custom size
        return self
    }
}

extension View {
    /// Applies user's font size preference to body text
    func scaledBody(_ settingsManager: SettingsManager) -> some View {
        self.font(.system(size: 14 * settingsManager.settings.fontSize))
    }
}
```

### Apply in MessageRow or Transcript

```swift
struct MessageRow: View {
    @Environment(\.settingsManager) private var settingsManager

    var body: some View {
        Text(message.content)
            .font(.system(size: 14 * settingsManager.settings.fontSize))
    }
}
```

---

## 2. Compact Mode Spacing

### Update TranscriptView

```swift
struct TranscriptCanvasView: View {
    @Environment(\.settingsManager) private var settingsManager

    private var messageSpacing: CGFloat {
        settingsManager.settings.compactMode ? 8 : 12
    }

    var body: some View {
        VStack(spacing: messageSpacing) {
            ForEach(messages) { message in
                MessageRow(message: message)
            }
        }
    }
}
```

### Update Card Padding

```swift
.padding(settingsManager.settings.compactMode ? 12 : 16)
```

---

## 3. Token Count Visibility

### Update Message Header

```swift
struct MessageHeader: View {
    @Environment(\.settingsManager) private var settingsManager
    let message: ChatMessage

    var body: some View {
        HStack {
            Text(message.role.rawValue.capitalized)
            Spacer()

            // Only show if enabled
            if settingsManager.settings.showTokenCounts,
               let tokens = message.tokenUsage {
                TokenBadge(count: tokens.total)
            }
        }
    }
}
```

---

## 4. Tool Permissions Filter

### Update ComposerBar

```swift
struct Composer: View {
    @Environment(\.settingsManager) private var settingsManager
    @State private var chatVM: ChatViewModel

    private var availableTools: [UIToolToggleItem] {
        chatVM.toolToggles.filter { tool in
            settingsManager.isToolEnabled(tool.id)
        }
    }

    var body: some View {
        // Use availableTools instead of chatVM.toolToggles
        ToolPicker(tools: availableTools)
    }
}
```

---

## 5. Auto-scroll Behavior

### Update TranscriptView Scroll Logic

```swift
struct TranscriptCanvasView: View {
    @Environment(\.settingsManager) private var settingsManager
    @Namespace private var bottomID

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
            }
            .onChange(of: messages.count) { _, _ in
                // Only auto-scroll if enabled
                if settingsManager.settings.autoScroll {
                    withAnimation {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }
}
```

---

## 6. Streaming Throttle

### Update ChatViewModel

```swift
@MainActor
final class ChatViewModel: ObservableObject {
    // ...

    func streamMessage() async {
        var throttle: TimeInterval {
            // Convert updates/sec to delay between updates
            1.0 / Double(settingsManager.settings.streamingThrottle)
        }

        for try await chunk in stream {
            // Accumulate chunk
            currentMessage.append(chunk)

            // Throttle UI updates
            try? await Task.sleep(nanoseconds: UInt64(throttle * 1_000_000_000))

            // Update UI
            self.streamingMessage = currentMessage
        }
    }
}
```

Or use existing AsyncStream throttling:

```swift
for try await chunk in stream.throttle(
    maxUpdatesPerSecond: settingsManager.settings.streamingThrottle
) {
    // ...
}
```

---

## 7. Network Timeout

### Update LLM Providers

```swift
final class OpenAIProvider: LLMProvider {
    private let settingsManager: SettingsManager

    func sendRequest() async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = settingsManager.settings.networkTimeout

        let (data, _) = try await URLSession.shared.data(for: request)
        // ...
    }
}
```

---

## 8. Max Context Tokens

### Update Context Builder

```swift
func buildContext(messages: [ChatMessage]) -> [ChatMessage] {
    let maxTokens = settingsManager.settings.maxContextTokens

    var context: [ChatMessage] = []
    var totalTokens = 0

    for message in messages.reversed() {
        let messageTokens = estimateTokens(message)
        if totalTokens + messageTokens > maxTokens {
            break
        }
        context.insert(message, at: 0)
        totalTokens += messageTokens
    }

    return context
}
```

---

## 9. Context Compaction

### Update ChatViewModel

```swift
private func prepareContext() -> [ChatMessage] {
    if settingsManager.settings.contextCompactionEnabled {
        return compactContext(messages)
    } else {
        return messages
    }
}

private func compactContext(_ messages: [ChatMessage]) -> [ChatMessage] {
    // Summarize older messages if over token limit
    // Keep recent messages in full
    // ...
}
```

---

## 10. Summary Generation

### Update Session Save Logic

```swift
func saveSession() async {
    if settingsManager.settings.summaryGenerationEnabled {
        let summary = await generateSummary(session)
        session.summary = summary
    }
    try? modelContext.save()
}
```

---

## 11. Recent Session Limit

### Update Sidebar Query

```swift
struct SidebarView: View {
    @Environment(\.settingsManager) private var settingsManager
    @Query private var allSessions: [ChatSessionEntity]

    private var recentSessions: [ChatSessionEntity] {
        Array(
            allSessions
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(settingsManager.settings.recentSessionLimit)
        )
    }

    var body: some View {
        List(recentSessions) { session in
            SessionRow(session: session)
        }
    }
}
```

---

## 12. Auto-save Interval

### Update WorkbenchViewModel

```swift
@MainActor
final class WorkbenchViewModel: ObservableObject {
    private var autoSaveTask: Task<Void, Never>?

    func startAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        settingsManager.settings.autoSaveInterval * 1_000_000_000
                    )
                )
                guard !Task.isCancelled else { break }
                saveCurrentState()
            }
        }
    }
}
```

---

## 13. Provider Defaults

### Update on Launch

```swift
// In RootView or ContentView
.onAppear {
    if viewModel.selectedProvider == nil {
        // Use default provider from settings
        if let provider = modelRegistry.provider(
            id: settingsManager.settings.defaultProviderID
        ) {
            viewModel.selectedProvider = provider
        }
    }

    if viewModel.selectedModel == nil {
        // Use default model from settings
        if let model = modelRegistry.model(
            name: settingsManager.settings.defaultModel
        ) {
            viewModel.selectedModel = model
        }
    }
}
```

---

## Quick Reference

### Environment Access

```swift
@Environment(\.settingsManager) private var settingsManager
```

### Direct Property Access

```swift
settingsManager.settings.compactMode
settingsManager.settings.fontSize
settingsManager.settings.autoScroll
```

### Convenience Methods

```swift
settingsManager.isToolEnabled("web_search")
settingsManager.setToolEnabled("shell", enabled: false)
```

### Observable Updates

Settings changes automatically trigger SwiftUI updates because SettingsManager is `@Observable`.

---

## Testing Integration

1. Change setting in Settings view
2. Verify immediate update in main UI
3. Quit and relaunch app
4. Verify setting persisted
5. Reset to defaults
6. Verify all settings reverted

---

## Common Patterns

### Conditional UI

```swift
if settingsManager.settings.showTokenCounts {
    TokenBadge()
}
```

### Dynamic Spacing

```swift
VStack(spacing: settingsManager.settings.compactMode ? 8 : 12) {
    // ...
}
```

### Scaled Fonts

```swift
.font(.system(size: 14 * settingsManager.settings.fontSize))
```

### Throttled Streams

```swift
stream.throttle(maxUpdatesPerSecond: settingsManager.settings.streamingThrottle)
```

---

## Performance Notes

- SettingsManager uses `@Observable`, so only views actually using the setting will update
- Debounced saves prevent excessive UserDefaults writes
- All validation happens on property set, not on read
- Environment injection is efficient (not creating new instances)

---

## Migration Checklist

Per integration point:

- [ ] Add `@Environment(\.settingsManager)` to view
- [ ] Read setting value
- [ ] Apply to UI/logic
- [ ] Test live update
- [ ] Test persistence
- [ ] Remove any `@AppStorage` if applicable
- [ ] Document behavior
