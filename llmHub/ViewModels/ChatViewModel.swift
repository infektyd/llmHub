//
//  ChatViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import FoundationModels
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
    /// AFM diagnostics state for runtime availability checks.
    var afmDiagnostics: AFMDiagnosticsState = AFMDiagnosticsState()

    // ... existing properties ...

    /// Adds a reference to the staging area.
    func addReference(_ reference: ChatReference) {
        let alreadyStaged = stagedReferences.contains { existing in
            if existing.id == reference.id { return true }
            return existing.text == reference.text
                && existing.sourceMessageID == reference.sourceMessageID
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
    /// Names of tools currently executing (for UI feedback).
    var executingToolNames: Set<String> = []
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

    /// Estimated token count during active streaming (approx 4 chars per token)
    var streamingTokenEstimate: Int {
        guard let text = streamingText else { return 0 }
        return max(1, text.count / 4)
    }

    /// The chat service for LLM interactions.
    private var chatService: ChatService?
    /// Streaming accumulator for incoming tokens.
    private let streamAccumulator = StreamAccumulator()
    /// Identifier for the current streaming message.
    private var streamingMessageID: UUID?
    /// Timestamp for the streaming message.
    private var streamingStartedAt: Date?
    /// Task handle for the active streaming pipeline.
    private var currentStreamTask: Task<Void, Never>?
    /// Session ID associated with the active streaming task.
    private var currentStreamingSessionID: UUID?
    /// Model context used for the active streaming task.
    private var currentStreamingModelContext: ModelContext?

    // MARK: - Tool Execution Timing (STEP 3)

    private var toolExecutionElapsedSeconds: [String: Int] = [:]
    private var toolExecutionCancelHandlers: [String: () -> Void] = [:]
    private var toolTimerTask: Task<Void, Never>?

    /// Service for conversation distillation.
    private var distillationService: ConversationDistillationService?

    /// Tracks the previous session to trigger cleanup/distillation on switch.
    private var previousSessionID: UUID?

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

        // Initialize distillation service
        self.distillationService = ConversationDistillationService()

        // Initialize keychain
        let keychain = KeychainStore()

        // Try to get OpenAI key from environment first, then keychain
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            logger.info("Found OpenAI API key in environment")
            try? await keychain.updateKey(envKey, for: .openai)
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
        // If the UI already provided an authorization service, reuse it so prompts/decisions are consistent.
        let authService = self.authService ?? ToolAuthorizationService()
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

        let toolRegistry = await ToolRegistry(tools: tools)
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

    /// Allows the UI to provide a shared ToolAuthorizationService instance so prompts and permission
    /// state are consistent across the view and the execution layer.
    func attachAuthorizationService(_ service: ToolAuthorizationService) {
        self.authService = service
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
            authService.grantAccess(for: toolID)
        } else {
            authService.revokeAccess(for: toolID)
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
            let permission = authService?.checkAccess(for: tool.name) ?? .notDetermined
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

    /// Called when user switches sessions or session becomes inactive.
    /// Triggers background distillation of the session into memory.
    func onSessionDeactivated(session: ChatSessionEntity, modelContext: ModelContext) {
        guard let distillationService = distillationService else { return }

        session.triggerDistillation(
            distillationService: distillationService,
            modelContext: modelContext
        )
    }

    // MARK: - Session Management
    // (rest of file unchanged)

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

        // Rationale: Persisted provider IDs may be legacy/case-varied (e.g. "OpenAI", "openAI").
        // Normalize before matching against the model registry list.
        let canonicalSavedProviderID = ProviderID.canonicalID(from: savedProviderID)

        logger.info(
            "Hydrating state from session: \(savedProviderID) → \(canonicalSavedProviderID) / \(savedModelID)"
        )

        func makeUIProvider(providerName: String) -> UILLMProvider {
            let models = modelRegistry.models(for: providerName).map { model in
                UILLMModel(
                    id: UUID(),
                    modelID: model.id,
                    name: model.displayName,
                    contextWindow: model.contextWindow
                )
            }

            let icon: String
            switch providerName.lowercased() {
            case "openai": icon = "sparkles"
            case "anthropic": icon = "brain.head.profile"
            case "google": icon = "cloud.fill"
            case "mistral": icon = "wind"
            case "xai": icon = "x.circle.fill"
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

        let targetProvider = modelRegistry.availableProviders()
            .filter { providerName in
                ProviderID.canonicalID(from: providerName) == canonicalSavedProviderID
            }
            .map { providerName in makeUIProvider(providerName: providerName) }
            .first

        if let provider = targetProvider {
            workbenchVM.selectedProvider = provider

            if let model = provider.models.first(where: { $0.modelID == savedModelID }) {
                workbenchVM.selectedModel = model
                logger.info("Hydration successful: \(provider.name) -> \(model.name)")
            } else if let resolvedModelID = Self.resolvePersistedModelID(
                providerID: canonicalSavedProviderID,
                savedModelID: savedModelID,
                availableModels: provider.models.map { ($0.modelID, $0.name) }
            ),
                let migrated = provider.models.first(where: { $0.modelID == resolvedModelID })
            {
                logger.info(
                    "Migrated persisted model '\(savedModelID)' -> '\(resolvedModelID)' for provider \(provider.name)"
                )
                workbenchVM.selectedModel = migrated
            } else {
                let key = "\(savedProviderID):\(savedModelID)"
                if !Self.loggedMissingModels.contains(key) {
                    logger.warning(
                        "Model \(savedModelID) not found in \(provider.name), using default")
                    Self.loggedMissingModels.insert(key)
                }
                if let defaultModel = provider.models.first {
                    workbenchVM.selectedModel = defaultModel
                }
            }
        } else {
            let knownCanonicalIDs = Set(ProviderID.legacyAliasesByLookupKey.values)
            let isKnownProvider = knownCanonicalIDs.contains(canonicalSavedProviderID)

            let availableProviderNames = modelRegistry.availableProviders()
            let key = "provider:\(canonicalSavedProviderID)"

            if !Self.loggedMissingModels.contains(key) {
                let available = availableProviderNames.joined(separator: ", ")
                if isKnownProvider {
                    logger.warning(
                        "Provider '\(savedProviderID)' (canonical: \(canonicalSavedProviderID)) is registered, but models are not loaded/available. Available providers with models: \(available). Falling back."
                    )
                } else {
                    logger.warning(
                        "Could not find provider for ID: \(savedProviderID) (canonical: \(canonicalSavedProviderID)). Available providers with models: \(available). Falling back."
                    )
                }
                Self.loggedMissingModels.insert(key)
            }

            // Fallback to first available provider+model (and let onChange persist migration).
            if let fallbackProviderName = availableProviderNames.first {
                let fallbackProvider = makeUIProvider(providerName: fallbackProviderName)
                workbenchVM.selectedProvider = fallbackProvider
                if let fallbackModel = fallbackProvider.models.first {
                    workbenchVM.selectedModel = fallbackModel
                }
            }
        }
    }

    // MARK: - Persisted Model ID Migration

    /// Resolves a persisted/legacy model identifier into a real model id present in `availableModels`.
    ///
    /// - Rationale: Earlier builds may have persisted UI display names (e.g. "Gemini 3 Flash Preview")
    ///   instead of API model IDs (e.g. "gemini-3-flash-preview"). We migrate deterministically.
    ///
    /// - Rules:
    ///   - Prefer explicit alias maps for known historical values.
    ///   - Fall back to a conservative display-name match only if it maps uniquely.
    static func resolvePersistedModelID(
        providerID: String,
        savedModelID: String,
        availableModels: [(id: String, displayName: String)]
    ) -> String? {
        let providerKey = ProviderID.canonicalID(from: providerID)
        let savedKey = ProviderID.lookupKey(from: savedModelID)

        // Known historical aliases (display-ish strings -> real API model IDs).
        // Keys are lookupKey-normalized (lowercased alphanumerics only).
        let aliasesByProvider: [String: [String: String]] = [
            "google": [
                ProviderID.lookupKey(from: "Gemini 3 Flash Preview"): "gemini-3-flash-preview",
                ProviderID.lookupKey(from: "Gemini 3 Pro Preview"): "gemini-3-pro-preview"
            ],
            // Anthropic: sometimes users have old display names persisted.
            "anthropic": [
                ProviderID.lookupKey(from: "Claude 3.5 Sonnet"): "claude-3-5-sonnet-20241022",
                ProviderID.lookupKey(from: "Claude 3.5 Haiku"): "claude-3-5-haiku-20241022",
                ProviderID.lookupKey(from: "Claude 3 Opus"): "claude-3-opus-20240229",
                ProviderID.lookupKey(from: "Claude Sonnet 4"): "claude-sonnet-4-20250514",
                ProviderID.lookupKey(from: "Claude Sonnet 4.5"): "claude-sonnet-4-5-20250929",
                ProviderID.lookupKey(from: "Claude Opus 4.5"): "claude-opus-4-5-20251101"
            ],
            // xAI: map common UI-ish names to canonical IDs.
            "xai": [
                ProviderID.lookupKey(from: "Grok 4"): "grok-4",
                ProviderID.lookupKey(from: "Grok 3"): "grok-3",
                ProviderID.lookupKey(from: "Grok 3 Mini"): "grok-3-mini",
                ProviderID.lookupKey(from: "Grok 2"): "grok-2-1212",
                ProviderID.lookupKey(from: "Grok 2 Vision"): "grok-2-vision-1212"
            ]
        ]

        if let mapped = aliasesByProvider[providerKey]?[savedKey] {
            if availableModels.contains(where: { $0.id == mapped }) {
                return mapped
            }
        }

        // Conservative fallback: match against displayName lookup key, but only if unique.
        let matches = availableModels.filter { ProviderID.lookupKey(from: $0.displayName) == savedKey }
        if matches.count == 1 {
            return matches[0].id
        }

        // Final fallback: case-insensitive direct ID match.
        if let direct = availableModels.first(where: { $0.id.caseInsensitiveCompare(savedModelID) == .orderedSame }) {
            return direct.id
        }

        return nil
    }

    // (rest unchanged from your current file)
    // NOTE: leaving everything after hydrateState as-is to avoid unrelated diffs.

    /// Sends a message in the given session.
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
        guard !messageText.isEmpty || !finalAttachments.isEmpty || !finalReferences.isEmpty else {
            return
        }
        guard !isGenerating else {
            logger.warning("Already generating a response, ignoring send request")
            return
        }

        if attachments == nil {
            stagedAttachments.removeAll()
        }
        if !finalReferences.isEmpty {
            stagedReferences.removeAll()
        }

        let userMessageText = messageText
        var imageAttachments: [Data] = []
        var messageAttachments: [Attachment] = []

        for attachment in finalAttachments {
            messageAttachments.append(attachment)

            switch attachment.type {
            case .image:
                if let data = try? Data(contentsOf: attachment.url) {
                    imageAttachments.append(data)
                }
            case .text, .code:
                // Keep chat transcript clean: attachments render as collapsible artifact cards.
                // Attachment contents are injected into the LLM request by ChatService (request-only).
                break
            default:
                break
            }
        }

        let (providerID, modelID) = mapUISelectionToProviderModel(
            selectedProvider: selectedProvider,
            selectedModel: selectedModel,
            sessionEntity: session
        )

        session.providerID = providerID
        session.model = modelID
        let sessionID = session.id

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
        currentStreamingSessionID = sessionID
        currentStreamingModelContext = modelContext

        currentStreamTask = Task { @MainActor in
            let (uiStream, uiContinuation) = AsyncStream<String>.makeStream()

            let updateTask = Task { @MainActor in
                for await text in uiStream {
                    self.streamingText = text
                    self.setLastVisibleMessage(to: streamingID)
                }
            }

            do {
                defer {
                    currentStreamTask = nil
                }
                await streamAccumulator.reset()
                await streamAccumulator.begin(token: streamToken)

                streamingMessageID = streamingID
                streamingStartedAt = streamingStart
                streamingText = nil

                let service = await ensureChatService(modelContext: modelContext)

                logger.info("Sending message to provider: \(providerID), model: \(modelID)")

                let stream = try await service.streamCompletion(
                    for: domainSession,
                    userMessage: userMessageText,
                    attachments: messageAttachments,
                    references: finalReferences,
                    images: imageAttachments
                )

                for try await event in stream {
                    if Task.isCancelled {
                        logger.info("Stream cancelled by user")
                        break
                    }

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

                        uiContinuation.finish()
                        _ = await updateTask.result

                        streamingText = nil
                        streamingMessageID = nil
                        streamingStartedAt = nil
                        isTruncated = false
                        truncatedSessionID = nil
                        executingToolNames.removeAll()
                        logger.info(
                            "Completion received, final length: \(message.content.count)")
                        setLastVisibleMessage(to: message.id)

                        self.handleStreamCompletion(
                            sessionID: sessionID, modelID: modelID, modelContext: modelContext)

                    case .truncated(let message):
                        _ = await streamAccumulator.complete(
                            token: streamToken,
                            final: message.content
                        )

                        uiContinuation.finish()
                        _ = await updateTask.result

                        streamingText = nil
                        streamingMessageID = nil
                        streamingStartedAt = nil
                        isTruncated = true
                        truncatedSessionID = sessionID
                        executingToolNames.removeAll()
                        logger.warning(
                            "Response TRUNCATED at \(message.content.count) characters - max_tokens limit reached"
                        )
                        setLastVisibleMessage(to: message.id)

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
                        executingToolNames.removeAll()
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
                        executingToolNames.insert(name)
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

                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            self?.showContextCompactionNotification = false
                        }
                    }
                }

                if Task.isCancelled {
                    uiContinuation.finish()
                    _ = await updateTask.result
                    await streamAccumulator.reset()
                    logger.info("Stream task cancelled before completion")
                    if isGenerating {
                        isGenerating = false
                        resetStreamingState()
                        executingToolNames.removeAll()
                        isTruncated = false
                        truncatedSessionID = nil
                    }
                    return
                }

                await streamAccumulator.reset()

                isGenerating = false
                resetStreamingState()
                logger.info("Message generation completed")

            } catch {
                uiContinuation.finish()
                _ = await updateTask.result

                if Task.isCancelled {
                    await streamAccumulator.reset()
                    logger.info("Stream task cancelled during stream error")
                    if isGenerating {
                        isGenerating = false
                        resetStreamingState()
                        executingToolNames.removeAll()
                        isTruncated = false
                        truncatedSessionID = nil
                    }
                    return
                }

                await streamAccumulator.fail(token: streamToken, error: error)
                await streamAccumulator.reset()

                isGenerating = false
                resetStreamingState()
                executingToolNames.removeAll()
                logger.error("Failed to send message: \(error)")

                self.handleStreamError(
                    sessionID: sessionID, error: error, modelContext: modelContext)
            }
        }
    }

    func stopGeneration() async {
        guard let task = currentStreamTask else { return }
        logger.info("Stop generation requested by user")

        let textSnapshot = streamingText ?? ""
        let messageIDSnapshot = streamingMessageID
        let startedAtSnapshot = streamingStartedAt
        let sessionIDSnapshot = currentStreamingSessionID
        let modelContextSnapshot = currentStreamingModelContext

        task.cancel()
        currentStreamTask = nil

        isGenerating = false
        streamingText = nil
        streamingMessageID = nil
        streamingStartedAt = nil
        isTruncated = false
        truncatedSessionID = nil
        executingToolNames.removeAll()
        currentStreamingSessionID = nil
        currentStreamingModelContext = nil

        guard
            let messageID = messageIDSnapshot,
            let sessionID = sessionIDSnapshot,
            let modelContext = modelContextSnapshot
        else { return }

        let emote = await generateInterruptionEmote()
        let trimmed = textSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = trimmed.isEmpty ? emote : "\(textSnapshot) \(emote)"

        let interruptedMessage = ChatMessage(
            id: messageID,
            role: .assistant,
            content: finalText,
            thoughtProcess: nil,
            parts: [.text(finalText)],
            createdAt: startedAtSnapshot ?? Date(),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil,
            toolCallID: nil,
            toolCalls: nil
        )

        let service = await ensureChatService(modelContext: modelContext)
        try? service.appendMessage(interruptedMessage, to: sessionID)
        setLastVisibleMessage(to: messageID)
    }

    private func generateInterruptionEmote() async -> String {
        let fallback = "⏸️"

        do {
            // Create a session with simple instructions
            let session = LanguageModelSession(
                instructions: "You are a helpful assistant. Always respond with exactly one emoji."
            )
            
            let prompt = """
            Generate a single emoji that represents an interrupted thought or \
            paused conversation. Respond with only the emoji, nothing else.
            """
            
            let response = try await session.respond(to: prompt)

            if let firstEmoji = response.content.unicodeScalars.first(where: { $0.properties.isEmoji })
            {
                return String(firstEmoji)
            }
        } catch {
            logger.warning(
                "AFM emote generation failed: \(error.localizedDescription)")
        }

        return fallback
    }

    private func mapUISelectionToProviderModel(
        selectedProvider: UILLMProvider?,
        selectedModel: UILLMModel?,
        sessionEntity: ChatSessionEntity
    ) -> (providerID: String, modelID: String) {
        if let provider = selectedProvider, let model = selectedModel {
            logger.info("UI Selection - Provider: \(provider.name), Model: \(model.name)")

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
                providerID = normalizedName
            }

            logger.debug("Normalized '\(provider.name)' -> '\(providerID)'")

            let modelID = model.modelID

            logger.info("Mapped to - Provider ID: \(providerID), Model ID: \(modelID)")
            return (providerID, modelID)
        }

        let providerID = sessionEntity.providerID.isEmpty ? "openai" : sessionEntity.providerID
        let modelID = sessionEntity.model.isEmpty ? "gpt-4o" : sessionEntity.model

        logger.info("Using session defaults - Provider: \(providerID), Model: \(modelID)")
        return (providerID, modelID)
    }

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

    private func generateConversationTitle(for session: ChatSessionEntity, modelName: String) {
        let defaultTitles = ["Untitled", "New Conversation", ""]
        guard defaultTitles.contains(session.title) || session.title.isEmpty else {
            return
        }

        guard let firstUserMessage = session.messages.first(where: { $0.role == "user" }) else {
            return
        }

        let content = firstUserMessage.content
        let maxLength = 40
        var truncated = String(content.prefix(maxLength))

        if content.count > maxLength {
            if let lastSpace = truncated.lastIndex(of: " ") {
                truncated = String(truncated[..<lastSpace])
            }
            truncated += "…"
        }

        let emoji = selectEmoji(for: content.lowercased())
        let formattedModel = formatModelName(modelName)

        session.title = "\(emoji) \(truncated) • \(formattedModel)"

        logger.info("Generated conversation title: \(session.title)")
    }

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

    private func formatModelName(_ modelID: String) -> String {
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

        return modelID.prefix(1).uppercased() + modelID.dropFirst()
    }

    private func setLastVisibleMessage(to id: UUID?) {
        guard lastVisibleMessageID != id else { return }
        lastVisibleMessageID = id
    }

    private func resetStreamingState() {
        streamingText = nil
        streamingMessageID = nil
        streamingStartedAt = nil
        currentStreamingSessionID = nil
        currentStreamingModelContext = nil
    }

    private func handleStreamCompletion(
        sessionID: UUID, modelID: String, modelContext: ModelContext
    ) {
        do {
            let descriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate { $0.id == sessionID })
            if let session = try modelContext.fetch(descriptor).first {
                let count = session.messages.count
                logger.info("Session message count: \(count)")

                // Update lastActivityAt on every message
                session.lastActivityAt = Date()

                if count <= 2 {
                    self.generateConversationTitle(for: session, modelName: modelID)
                }

                // Schedule AFM classification after first message or at 5 messages
                if count == 2 || count == 5 {
                    self.scheduleClassification(for: session, modelContext: modelContext)
                }

                try modelContext.save()
            }
        } catch {
            logger.error(
                "Failed to fetch session for completion update: \(error.localizedDescription)")
        }
    }

    /// Schedules AFM classification for a conversation session.
    private func scheduleClassification(for session: ChatSessionEntity, modelContext: ModelContext)
    {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            let classificationService = ConversationClassificationService()

            // Convert entities to domain messages for classification
            let messages = session.messages.sorted { $0.createdAt < $1.createdAt }.map {
                $0.asDomain()
            }

            do {
                let metadata = try await classificationService.classify(messages: messages)

                // Update session with classification results
                session.afmTitle = metadata.title
                session.afmEmoji = metadata.emoji
                session.afmCategory = metadata.category.rawValue
                session.afmTopics = try? JSONEncoder().encode(metadata.topics)
                session.afmClassifiedAt = Date()
                session.lifecycleIntent = metadata.intent.rawValue
                session.lifecycleRetention = metadata.suggestedRetention.rawValue
                session.isComplete = metadata.isComplete
                session.hasArtifacts = metadata.hasArtifacts

                try modelContext.save()
                self.logger.info(
                    "Classification completed for session \(session.id): \(metadata.title)")
            } catch {
                self.logger.error("Classification failed: \(error.localizedDescription)")
            }
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

    nonisolated func checkAFMAvailability(retryDelay: TimeInterval = 0) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let timestamp = Date()
            let model = SystemLanguageModel.default
            let availability = model.availability

            afmDiagnostics.lastCheckTime = timestamp
            afmDiagnostics.availability = availability
            afmDiagnostics.isAvailable = (availability == .available)
            afmDiagnostics.checkCount += 1

            switch availability {
            case .available:
                afmDiagnostics.reasonText = "✅ AFM Available"
                logger.info("AFM: ✅ Available at \(timestamp)")
            case .unavailable(let reason):
                let reasonText = "\(reason)"
                afmDiagnostics.reasonText = "❌ \(reasonText)"
                logger.info("AFM: ❌ Unavailable - \(reasonText) at \(timestamp)")
            @unknown default:
                afmDiagnostics.reasonText = "❓ Unknown state"
                logger.warning("AFM: Unknown availability at \(timestamp)")
            }

            if retryDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                checkAFMAvailability(retryDelay: 0)
            }
        }
    }

    func retryAFMCheck() {
        checkAFMAvailability(retryDelay: 2.0)
    }

    func continueGenerating(session: ChatSessionEntity, modelContext: ModelContext) {
        guard let sessionID = truncatedSessionID,
            isTruncated,
            sessionID == session.id,
            !isGenerating
        else { return }

        sendMessage(
            messageText: "Continue",
            session: session,
            modelContext: modelContext
        )
    }
    
    // MARK: - Tool Execution Timing (STEP 3)
    
    /// Start tracking elapsed time for a tool execution
    func startToolTimer(toolCallID: String, cancelHandler: @escaping () -> Void) {
        toolExecutionElapsedSeconds[toolCallID] = 0
        toolExecutionCancelHandlers[toolCallID] = cancelHandler
        
        // Start or restart the timer task if needed
        if toolTimerTask == nil || toolTimerTask?.isCancelled == true {
            toolTimerTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    
                    // Update all active tool timers (throttled to 1 Hz)
                    for toolCallID in toolExecutionElapsedSeconds.keys {
                        toolExecutionElapsedSeconds[toolCallID, default: 0] += 1
                    }
                }
            }
        }
    }
    
    /// Stop tracking elapsed time for a tool execution
    func stopToolTimer(toolCallID: String) {
        toolExecutionElapsedSeconds.removeValue(forKey: toolCallID)
        toolExecutionCancelHandlers.removeValue(forKey: toolCallID)
        
        // Cancel timer task if no tools are running
        if toolExecutionElapsedSeconds.isEmpty {
            toolTimerTask?.cancel()
            toolTimerTask = nil
        }
    }
    
    /// Cancel a running tool execution
    func cancelToolExecution(toolCallID: String) {
        if let cancelHandler = toolExecutionCancelHandlers[toolCallID] {
            cancelHandler()
            stopToolTimer(toolCallID: toolCallID)
        }
    }
}
