//
//  ChatViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI

/// ViewModel managing the chat interface and interaction logic.
@Observable
@MainActor
class ChatViewModel {
    /// Indicates whether tools are enabled for the current session.
    var toolsEnabled: Bool = true
    /// The list of tools available to the user.
    var availableTools: [UIToolDefinition] = []
    /// Tool toggle metadata for UI (availability + permissions).
    var toolToggles: [UIToolToggleItem] = []

    /// Staged references for the next message.
    var stagedReferences: [ChatReference] = []

    /// Staged attachments for the next message.
    var stagedAttachments: [Attachment] = []

    /// Indicates whether the view model is currently streaming/generating a response.
    var isGenerating: Bool = false

    // ... existing properties ...

    /// Adds a reference to the staging area.
    func addReference(_ reference: ChatReference) {
        let alreadyStaged = stagedReferences.contains { existing in
            if existing.id == reference.id { return true }
            return existing.text == reference.text && existing.sourceMessageID == reference.sourceMessageID
        }
        if !alreadyStaged {
            stagedReferences.append(reference)
        }
    }

    /// Removes a reference from the staging area.
    func removeReference(at index: Int) {
        guard index >= 0 && index < stagedReferences.count else { return }
        stagedReferences.remove(at: index)
    }

    // ...

    /// Tracks the latest message the UI should keep in view.
    var lastVisibleMessageID: UUID?
    /// Current streaming text buffer for the assistant.
    var streamingText: String?
    /// Notification message for context compaction.
    var contextCompactionMessage: String?
    /// Whether to show the context compaction notification.
    var showContextCompactionNotification: Bool = false
    /// Indicates the response was truncated due to max_tokens limit.
    var isTruncated: Bool = false
    /// The session ID of the truncated response (for continuation).
    var truncatedSessionID: UUID?
    /// The message displayed for streaming tokens.
    var streamingDisplayMessage: ChatMessage? {
        guard let messageID = streamingMessageID,
            let startedAt = streamingStartedAt,
            let streamingText = streamingText
        else { return nil }

        return ChatMessage(
            id: messageID,
            role: .assistant,
            content: streamingText,
            thoughtProcess: nil,
            parts: [],
            createdAt: startedAt,
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil,
            toolCallID: nil,
            toolCalls: nil
        )
    }

    /// Indicates the model is thinking but hasn't started streaming yet
    var isThinking: Bool {
        isGenerating && (streamingText == nil || streamingText?.isEmpty == true)
    }

    /// Indicates content is actively streaming
    var isActivelyStreaming: Bool {
        isGenerating && streamingText != nil && !streamingText!.isEmpty
    }

    /// The chat service for LLM interactions.
    private var chatService: ChatService?
    /// Streaming accumulator for incoming tokens.
    private let streamAccumulator = StreamAccumulator()
    /// Identifier for the current streaming message.
    private var streamingMessageID: UUID?
    /// Timestamp for the streaming message.
    private var streamingStartedAt: Date?

    // Core Actors
    private var workspace: LightweightWorkspace?
    private var authService: ToolAuthorizationService?
    private var toolRegistry: ToolRegistry?
    private var toolExecutor: ToolExecutor?
    private var toolEnvironment: ToolEnvironment = .current

    /// Tracks model keys we've already warned about to avoid log spam.
    /// Key format: "providerID:modelID"
    private static var loggedMissingModels: Set<String> = []

    /// Logger for debugging.
    private let logger = Logger(subsystem: "com.llmhub", category: "ChatViewModel")

    // This would be initialized with a specific session entity in a real app
    // For now, it manages the transient state of the chat view

    init() {
        // Initialize with default static tools until registry loads
        self.availableTools = UIToolDefinition.defaultTools(for: ToolEnvironment.current)
    }

    /// Initializes the ChatService lazily when needed.
    func ensureChatService(modelContext: ModelContext) async -> ChatService {
        if let service = chatService {
            return service
        }

        // Initialize providers config
        let config = makeDefaultConfig()

        // Initialize keychain
        let keychain = KeychainStore()

        // Try to get OpenAI key from environment first, then keychain
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            logger.info("Found OpenAI API key in environment")
            try? await keychain.updateKey(envKey, for: .openAI)
        }

        // Initialize provider registry with ALL providers
        // Providers will check keychain for API keys dynamically when making requests
        let registry = ProviderRegistry(providerBuilders: [
            { OpenAIProvider(keychain: keychain, config: config.openAI) },
            { AnthropicProvider(keychain: keychain, config: config.anthropic) },
            { MistralProvider(keychain: keychain, config: config.mistral) },
            { GoogleAIProvider(keychain: keychain, config: config.googleAI) },
            { XAIProvider(keychain: keychain, config: config.xai) },
            { OpenRouterProvider(keychain: keychain, config: config.openRouter) },
        ])

        let baseEnvironment = ToolEnvironment.current
        #if os(macOS)
            let backendAvailable = await CodeExecutionEngine().isBackendAvailable
            let toolEnvironment = ToolEnvironment(
                platform: baseEnvironment.platform,
                isSimulator: baseEnvironment.isSimulator,
                hasCodeExecutionBackend: backendAvailable,
                sandboxRoot: baseEnvironment.sandboxRoot
            )
        #else
            let toolEnvironment = baseEnvironment
        #endif

        // Initialize Actors
        let workspace = LightweightWorkspace()
        let authService = ToolAuthorizationService()
        self.workspace = workspace
        self.authService = authService

        // Initialize Tools
        let tools: [any Tool] = [
            HTTPRequestTool(),
            ShellTool(),
            FileReaderTool(),
            CalculatorTool(),
            WebSearchTool(),
            FileEditorTool(),
            FilePatchTool(),
            WorkspaceTool(),
        ]

        let toolRegistry = ToolRegistry(tools: tools)
        let toolExecutor = ToolExecutor(registry: toolRegistry, environment: toolEnvironment)

        self.toolRegistry = toolRegistry
        self.toolExecutor = toolExecutor
        self.toolEnvironment = toolEnvironment

        await rebuildToolState(environment: toolEnvironment)

        let service = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor,
            toolAuthorizationService: authService
        )

        self.chatService = service
        return service
    }

    /// Refresh tool toggles and authorized tool list, ensuring registry is loaded.
    func refreshToolToggles(modelContext: ModelContext) async {
        _ = await ensureChatService(modelContext: modelContext)
        await rebuildToolState(environment: toolEnvironment)
    }

    /// Adds an attachment to the staging area.
    func addAttachment(_ attachment: Attachment) {
        stagedAttachments.append(attachment)
    }

    /// Removes an attachment from the staging area.
    func removeAttachment(at index: Int) {
        guard index >= 0 && index < stagedAttachments.count else { return }
        stagedAttachments.remove(at: index)
    }

    /// Update permission state for a tool and refresh UI lists.
    func setToolPermission(toolID: String, enabled: Bool) async {
        guard let authService else { return }
        if enabled {
            await authService.grantAccess(for: toolID)
        } else {
            await authService.revokeAccess(for: toolID)
        }
        await rebuildToolState(environment: toolEnvironment)
    }

    /// Build UI tool toggle list and authorized tool definitions.
    private func rebuildToolState(environment: ToolEnvironment) async {
        guard let registry = toolRegistry else { return }
        let uiDefaults = UIToolDefinition.defaultTools(for: environment)
        let iconMap = Dictionary(
            uniqueKeysWithValues: uiDefaults.map { ($0.name.lowercased(), $0.icon) })
        let tools = await registry.allTools()

        var toggles: [UIToolToggleItem] = []

        for tool in tools {
            let availability = tool.availability(in: environment)
            let permission = await authService?.checkAccess(for: tool.name) ?? .notDetermined
            let icon = iconMap[tool.name.lowercased()] ?? "wrench.and.screwdriver"

            let toggle = UIToolToggleItem(
                id: tool.name,
                name: tool.name,
                icon: icon,
                description: tool.description,
                isEnabled: permission == .authorized,
                isAvailable: availability.isSupported,
                unavailableReason: availability.details
            )
            toggles.append(toggle)
        }

        toggles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        toolToggles = toggles
        availableTools =
            toggles
            .filter { $0.isEnabled }
            .map {
                UIToolDefinition(
                    id: UUID(),
                    name: $0.name,
                    icon: $0.icon,
                    description: $0.description
                )
            }
    }

    // MARK: - Session Management

    /// Updates the session's model selection and persists it immediately.
    func updateSessionModel(
        session: ChatSessionEntity,
        provider: UILLMProvider?,
        model: UILLMModel?,
        modelContext: ModelContext
    ) {
        // Reuse the mapping logic to get canonical IDs
        let (providerID, modelID) = mapUISelectionToProviderModel(
            selectedProvider: provider,
            selectedModel: model,
            sessionEntity: session
        )

        // Only update and save if changed
        if session.providerID != providerID || session.model != modelID {
            session.providerID = providerID
            session.model = modelID
            session.updatedAt = Date()

            do {
                try modelContext.save()
                logger.info("Persisted session model change: \(providerID) / \(modelID)")
            } catch {
                logger.error(
                    "Failed to persist session model update: \(error.localizedDescription)")
            }
        }
    }

    /// Hydrates the UI state from the session's persisted model selection.
    /// strictly trusting the DB state over defaults.
    func hydrateState(
        from session: ChatSessionEntity,
        workbenchVM: WorkbenchViewModel,
        modelRegistry: ModelRegistry
    ) {
        let savedProviderID = session.providerID
        let savedModelID = session.model

        guard !savedProviderID.isEmpty, !savedModelID.isEmpty else {
            logger.info("No saved model state in session, using defaults.")
            return
        }

        logger.info("Hydrating state from session: \(savedProviderID) / \(savedModelID)")

        // 1. Find Provider
        // We try to match the saved ID to the UI providers in the registry
        // Simple heuristic: check if provider name contains the ID or vice versa
        // A better way would be if UILLMProvider had an 'id' property that matches, but it seems to use 'name'
        // Let's try to match loosely

        let targetProvider = modelRegistry.availableProviders()
            .filter { providerName in
                // Normalize provider name
                let normalized = providerName.lowercased()
                    .replacingOccurrences(of: " ai", with: "")
                    .trimmingCharacters(in: CharacterSet.whitespaces)
                return normalized == savedProviderID || savedProviderID.contains(normalized)
            }
            .map { providerName -> UILLMProvider in
                let models = modelRegistry.models(for: providerName).map { model in
                    UILLMModel(
                        id: UUID(),
                        modelID: model.id,
                        name: model.displayName,
                        contextWindow: model.contextWindow
                    )
                }

                // Determine icon based on provider name
                let icon: String
                switch providerName.lowercased() {
                case "openai": icon = "sparkles"
                case "anthropic": icon = "brain.head.profile"
                case "google": icon = "cloud.fill"
                case "mistral": icon = "wind"
                case "xai": icon = "x.circle.fill"  // or appropriate icon
                default: icon = "server.rack"
                }

                return UILLMProvider(
                    id: UUID(),
                    name: providerName,
                    icon: icon,
                    models: models,
                    isActive: false
                )
            }
            .first

        if let provider = targetProvider {
            workbenchVM.selectedProvider = provider

            // 2. Find Model - match by modelID (stable identifier)
            if let model = provider.models.first(where: { $0.modelID == savedModelID }) {
                workbenchVM.selectedModel = model
                logger.info("Hydration successful: \(provider.name) -> \(model.name)")
            } else {
                // Log missing model only once to avoid spam
                let key = "\(savedProviderID):\(savedModelID)"
                if !Self.loggedMissingModels.contains(key) {
                    logger.warning(
                        "Model \(savedModelID) not found in \(provider.name), using default")
                    Self.loggedMissingModels.insert(key)
                }
                // Fallback to provider's first model
                if let defaultModel = provider.models.first {
                    workbenchVM.selectedModel = defaultModel
                }
            }
        } else {
            // Log missing provider only once
            let key = "provider:\(savedProviderID)"
            if !Self.loggedMissingModels.contains(key) {
                logger.warning("Could not find provider for ID: \(savedProviderID)")
                Self.loggedMissingModels.insert(key)
            }
        }
    }

    /// Sends a message in the given session.
    /// - Parameters:
    ///   - messageText: The text of the message to send.
    ///   - attachments: Optional attachments to include (defaults to stagedAttachments).
    ///   - session: The chat session to append the message to.
    ///   - modelContext: The SwiftData context for persistence.
    ///   - selectedProvider: The currently selected UI provider (optional, for model mapping).
    ///   - selectedModel: The currently selected UI model (optional, for model mapping).
    func sendMessage(
        messageText: String,
        attachments: [Attachment]? = nil,
        session: ChatSessionEntity,
        modelContext: ModelContext,
        selectedProvider: UILLMProvider? = nil,
        selectedModel: UILLMModel? = nil
    ) {
        let finalAttachments = attachments ?? stagedAttachments
        let finalReferences = stagedReferences
        guard !messageText.isEmpty || !finalAttachments.isEmpty || !finalReferences.isEmpty else { return }
        guard !isGenerating else {
            logger.warning("Already generating a response, ignoring send request")
            return
        }

        // Clear staged attachments if we are using them
        if attachments == nil {
            stagedAttachments.removeAll()
        }
        if !finalReferences.isEmpty {
            stagedReferences.removeAll()
        }

        var userMessageText = messageText
        var imageAttachments: [Data] = []
        var messageAttachments: [Attachment] = []

        // Process attachments
        for attachment in finalAttachments {
            messageAttachments.append(attachment)

            switch attachment.type {
            case .image:
                if let data = try? Data(contentsOf: attachment.url) {
                    imageAttachments.append(data)
                }
            case .text, .code:
                if let content = try? String(contentsOf: attachment.url, encoding: .utf8) {
                    userMessageText += "\n\n[Attached: \(attachment.filename)]\n\(content)"
                }
            default:
                break
            }
        }

        // References are injected into the next outgoing request only (not persisted into the user message).

        // Map UI model selection to real provider/model IDs
        let (providerID, modelID) = mapUISelectionToProviderModel(
            selectedProvider: selectedProvider,
            selectedModel: selectedModel,
            sessionEntity: session
        )

        // Update session entity synchronously on MainActor
        session.providerID = providerID
        session.model = modelID
        let sessionID = session.id

        // Persist the user message via SwiftData to avoid optimistic-append duplicates.
        do {
            let userDomainMessage = ChatMessage(
                id: UUID(),
                role: .user,
                content: userMessageText,
                thoughtProcess: nil,
                parts: [.text(userMessageText)],
                attachments: messageAttachments,
                createdAt: Date(),
                codeBlocks: [],
                tokenUsage: nil,
                costBreakdown: nil
            )
            let userEntity = ChatMessageEntity(message: userDomainMessage)
            userEntity.session = session
            session.updatedAt = Date()
            modelContext.insert(userEntity)
            try modelContext.save()
        } catch {
            logger.error("Failed to persist user message: \(error.localizedDescription)")
            return
        }

        isGenerating = true
        let streamToken = UUID().uuidString
        let streamingID = UUID()
        let streamingStart = Date()
        let domainSession = session.asDomain()

        // Call the real LLM API
        Task { @MainActor in
            // Setup throttled UI update stream
            let (uiStream, uiContinuation) = AsyncStream<String>.makeStream()

            // Task to handle UI updates at a throttled rate
            let updateTask = Task { @MainActor in
                // Throttle updates to max 1 per 300ms
                for await text in uiStream.throttled(for: .milliseconds(300)) {
                    self.streamingText = text
                    self.setLastVisibleMessage(to: streamingID)
                }
            }

            do {
                await streamAccumulator.reset()
                await streamAccumulator.begin(token: streamToken)

                streamingMessageID = streamingID
                streamingStartedAt = streamingStart
                streamingText = nil

                // Get or create chat service
                let service = await ensureChatService(modelContext: modelContext)

                logger.info("Sending message to provider: \(providerID), model: \(modelID)")

                // Stream completion using the PREPARED domain session
                let stream = try await service.streamCompletion(
                    for: domainSession,
                    userMessage: userMessageText,  // Includes attached text content
                    attachments: messageAttachments,
                    references: finalReferences,
                    images: imageAttachments
                )

                // ... Rest of loop logic is same ...

                // We can't safely access session.messages.last?.id here since 'session' is not captured.
                // We'll skip this optimization or fetch.
                // setLastVisibleMessage(to: session.messages.last?.id)

                // Track streaming state
                for try await event in stream {
                    switch event {
                    case .token(let text):
                        if let updated = await streamAccumulator.append(
                            token: streamToken,
                            delta: text
                        ) {
                            uiContinuation.yield(updated)
                        }

                    case .completion(let message):
                        _ = await streamAccumulator.complete(
                            token: streamToken,
                            final: message.content
                        )

                        // Finish UI stream and wait for it to process pending updates
                        uiContinuation.finish()
                        _ = await updateTask.result

                        streamingText = nil
                        streamingMessageID = nil
                        streamingStartedAt = nil
                        isTruncated = false
                        truncatedSessionID = nil
                        logger.info(
                            "Completion received, final length: \(message.content.count)")
                        setLastVisibleMessage(to: message.id)

                        // Update session safely via helper
                        self.handleStreamCompletion(
                            sessionID: sessionID, modelID: modelID, modelContext: modelContext)

                    case .truncated(let message):
                        _ = await streamAccumulator.complete(
                            token: streamToken,
                            final: message.content
                        )

                        // Finish UI stream and wait for it to process pending updates
                        uiContinuation.finish()
                        _ = await updateTask.result

                        streamingText = nil
                        streamingMessageID = nil
                        streamingStartedAt = nil
                        isTruncated = true
                        truncatedSessionID = sessionID
                        logger.warning(
                            "Response TRUNCATED at \(message.content.count) characters - max_tokens limit reached"
                        )
                        setLastVisibleMessage(to: message.id)

                        // Update session
                        self.handleStreamCompletion(
                            sessionID: sessionID, modelID: modelID, modelContext: modelContext)

                    case .error(let error):
                        await streamAccumulator.fail(token: streamToken, error: error)
                        uiContinuation.finish()
                        _ = await updateTask.result

                        streamingText = nil
                        streamingMessageID = nil
                        streamingStartedAt = nil
                        isTruncated = false
                        truncatedSessionID = nil
                        logger.error("LLM Error: \(error.localizedDescription)")

                        self.handleStreamError(
                            sessionID: sessionID, error: error, modelContext: modelContext)

                    case .usage(let usage):
                        logger.info(
                            "Token usage - Input: \(usage.inputTokens), Output: \(usage.outputTokens)"
                        )

                    case .thinking(let thought):
                        logger.debug("Thinking: \(thought)")

                    case .toolUse(let id, let name, _):
                        logger.info("Tool use: \(name) (id: \(id))")

                    case .toolExecuting(let name):
                        logger.info("Tool executing: \(name)")

                    case .reference(let ref):
                        logger.debug("Reference: \(ref)")

                    case .contextCompacted(let droppedMessages, let tokensSaved):
                        logger.info(
                            "⚡️ Context compacted: \(droppedMessages) messages dropped, \(tokensSaved) tokens saved"
                        )
                        self.contextCompactionMessage =
                            "⚡️ Context optimized: \(droppedMessages) message\(droppedMessages == 1 ? "" : "s") compacted, \(tokensSaved) tokens saved"
                        self.showContextCompactionNotification = true

                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            self.showContextCompactionNotification = false
                        }
                    }
                }

                await streamAccumulator.reset()

                isGenerating = false
                resetStreamingState()
                logger.info("Message generation completed")

            } catch {
                uiContinuation.finish()
                _ = await updateTask.result

                await streamAccumulator.fail(token: streamToken, error: error)
                await streamAccumulator.reset()

                isGenerating = false
                resetStreamingState()
                logger.error("Failed to send message: \(error)")

                // Show error in chat
                self.handleStreamError(
                    sessionID: sessionID, error: error, modelContext: modelContext)
            }
        }
    }

    /// Maps UI model selection to actual provider/model IDs.
    /// This is a temporary bridge between UI models and domain models.
    private func mapUISelectionToProviderModel(
        selectedProvider: UILLMProvider?,
        selectedModel: UILLMModel?,
        sessionEntity: ChatSessionEntity
    ) -> (providerID: String, modelID: String) {

        // If we have UI selections, try to map them
        if let provider = selectedProvider, let model = selectedModel {
            logger.info("UI Selection - Provider: \(provider.name), Model: \(model.name)")

            // Map provider names to IDs
            // Normalize provider name: lowercase and remove " AI" suffix
            let normalizedName = provider.name.lowercased()
                .replacingOccurrences(of: " ai", with: "")
                .trimmingCharacters(in: .whitespaces)

            let providerID: String
            switch normalizedName {
            case "openai", "open ai":
                providerID = "openai"
            case "anthropic":
                providerID = "anthropic"
            case "google", "gemini":
                providerID = "google"
            case "mistral":
                providerID = "mistral"
            case "xai", "x ai", "grok":
                providerID = "xai"
            case "openrouter", "open router":
                providerID = "openrouter"
            default:
                // Fallback: use normalized name
                providerID = normalizedName
            }

            logger.debug("Normalized '\(provider.name)' -> '\(providerID)'")

            // ✅ Use actual model ID instead of display name mapping
            let modelID = model.modelID

            logger.info("Mapped to - Provider ID: \(providerID), Model ID: \(modelID)")
            return (providerID, modelID)
        }

        // Fallback: use session's existing provider/model or default to OpenAI GPT-4o
        let providerID = sessionEntity.providerID.isEmpty ? "openai" : sessionEntity.providerID
        let modelID = sessionEntity.model.isEmpty ? "gpt-4o" : sessionEntity.model

        logger.info("Using session defaults - Provider: \(providerID), Model: \(modelID)")
        return (providerID, modelID)
    }

    /// Triggers a tool execution from the UI.
    /// - Parameters:
    ///   - tool: The tool definition to execute.
    ///   - workbenchVM: The workbench view model to handle the execution display.
    func triggerTool(_ tool: UIToolDefinition, workbenchVM: WorkbenchViewModel) {
        let executionID = UUID().uuidString
        let execution = ToolExecution(
            id: executionID,
            toolID: tool.id.uuidString,
            name: tool.name,
            icon: tool.icon,
            status: .running,
            output: "Executing \(tool.name)...",
            timestamp: Date()
        )

        workbenchVM.activeToolExecution = execution
        workbenchVM.toolInspectorVisible = true

        // Simulate completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            workbenchVM.activeToolExecution = ToolExecution(
                id: executionID,
                toolID: tool.id.uuidString,
                name: tool.name,
                icon: tool.icon,
                status: .completed,
                output: "Successfully executed \(tool.name)\n\nResult: Sample output data...",
                timestamp: execution.timestamp
            )
        }
    }

    /// Generates a conversation title based on the first user message.
    /// Format: "[emoji] [short topic] • [model name]"
    /// - Parameters:
    ///   - session: The chat session to update
    ///   - modelName: The model name to include in the title
    private func generateConversationTitle(for session: ChatSessionEntity, modelName: String) {
        // Check if title needs generation
        let defaultTitles = ["Untitled", "New Conversation", ""]
        guard defaultTitles.contains(session.title) || session.title.isEmpty else {
            return
        }

        // Find first user message
        guard let firstUserMessage = session.messages.first(where: { $0.role == "user" }) else {
            return
        }

        // Extract first ~40 chars and truncate at word boundary
        let content = firstUserMessage.content
        let maxLength = 40
        var truncated = String(content.prefix(maxLength))

        if content.count > maxLength {
            // Find last space to truncate at word boundary
            if let lastSpace = truncated.lastIndex(of: " ") {
                truncated = String(truncated[..<lastSpace])
            }
            truncated += "…"
        }

        // Pick emoji based on keywords
        let emoji = selectEmoji(for: content.lowercased())

        // Format model name (e.g., "gpt-4o" -> "GPT-4o")
        let formattedModel = formatModelName(modelName)

        // Generate title
        session.title = "\(emoji) \(truncated) • \(formattedModel)"

        logger.info("Generated conversation title: \(session.title)")
    }

    /// Selects an appropriate emoji based on message content.
    private func selectEmoji(for content: String) -> String {
        if content.contains("code") || content.contains("swift") || content.contains("python")
            || content.contains("programming") || content.contains("javascript")
            || content.contains("typescript")
        {
            return "💻"
        } else if content.contains("math") || content.contains("calculate")
            || content.contains("number") || content.contains("equation")
        {
            return "🧮"
        } else if content.contains("help") || content.contains("how") || content.contains("what")
            || content.contains("why")
        {
            return "❓"
        } else if content.contains("write") || content.contains("essay") || content.contains("blog")
            || content.contains("article")
        {
            return "✍️"
        } else if content.contains("search") || content.contains("find") || content.contains("look")
        {
            return "🔍"
        } else if content.contains("image") || content.contains("photo")
            || content.contains("picture")
        {
            return "🖼️"
        } else if content.contains("data") || content.contains("analyze")
            || content.contains("analysis")
        {
            return "📊"
        } else if content.contains("bug") || content.contains("error") || content.contains("fix")
            || content.contains("debug")
        {
            return "🔧"
        } else {
            return "💬"
        }
    }

    /// Formats a model ID into a display name.
    private func formatModelName(_ modelID: String) -> String {
        // Handle common patterns
        if modelID.hasPrefix("claude-") {
            let parts = modelID.components(separatedBy: "-")
            if parts.count >= 2 {
                return "Claude \(parts[1].capitalized)"
            }
        } else if modelID.hasPrefix("gpt-") {
            return modelID.replacingOccurrences(of: "gpt-", with: "GPT-")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        } else if modelID.hasPrefix("gemini-") {
            return modelID.replacingOccurrences(of: "gemini-", with: "Gemini ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        } else if modelID.hasPrefix("grok-") {
            return modelID.replacingOccurrences(of: "grok-", with: "Grok ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }

        // Default: capitalize first letter
        return modelID.prefix(1).uppercased() + modelID.dropFirst()
    }

    /// Records the latest message the UI should keep visible.
    private func setLastVisibleMessage(to id: UUID?) {
        guard lastVisibleMessageID != id else { return }
        lastVisibleMessageID = id
    }

    /// Clear streaming state for the current session.
    private func resetStreamingState() {
        streamingText = nil
        streamingMessageID = nil
        streamingStartedAt = nil
    }

    // MARK: - Safe Update Helpers

    private func handleStreamCompletion(
        sessionID: UUID, modelID: String, modelContext: ModelContext
    ) {
        do {
            let descriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate { $0.id == sessionID })
            if let session = try modelContext.fetch(descriptor).first {
                let count = session.messages.count
                logger.info("Session message count: \(count)")

                if count <= 2 {
                    self.generateConversationTitle(for: session, modelName: modelID)
                }
            }
        } catch {
            logger.error(
                "Failed to fetch session for completion update: \(error.localizedDescription)")
        }
    }

    private func handleStreamError(sessionID: UUID, error: Error, modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate { $0.id == sessionID })
            if let session = try modelContext.fetch(descriptor).first {
                let errorMessage = ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "❌ Error: \(error.localizedDescription)",
                    parts: [],
                    createdAt: Date(),
                    codeBlocks: []
                )
                let errorEntity = ChatMessageEntity(message: errorMessage)
                errorEntity.session = session
                session.updatedAt = Date()
                modelContext.insert(errorEntity)
                try modelContext.save()
                setLastVisibleMessage(to: errorEntity.id)
            }
        } catch {
            logger.error("Failed to fetch session for error update: \(error.localizedDescription)")
        }
    }

    /// Continues generation for a truncated session.
    func continueGenerating(session: ChatSessionEntity, modelContext: ModelContext) {
        guard let sessionID = truncatedSessionID,
            isTruncated,
            sessionID == session.id,
            !isGenerating
        else { return }

        // Send a "Continue" user message to prompt the model to resume
        sendMessage(
            messageText: "Continue",
            session: session,
            modelContext: modelContext
        )
    }
}
