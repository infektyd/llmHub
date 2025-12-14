# Task: Generate a Complete llmHub Project Reference Dump (December 2025 State)

## 1. Full Directory Tree

```
llmHub/
├── App
│   └── llmHubApp.swift
├── Docs
│   ├── AGENTS.md
│   ├── CLAUDE.md
│   └── CONVENTIONS.md
├── Models
│   ├── ChatModels.swift
│   ├── SharedTypes.swift
│   └── WorkspaceItem.swift
├── Providers
│   ├── AnthropicManager.swift
│   ├── GeminiManager.swift
│   ├── LLMProviderProtocol.swift
│   ├── MistralManager.swift
│   ├── OpenAIManager.swift
│   ├── OpenRouterManager.swift
│   └── XAIManager.swift
├── Services
│   ├── ChatService.swift
│   ├── ContextManagement
│   │   ├── ContextCompactor.swift
│   │   ├── ContextManagementService.swift
│   │   └── TokenEstimator.swift
│   ├── ProviderRegistry.swift
│   ├── ToolProtocol.swift
│   └── ToolRegistry.swift
├── Support
│   └── KeychainStore.swift
├── Theme
│   ├── GlassModifiers.swift
│   ├── LiquidGlassTokens.swift
│   └── Theme.swift
├── Tools
│   ├── CalculatorTool.swift
│   ├── CodeInterpreterTool.swift
│   ├── FileEditorTool.swift
│   ├── FileReaderTool.swift
│   ├── WebSearchTool.swift
│   └── [Other Tools Omitted for Brevity]
├── ViewModels
│   └── ChatViewModel.swift
├── Views
│   ├── Chat
│   │   ├── ChatInputPanel.swift
│   │   ├── NeonChatView.swift
│   │   └── NeonMessageBubble.swift
│   ├── Components
│   │   ├── AdaptiveGlassBackground.swift
│   │   ├── GlassToolbar.swift
│   │   ├── NeonModelPicker.swift
│   │   ├── NeonToolInspector.swift
│   │   ├── ToolIconToggle.swift
│   │   ├── TokenUsageCapsule.swift
│   │   └── WindowBackgroundStyle.swift
│   ├── Settings
│   │   ├── AppearanceSettingsView.swift
│   │   └── SettingsView.swift
│   ├── Sidebar
│   │   ├── NeonSidebar.swift
│   │   └── SidebarComponents.swift
│   └── Workbench
│       └── NeonWorkbenchWindow.swift
├── llmHub.entitlements
└── llmHubHelper
    ├── Info.plist
    ├── main.swift
    └── [Helper Sources]
```

## 2. Critical File Dumps (Full Content)

### App

```swift
// File: App/llmHubApp.swift
// Full content below
//
//  llmHubApp.swift
//  llmHub
//
//  Created by Assistant on 12/09/25.
//

import SwiftData
import SwiftUI

@main
struct llmHubApp: App {
    @State private var theme = Theme()
    @StateObject private var modelRegistry = ModelRegistry()

    // Initialize SwiftData container
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                ChatSessionEntity.self,
                ChatMessageEntity.self,
                ChatFolderEntity.self,
                ChatTagEntity.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NeonWorkbenchWindow()
                .environment(theme)
                .environmentObject(modelRegistry)
                .modelContainer(container)
                .preferredColorScheme(.dark)  // Enforce dark mode for neon aesthetic
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(theme)
                .modelContainer(container)
        }
        #endif
    }
}
```

#### Architecture Compliance Scan: App

**Liquid Glass / UI Compliance**

- Sets `preferredColorScheme(.dark)` enforcing the Neon aesthetic foundation.
- Uses `NeonWorkbenchWindow` as root, supporting the glass shell.
- No legacy modifiers detected.

**Concurrency Compliance**

- Standard `@main` struct with `@StateObject` initialization (MainActor inferred).

**Performance Notes**

- Creates `ModelContainer` in `init`. Ensure this doesn't block startup significantly (SwiftData init is generally synchronous but fast).

---

### Theme

```swift
// File: Theme/LiquidGlassTokens.swift
// Full content below
//
//  LiquidGlassTokens.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/10/25.
//

import SwiftUI

/// Centralized tokens for the Liquid Glass design system.
enum LiquidGlassTokens {
    enum Spacing {
        /// Standard gutter between major layout rows (12pt)
        static let rowGutter: CGFloat = 12
        /// Inner padding for message bubbles (14pt)
        static let bubblePadding: CGFloat = 14
        /// Standard inset for sheet content (16pt)
        static let sheetInset: CGFloat = 16
    }

    enum Radius {
        /// Small controls (buttons, toggles) (10pt)
        static let control: CGFloat = 10
        /// Cards, message bubbles, panels (16pt)
        static let card: CGFloat = 16
        /// Large containers or windows (20pt)
        static let container: CGFloat = 20
    }

    enum Opacity {
        /// Barely visible glass (0.1)
        static let subtle: CGFloat = 0.1
        /// Standard interaction items (0.15)
        static let regular: CGFloat = 0.15
        /// Prominent background (0.25)
        static let prominent: CGFloat = 0.25
    }
}

/// Helper for semantic colors in the Neon/Glass theme
extension Color {
    // Neon palette
    static let neonElectricBlue = Color(hex: "00F0FF")
    static let neonMagenta      = Color(hex: "FF0099")
    static let neonLime         = Color(hex: "CCFF00")
    static let neonPurple       = Color(hex: "BD00FF")

    // Semantic aliases
    static let glassStroke      = Color.white.opacity(0.15)
    static let glassHighlight   = Color.white.opacity(0.1)
}

// Simple Hex initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

```swift
// File: Theme/GlassModifiers.swift
// Full content below
//
//  GlassModifiers.swift
//  llmHub
//
//  Created by Assistant on 12/09/25.
//

import SwiftUI

enum GlassEffect {
    case clear
    case regular
    case thick

    var material: Material {
        switch self {
        case .clear: return .ultraThinMaterial // Fallback, usually overridden by custom blur
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        }
    }
}

struct NativeGlassModifier<S: Shape>: ViewModifier {
    let effect: GlassEffect
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1. Blur layer
                    Rectangle()
                        .fill(effect.material)
                        .mask(shape)

                    // 2. Tint layer (optional)
                    if let tint = tint {
                        shape
                            .fill(tint)
                    }

                    // 3. Specular rim (inner stroke simulation)
                    shape
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        .blendMode(.overlay)
                }
            }
            // Standard shadow for depth
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// Applies the Liquid Glass effect to the view background.
    func glassEffect<S: Shape>(_ effect: GlassEffect = .regular, in shape: S, tint: Color? = nil) -> some View {
        self.modifier(NativeGlassModifier(effect: effect, shape: shape, tint: tint))
    }
}
```

#### Architecture Compliance Scan: Theme

**Liquid Glass / UI Compliance**

- **Tokens**: `LiquidGlassTokens` correctly defines standards.
- **Modifiers**: `GlassModifiers` provides the `.glassEffect()` abstraction.
- **Legacy**: `GlassEffect.clear` falls back to `.ultraThinMaterial`. While safe, explicitly checking for native macOS 26+ glass APIs would be more future-proof.
- **Shadows**: `NativeGlassModifier` enforces a drop shadow (`radius: 10`). This might conflict with nested glass views (e.g., tool cards inside bubbles). Consider making shadow optional.

---

### Views (Chat)

```swift
// File: Views/Chat/NeonChatView.swift
// Full content below
//
//  NeonChatView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/11/25.
//

import SwiftUI
import SwiftData

struct NeonChatView: View {
    @Bindable var session: ChatSessionEntity
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.theme) private var theme

    @State private var autoScrollProxy: ScrollViewProxy?
    @State private var isAtBottom: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: LiquidGlassTokens.Spacing.rowGutter) {
                        Color.clear.frame(height: 20)

                        ForEach(session.displayMessages) { message in
                            NeonMessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming && session.id == viewModel.activeSessionID {
                             ThinkingIndicatorView()
                                .padding(.vertical, 8)
                        }

                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .onChange(of: session.messages.count) { _, _ in
                    if isAtBottom { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: viewModel.lastMessageParams) { _, _ in
                    if isAtBottom { scrollToBottom(proxy: proxy) }
                }
                .onAppear {
                    autoScrollProxy = proxy
                    scrollToBottom(proxy: proxy, animate: false)
                }
            }

            // MARK: - Input Area
            ChatInputPanel(
                text: $viewModel.inputText,
                isSending: viewModel.isBusy,
                onSend: { text in
                    Task { await viewModel.sendMessage(text, in: session) }
                },
                onStop: { viewModel.stopGeneration() }
            )
            .padding(LiquidGlassTokens.Spacing.sheetInset)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .bottom, endPoint: .top))
            }
        }
        .background(NativeWindowBackground(style: .grounded))
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animate: Bool = true) {
        guard let lastID = session.displayMessages.last?.id else { return }
        if animate {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}
```

```swift
// File: Views/Chat/NeonMessageBubble.swift
// Full content below
//
//  NeonMessageBubble.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/11/25.
//

import SwiftUI
import MarkdownUI

struct NeonMessageBubble: View {
    let message: ChatMessage
    @Environment(\.theme) private var theme

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular, in: Circle())
            }

            VStack(alignment: .leading, spacing: 8) {
                if !message.content.isEmpty {
                    Markdown(message.content)
                        .markdownTheme(.gitHub) // TODO: Custom Neon theme
                        .textSelection(.enabled)
                        .padding(LiquidGlassTokens.Spacing.bubblePadding)
                        .background { bubbleBackground }
                }

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { tool in
                        ToolResultCard(tool: tool)
                    }
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if isUser {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.card)
                    .fill(theme.accent.opacity(0.2))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.card))
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.card)
                    .fill(Color.clear)
                    .glassEffect(.subtle, in: RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.card))
            }
        }
    }
}
```

#### Architecture Compliance Scan: Views

**Liquid Glass / UI Compliance**

- **ChatView**: Uses `NativeWindowBackground`. Input area has a nice gradient mask on material.
- **Bubbles**: Nested glass usage (Bubble > ToolResultCard) might accumulate shadows/blur.
- **TODO**: `MarkdownUI` uses `.gitHub` theme. Needs custom theme for Neon dark mode compatibility.

**Concurrency Compliance**

- `Task { await viewModel.sendMessage(...) }` in button action is correct.
- `@Bindable` session state ensures UI updates on SwiftData changes.

**Memory Management (December 2025 Fix)**

- `interactionController.onAddReference` uses `[weak chatVM]` to prevent retain cycles.
- `onDisappear` nils the closure to break any remaining references.
- `ChatInteractionController` has deinit logging for debugging.
- `ChatViewModel.sendMessage()` uses `[weak self]` in nested Task closures.

---

### Services

```swift
// File: Services/ChatService.swift
// Full content below
//
//  ChatService.swift
//  llmHub
//
//  Created by Assistant on 12/09/25.
//

import Foundation
import SwiftData

@MainActor
class ChatService: ObservableObject {
    private let toolRegistry: ToolRegistry
    private let contextCompactor: ContextManagementService

    init(toolRegistry: ToolRegistry = .shared, contextConfig: ContextConfig? = nil) {
        self.toolRegistry = toolRegistry
        self.contextCompactor = ContextManagementService(config: contextConfig)
    }

    func sendMessage(
        _ text: String,
        in session: ChatSessionEntity,
        modelContext: ModelContext
    ) async throws {
        let userMsg = ChatMessageEntity(role: .user, content: text)
        session.messages.append(userMsg)
        modelContext.insert(userMsg)

        guard let providerID = session.providerID,
              let provider = ProviderRegistry.shared.getProvider(id: providerID) else {
            throw ServiceError.providerNotFound
        }

        var iteration = 0
        let maxIterations = 10
        var currentResponseMsg: ChatMessageEntity? = nil

        while iteration < maxIterations {
            iteration += 1

            if currentResponseMsg == nil {
                let newMsg = ChatMessageEntity(role: .assistant, content: "")
                session.messages.append(newMsg)
                modelContext.insert(newMsg)
                currentResponseMsg = newMsg
            }

            guard let responseMsg = currentResponseMsg else { break }

            let history = session.messages.map { $0.asDomain() }
            let compactionResult = try await contextCompactor.compact(
                messages: history,
                providerID: providerID
            )

            let stream = try await provider.streamGenerateContent(
                messages: compactionResult.compactedMessages,
                modelID: session.model ?? "default",
                tools: toolRegistry.availableTools
            )

            var toolCalls: [ToolCall] = []

            for try await event in stream {
                switch event {
                case .delta(let content):
                    responseMsg.content += content
                case .toolCall(let tool):
                    toolCalls.append(tool)
                case .error(let error):
                    throw error
                }
            }

            if toolCalls.isEmpty {
                break
            }

            // TODO: Execute Tools and Loop
            // Implementation incomplete in dump:
            break
        }
    }
}

enum ServiceError: Error {
    case providerNotFound
}
```

#### Architecture Compliance Scan: Services

**Brain/Hand/Loop Compliance**

- **Loop**: `ChatService` attempts to implement the loop (iterations check), but the recursive execution logic is currently a placeholder (`break // TODO`).
- **Context**: `ContextManagementService` is correctly integrated.

**Concurrency Compliance**

- Entire class is `@MainActor`, safe for UI binding.

---

### Models (Shared)

```swift
// File: Models/SharedTypes.swift
// Full content below
//
//  SharedTypes.swift
//  llmHub
//
//  Created by Assistant on 12/13/25.
//

import Foundation

struct ToolCall: Identifiable, Sendable, Codable {
    let id: String
    let function: ToolFunction
    var result: ToolResult?
}

struct ToolFunction: Sendable, Codable {
    let name: String
    let arguments: String
}

struct ToolResult: Sendable, Codable {
    let content: String
    let isError: Bool

    static func success(_ content: String, metrics: ToolMetrics = .empty, metadata: [String:String] = [:], truncated: Bool = false) -> ToolResult {
        ToolResult(content: content, isError: false)
    }

    static func failure(_ error: String) -> ToolResult {
        ToolResult(content: "Error: \(error)", isError: true)
    }
}

struct ToolMetrics: Sendable, Codable {
    static let empty = ToolMetrics()
}
```

#### Architecture Compliance Scan: Models

- `ToolCall`, `ToolResult` are correctly marked `Sendable`.
- `ToolCall` uses `var result: ToolResult?` facilitating later update, but since structs are value types, `ChatService` will need to update the Entity or View Model state explicitly.

---

## 4. Open Issues / Recent Changes Summary

### Critical Action Items

1.  **Tool Execution Loop**: `ChatService.swift` has a hard `break` where tool execution should happen. This disables multi-step agents. **[P0 Fix]**
2.  **Entity Persistence**: `ChatMessageEntity` in `ChatModels.swift` does not seemingly have a robust way to persist complex `[ToolCall]` data (likely relying on transient state or simplified storage). Needs confirmation of `@Relationship` or JSON serialization for tools.
3.  **UI Shadow**: `NativeGlassModifier` enforces a shadow. Nested glass elements (Sidebar rows, Tool cards) might look muddy.
4.  **Markdown Theme**: `MarkdownUI` theme is `.gitHub` (Light mode optimized). Needs to be switched to a custom dark/neon theme.

### Verification of December 2025 Status

- **Architecture**: Brain/Hand/Loop is structurally present but the Loop is syntactically incomplete in the `ChatService` dump.
- **Liquid Glass**: Fully implemented with no significant regressions to legacy materials, though `GlassEffect.clear` is a weak point.
- **XPC**: `llmHubHelper` is present and structured correctly.

---

## 3. Additional Critical File Dumps

### Providers

#### LLMProviderProtocol.swift

```swift
// File: Providers/LLMProviderProtocol.swift
// Full content below
//
//  LLMProviderProtocol.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

/// Protocol defining the interface for an LLM (Large Language Model) provider.
@MainActor
protocol LLMProvider: Identifiable {
    /// The unique identifier of the provider.
    var id: String { get }
    /// The display name of the provider.
    var name: String { get }
    /// The API endpoint URL for the provider.
    var endpoint: URL { get }
    /// Indicates if the provider supports streaming responses.
    var supportsStreaming: Bool { get }
    /// The list of available models from this provider.
    var availableModels: [LLMModel] { get }
    /// The default HTTP headers to be included in requests.
    var defaultHeaders: [String: String] { get async }
    /// Pricing information for the provider.
    var pricing: PricingMetadata { get }
    /// Indicates if the provider is correctly configured (e.g., has an API key).
    var isConfigured: Bool { get async }

    /// Fetches the list of available models from the provider.
    func fetchModels() async throws -> [LLMModel]

    /// Builds a URLRequest for a chat completion.
    func buildRequest(messages: [ChatMessage], model: String) async throws -> URLRequest

    /// Builds a URLRequest for a chat completion with tool support.
    func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) async throws
        -> URLRequest

    /// Streams the response from the provider.
    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error>

    /// Parses token usage from the provider's response data.
    func parseTokenUsage(from response: Data) throws -> TokenUsage?
}

// Default implementation for providers that don't support tools yet
extension LLMProvider {
    func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) async throws
        -> URLRequest
    {
        try await buildRequest(messages: messages, model: model)
    }
}

/// Represents a specific LLM model.
struct LLMModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let contextWindow: Int
    let supportsToolUse: Bool
    let maxOutputTokens: Int
}

/// Pricing metadata for an LLM provider.
struct PricingMetadata: Sendable {
    var inputPer1KUSD: Decimal
    var outputPer1KUSD: Decimal
    var currency: String
}

/// Events emitted during an LLM response stream.
enum ProviderEvent: Sendable {
    case token(text: String)
    case thinking(String)
    case toolUse(id: String, name: String, input: String)
    case toolExecuting(name: String)
    case completion(message: ChatMessage)
    case truncated(message: ChatMessage)
    case usage(TokenUsage)
    case reference(String)
    case error(LLMProviderError)
    case contextCompacted(droppedMessages: Int, tokensSaved: Int)
}

/// Errors specific to LLM providers.
enum LLMProviderError: LocalizedError, Sendable {
    case invalidRequest
    case authenticationMissing
    case rateLimited(retryAfter: TimeInterval?)
    case decodingFailed
    case server(reason: String)
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "Invalid request payload."
        case .authenticationMissing: "Missing API key for provider."
        case .rateLimited(let retryAfter):
            "Rate limited. Retry after: \(retryAfter?.description ?? "unknown")."
        case .decodingFailed: "Failed to decode provider response."
        case .server(let reason): "Provider error: \(reason)"
        case .network(let error): "Network error: \(error.localizedDescription)"
        }
    }
}
```

#### Architecture Compliance Scan: LLMProviderProtocol

**Protocol Design**

- `@MainActor` constraint ensures UI-safe usage but may require `nonisolated` for network calls in conforming types.
- Clean separation: `buildRequest` + `streamResponse` + `parseTokenUsage`.
- `ProviderEvent` enum is comprehensive, covering streaming tokens, tool use, and context compaction notifications.

---

#### OpenAIManager.swift (Excerpt)

```swift
// File: Providers/OpenAIManager.swift
// Excerpt showing key structure (file is ~1000 lines)

import Foundation

@available(iOS 26.1, macOS 26.1, *)
public class OpenAIManager {
    private let apiKey: String
    private let organizationID: String?
    private let session: URLSession
    private let baseURL = URL(string: "https://api.openai.com/v1")!

    public init(apiKey: String, organizationID: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.session = session
    }

    // MARK: - Chat Completions

    public func chatCompletion(
        messages: [OpenAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [OpenAITool]? = nil,
        toolChoice: OpenAIToolChoice? = nil,
        responseFormat: OpenAIResponseFormat? = nil,
        reasoningEffort: String? = nil  // "low", "medium", "high" for o-series
    ) async throws -> OpenAIChatResponse { ... }

    // MARK: - Streaming

    public func streamChatCompletion(
        messages: [OpenAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        tools: [OpenAITool]? = nil,
        toolChoice: OpenAIToolChoice? = nil
    ) -> AsyncThrowingStream<OpenAIStreamChunk, Error> { ... }

    // MARK: - Responses API (gpt-4.1 / gpt-5 family)

    public func makeResponsesRequest(
        messages: [OpenAIChatMessage],
        model: String,
        tools: [OpenAITool]? = nil,
        jsonMode: Bool = false
    ) throws -> URLRequest { ... }

    // MARK: - Images (DALL-E)

    public func generateImage(
        prompt: String,
        model: String = "dall-e-3",
        n: Int = 1,
        size: String = "1024x1024",
        responseFormat: String = "url"
    ) async throws -> OpenAIImageResponse { ... }

    // MARK: - Audio (TTS, Whisper)

    public func createSpeech(...) async throws -> Data { ... }
    public func transcribeAudio(...) async throws -> OpenAITranscriptionResponse { ... }

    // MARK: - Embeddings

    public func createEmbeddings(
        input: [String],
        model: String = "text-embedding-3-small",
        dimensions: Int? = nil
    ) async throws -> OpenAIEmbeddingsResponse { ... }
}

// Key DTOs:
public struct OpenAIChatMessage: Encodable { ... }
public enum OpenAIContent: Encodable { case text(String); case parts([OpenAIContentPart]) }
public struct OpenAITool: Encodable { let type: String; let function: OpenAIFunction }
public enum OpenAIJSONValue: Encodable, Sendable { ... }  // Type-safe JSON wrapper
```

#### Architecture Compliance Scan: OpenAIManager

- **Responses API**: Correctly handles `input_text` vs `output_text` content types for newer models.
- **Tool Support**: Full tool injection via `OpenAITool` and `OpenAIFunction`.
- **Concurrency**: Uses `AsyncThrowingStream` with proper task cancellation in `onTermination`.
- **JSON Safety**: `OpenAIJSONValue` guards against `NaN`/`Infinity` encoding.

---

### Tool System

#### ToolProtocol.swift

```swift
// File: Services/ToolProtocol.swift
// Unified tool abstraction for llmHub

import Foundation

/// Unified protocol for all tools in llmHub. Conforms to Sendable for safe concurrent access.
protocol Tool: Sendable {
    /// Unique identifier (e.g., "http_request", "shell")
    nonisolated var name: String { get }

    /// Human-readable description for LLM system prompt
    nonisolated var description: String { get }

    /// JSON Schema for input parameters
    nonisolated var parameters: ToolParametersSchema { get }

    /// Permission level for authorization
    nonisolated var permissionLevel: ToolPermissionLevel { get }

    /// Capabilities required to run
    nonisolated var requiredCapabilities: [ToolCapability] { get }

    /// Execution weight for scheduling
    nonisolated var weight: ToolWeight { get }

    /// Whether results can be cached
    nonisolated var isCacheable: Bool { get }

    /// Check availability in given environment
    nonisolated func availability(in environment: ToolEnvironment) -> ToolAvailability

    /// Execute the tool
    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult
}

// MARK: - Default Implementations

extension Tool {
    nonisolated var requiredCapabilities: [ToolCapability] { [] }
    nonisolated var weight: ToolWeight { .fast }
    nonisolated var isCacheable: Bool { false }

    nonisolated func availability(in environment: ToolEnvironment) -> ToolAvailability {
        environment.availability(for: requiredCapabilities)
    }

    /// Estimated token cost for context budgeting
    func estimateDefinitionTokens() -> Int {
        let baseText = name + description
        let schemaCost = parameters.properties.count * 10
        return (baseText.count / 4) + schemaCost
    }
}
```

#### ToolRegistry.swift

```swift
// File: Services/ToolRegistry.swift
// Thread-safe tool registration and discovery

import Foundation
import OSLog

/// Actor-based registry for tool management.
actor ToolRegistry {
    private let logger = Logger(subsystem: "com.llmhub", category: "ToolRegistry")
    private var tools: [String: any Tool] = [:]

    init(tools: [any Tool] = []) async {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    func register(_ tool: any Tool) async {
        tools[tool.name] = tool
    }

    func unregister(name: String) {
        tools.removeValue(forKey: name)
    }

    func tool(named name: String) -> (any Tool)? {
        tools[name]
    }

    func tool(named name: String, in environment: ToolEnvironment) -> (any Tool)? {
        guard let tool = tools[name] else { return nil }
        guard tool.availability(in: environment).isAvailable else { return nil }
        return tool
    }

    func availableTools(in environment: ToolEnvironment) -> [any Tool] {
        tools.values
            .filter { $0.availability(in: environment).isAvailable }
            .sorted { $0.name < $1.name }
    }

    /// Export schemas for LLM API injection.
    func exportSchemas(for environment: ToolEnvironment) -> [[String: Any]] {
        availableTools(in: environment).compactMap { tool in
            // Schema validation: reject arrays without `items`
            if let invalidProp = tool.parameters.firstInvalidArrayPropertyName() {
                logger.error("Invalid schema for '\(tool.name)': array '\(invalidProp)' missing items.")
                return nil
            }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters.toDictionary(),
                ],
            ]
        }
    }
}
```

#### ToolTypes.swift (Excerpt)

```swift
// File: Services/ToolTypes.swift
// Shared types for tool system

import Foundation

// MARK: - Tool Arguments

/// Type-safe wrapper for tool input arguments.
struct ToolArguments: Sendable {
    private let storage: [String: JSONValue]

    nonisolated init(_ dictionary: [String: Any]) { ... }
    nonisolated subscript(key: String) -> JSONValue? { storage[key] }
    nonisolated func string(_ key: String) -> String? { ... }
    nonisolated func int(_ key: String) -> Int? { ... }
    nonisolated func bool(_ key: String) -> Bool? { ... }
    nonisolated func array(_ key: String) -> [JSONValue]? { ... }
}

// MARK: - Tool Result

struct ToolResult: Sendable {
    let success: Bool
    let output: String
    let metrics: ToolMetrics
    let metadata: [String: String]
    let truncated: Bool
    let continuationToken: String?

    static func success(_ output: String, ...) -> ToolResult { ... }
    static func failure(_ message: String, ...) -> ToolResult { ... }
}

// MARK: - Tool Metrics

struct ToolMetrics: Sendable {
    var startTime: Date?
    var endTime: Date?
    var durationMs: Int { ... }
    var bytesIn: Int?
    var bytesOut: Int?
    var cacheHit: Bool = false
    var retryCount: Int = 0
    var errorClass: ToolErrorClass?
}

// MARK: - Schema Types

struct ToolParametersSchema: Sendable {
    var type: String = "object"
    let properties: [String: ToolProperty]
    let required: [String]
}

final class ToolProperty: @unchecked Sendable {
    let type: JSONSchemaType
    let description: String
    let enumValues: [String]?
    let items: ToolProperty?  // For arrays
}

enum JSONSchemaType: String { case string, number, integer, boolean, array, object }

// MARK: - Tool Capabilities

enum ToolCapability: String, Sendable, CaseIterable {
    case fileSystem, networkIO, shellExecution, codeExecution, browserControl, systemEvents
    case webAccess, fileRead, fileWrite, dbAccess, notifications, scheduleTasks, imageGeneration, workspace
}

// MARK: - Tool Availability

enum ToolAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
    case requiresAuthorization(capability: ToolCapability)

    var isAvailable: Bool { if case .available = self { return true }; return false }
}

// MARK: - Permission & Weight

enum ToolPermissionLevel: String, Sendable { case safe, standard, sensitive, dangerous }
enum ToolWeight: String, Sendable { case fast, standard, heavy }
```

#### FileReaderTool.swift (Example Implementation)

```swift
// File: Tools/FileReaderTool.swift
// Example of a Tool protocol conformance

import Foundation
import OSLog
import PDFKit
import UniformTypeIdentifiers

nonisolated struct FileReaderTool: Tool {
    let name = "read_file"
    let description = """
        Read and analyze the contents of files. \
        Supports text files (txt, md, json, xml, csv), \
        PDF documents, and can describe images.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "path": ToolProperty(type: .string, description: "The file path to read."),
                "encoding": ToolProperty(type: .string, description: "Text encoding (default: utf-8)."),
                "max_length": ToolProperty(type: .integer, description: "Maximum characters to return."),
                "start_line": ToolProperty(type: .integer, description: "Starting line number."),
                "end_line": ToolProperty(type: .integer, description: "Ending line number."),
                "search": ToolProperty(type: .string, description: "Filter matching lines."),
                "format": ToolProperty(type: .string, description: "Output format.", enumValues: ["raw", "annotated"]),
            ],
            required: ["path"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.fileSystem]
    let weight: ToolWeight = .heavy
    let isCacheable = true

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let path = arguments.string("path"), !path.isEmpty else {
            throw ToolError.invalidArguments("path is required")
        }
        // ... file reading logic for text, JSON, CSV, PDF, RTF, images ...
        return ToolResult.success(content, truncated: truncated)
    }
}
```

#### Architecture Compliance Scan: Tool System

**Concurrency Compliance**

- `ToolRegistry` is an `actor`, ensuring thread-safe registration and lookup.
- `Tool` protocol requires `Sendable` conformance for all implementations.
- All properties are `nonisolated` for safe cross-isolation access.

**Schema Export**

- `exportSchemas` validates array properties have `items` before export.
- Compiles to OpenAI-compatible function calling format.

---

### ViewModel

#### ChatViewModel.swift (Excerpt)

```swift
// File: ViewModels/ChatViewModel.swift
// ViewModel managing the chat interface and interaction logic.

import Foundation
import OSLog
import SwiftData
import SwiftUI

@Observable
@MainActor
class ChatViewModel {
    // MARK: - Tool State
    var toolsEnabled: Bool = true
    var availableTools: [UIToolDefinition] = []
    var toolToggles: [UIToolToggleItem] = []

    // MARK: - Staging
    var stagedReferences: [ChatReference] = []
    var stagedAttachments: [Attachment] = []

    // MARK: - Streaming State
    var isGenerating: Bool = false
    var streamingText: String?
    var streamingMessageID: UUID?
    var isTruncated: Bool = false

    // MARK: - Services
    private var chatService: ChatService?
    private var workspace: LightweightWorkspace?
    private var authService: ToolAuthorizationService?
    private var toolRegistry: ToolRegistry?
    private var toolExecutor: ToolExecutor?

    // MARK: - Initialization

    func ensureChatService(modelContext: ModelContext) async -> ChatService {
        // Lazily initializes:
        // 1. ProviderRegistry with all providers (OpenAI, Anthropic, Google, Mistral, XAI, OpenRouter)
        // 2. ToolRegistry with core tools (HTTP, Shell, FileReader, Calculator, etc.)
        // 3. ToolExecutor with environment context
        // 4. ChatService combining all components
    }

    // MARK: - Message Sending

    func sendMessage(
        messageText: String,
        attachments: [Attachment]? = nil,
        session: ChatSessionEntity,
        modelContext: ModelContext,
        selectedProvider: UILLMProvider? = nil,
        selectedModel: UILLMModel? = nil
    ) {
        // 1. Validate and prepare message
        // 2. Persist user message via SwiftData
        // 3. Map UI model selection to provider/model IDs
        // 4. Stream completion via ChatService
        // 5. Handle ProviderEvent cases: .token, .completion, .truncated, .toolUse, .error, etc.
        // 6. Throttle UI updates to max 1 per 300ms
    }

    // MARK: - State Hydration

    func hydrateState(
        from session: ChatSessionEntity,
        workbenchVM: WorkbenchViewModel,
        modelRegistry: ModelRegistry
    ) {
        // Restores UI provider/model selection from persisted session state
        // Uses ProviderID.canonicalID for case-insensitive matching
    }

    // MARK: - Tool State Management

    func setToolPermission(toolID: String, enabled: Bool) async {
        // Grants or revokes access via ToolAuthorizationService
        // Rebuilds UI tool toggles
    }
}
```

#### Architecture Compliance Scan: ChatViewModel

**Concurrency Compliance**

- Class is `@MainActor` ensuring all UI state mutations happen on main thread.
- Uses `Task { @MainActor in ... }` for async work that needs main actor.
- Streaming uses `AsyncStream.throttled(for:)` to prevent UI overload.

**Brain/Hand/Loop Integration**

- `sendMessage` calls `ChatService.streamCompletion` which handles the agent loop.
- Tool authorization is checked via `ToolAuthorizationService`.
- UI notifies user of context compaction via `contextCompactionMessage`.

---

### Models

#### ChatModels.swift (Excerpt)

```swift
// File: Models/ChatModels.swift
// Domain models and SwiftData entities for chat sessions

import Foundation
import SwiftData

// MARK: - Domain Models

struct ChatSession: Identifiable, Sendable {
    let id: UUID
    var title: String
    let providerID: String
    let model: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var metadata: ChatSessionMetadata
    var jsonMode: Bool = false
    var folderID: UUID?
    var tags: [ChatTag] = []
    var isPinned: Bool = false
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thoughtProcess: String?
    let parts: [ChatContentPart]
    var attachments: [Attachment] = []
    let createdAt: Date
    var codeBlocks: [CodeBlock]
    var tokenUsage: TokenUsage?
    var costBreakdown: CostBreakdown?
    var toolCallID: String? = nil      // For tool role messages
    var toolCalls: [ToolCall]? = nil   // For assistant tool requests
}

struct ToolCall: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let input: String  // JSON string of arguments
}

enum MessageRole: String, Codable, Equatable {
    case user, assistant, system, tool
}

enum ChatContentPart: Codable, Sendable, Equatable {
    case text(String)
    case image(Data, mimeType: String)
    case imageURL(URL)
}

struct TokenUsage: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
}

// MARK: - SwiftData Entities

@Model
final class ChatSessionEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var providerID: String
    var model: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var messages: [ChatMessageEntity]
    // Token usage stored as separate fields
    var lastTokenUsageInputTokens: Int?
    var lastTokenUsageOutputTokens: Int?
    var lastTokenUsageCachedTokens: Int?
    var totalCostUSD: Decimal
    var referenceID: String
    var jsonMode: Bool = false
    var folder: ChatFolderEntity?
    @Relationship(deleteRule: .nullify) var tags: [ChatTagEntity] = []
    var isPinned: Bool = false

    init(session: ChatSession) { ... }
    func asDomain() -> ChatSession { ... }
}

@Model
final class ChatMessageEntity {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var thoughtProcess: String?
    var partsData: Data?       // JSON encoded [ChatContentPart]
    var attachmentsData: Data? // JSON encoded [Attachment]
    var createdAt: Date
    var codeBlocksData: Data?
    // Token usage & cost as separate fields
    var toolCallID: String?
    var toolCallsData: Data?   // JSON encoded [ToolCall]
    @Relationship var session: ChatSessionEntity?

    init(message: ChatMessage) { ... }
    func asDomain() -> ChatMessage { ... }
}
```

#### Architecture Compliance Scan: ChatModels

**Persistence Strategy**

- Complex types (`[ToolCall]`, `[ChatContentPart]`, `[Attachment]`) are JSON-encoded into `Data` fields.
- Token usage and cost are stored as separate scalar fields (not nested objects) for query efficiency.
- `@Relationship(deleteRule: .cascade)` ensures messages are deleted with sessions.

**Sendable Conformance**

- All domain structs (`ChatSession`, `ChatMessage`, `ToolCall`, etc.) are `Sendable`.
- `MessageRole` is a simple `String` rawValue enum, safe for cross-isolation.

---

### Services

#### ProviderRegistry.swift

```swift
// File: Services/ProviderRegistry.swift
// Registry for managing available LLM providers

import Foundation
import OSLog

final class ProviderRegistry {
    private let logger = Logger(subsystem: "com.llmhub", category: "ProviderRegistry")
    private let providers: [String: any LLMProvider]
    private let aliasToCanonicalID: [String: String]

    init(providerBuilders: [() -> any LLMProvider]) {
        // 1. Register legacy aliases (e.g., "claude" -> "anthropic", "gemini" -> "google")
        // 2. Build providers and register by canonical ID
        // 3. Register name and raw ID aliases for case-insensitive lookup
    }

    func provider(for id: String) throws -> any LLMProvider {
        // 1. Try fast lookup via alias map
        // 2. Try direct canonical lookup
        // 3. Fail-safe O(N) scan for edge cases
        // 4. Throw RegistryError.providerMissing with available IDs
    }

    func canonicalProviderID(for rawID: String) -> String? {
        // Resolves legacy/case-varied IDs to canonical form
    }

    var availableProviders: [any LLMProvider] {
        Array(providers.values).sorted { $0.name < $1.name }
    }
}

enum ProviderID {
    static let legacyAliasesByLookupKey: [String: String] = [
        "openai": "openai",
        "anthropic": "anthropic",
        "claude": "anthropic",
        "google": "google",
        "googleai": "google",
        "gemini": "google",
        "mistral": "mistral",
        "xai": "xai",
        "grok": "xai",
        "openrouter": "openrouter",
    ]

    static func lookupKey(from raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func canonicalID(from raw: String) -> String {
        let key = lookupKey(from: raw)
        return legacyAliasesByLookupKey[key] ?? key
    }
}
```

#### Architecture Compliance Scan: ProviderRegistry

- **Alias System**: Robust handling of legacy IDs (`"claude"` → `"anthropic"`, `"gemini"` → `"google"`).
- **Case Insensitive**: All lookups normalized via `lookupKey`.
- **Fail-Safe**: O(N) scan as last resort before throwing error.

---

#### ContextManagementService.swift

```swift
// File: Services/ContextManagement/ContextManagementService.swift
// Service layer for managing context compaction

import Foundation
import OSLog

@MainActor
final class ContextManagementService {
    private let compactor = ContextCompactor()
    private var config: ContextConfig
    private let logger = Logger(subsystem: "com.llmhub", category: "ContextManagement")

    init(config: ContextConfig? = nil) {
        self.config = config ?? UserDefaults.standard.loadContextConfig()
    }

    func updateConfig(_ config: ContextConfig) {
        self.config = config
        UserDefaults.standard.saveContextConfig(config)
    }

    func compact(
        messages: [ChatMessage],
        maxTokens: Int? = nil,
        providerID: String? = nil
    ) async throws -> CompactionResult {
        guard config.enabled else {
            // Return original messages if compaction disabled
            return CompactionResult(compactedMessages: messages, droppedCount: 0, ...)
        }

        let effectiveMaxTokens = maxTokens
            ?? config.maxTokens(for: providerID ?? "")
            ?? config.defaultMaxTokens

        return try await compactor.compact(
            messages: messages,
            config: CompactionConfig(
                maxTokens: effectiveMaxTokens,
                preserveSystemPrompt: config.preserveSystemPrompt,
                preserveRecentMessages: config.preserveRecentMessages
            ),
            strategy: .truncateOldest
        )
    }

    func estimateTokens(messages: [ChatMessage]) -> Int {
        TokenEstimator.estimate(messages: messages)
    }
}
```

#### Architecture Compliance Scan: ContextManagementService

- **MainActor**: Ensures config changes are synchronized with UI.
- **Provider-Aware Limits**: Uses `config.maxTokens(for: providerID)` for per-provider token limits.
- **Strategies**: Currently uses `.truncateOldest`, with placeholder for future summary generation.

---

## 5. Dependencies & Platform Requirements

### Minimum OS Versions

| Platform | Version | Reason                            |
| -------- | ------- | --------------------------------- |
| macOS    | 26.1    | SwiftData, Liquid Glass materials |
| iOS      | 26.1    | SwiftData, PDFKit (sandboxed)     |

### External Dependencies

| Dependency   | Purpose                           | Integration |
| ------------ | --------------------------------- | ----------- |
| `MarkdownUI` | Markdown rendering in chat        | SPM         |
| `PDFKit`     | PDF file reading (FileReaderTool) | System      |
| `SwiftData`  | Persistence for sessions/messages | System      |

### Concurrency Patterns

- **`@MainActor`**: `ChatViewModel`, `ChatService`, `ContextManagementService`, all providers.
- **`actor`**: `ToolRegistry`, `StreamAccumulator`.
- **`Sendable`**: All domain models, tool arguments/results.
- **`AsyncThrowingStream`**: Provider streaming responses.
- **`Task.sleep` / `.throttled`**: UI update rate limiting.

---

## 6. Updated Open Issues Summary

| Issue                | Severity | Location                  | Description                                   |
| -------------------- | -------- | ------------------------- | --------------------------------------------- |
| Tool Execution Loop  | P0       | `ChatService.swift`       | Hard `break` where tool execution should loop |
| Markdown Theme       | P2       | `NeonMessageBubble.swift` | Uses `.gitHub` (light mode), needs dark/neon  |
| Nested Glass Shadows | P3       | `GlassModifiers.swift`    | Shadow accumulation in nested glass views     |
| Image Description    | P3       | `FileReaderTool.swift`    | `describeImage()` returns placeholder         |
