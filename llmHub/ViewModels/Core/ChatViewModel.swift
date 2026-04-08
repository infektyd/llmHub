//
//  ChatViewModel.swift
//  llmHub
//
//  Created by Developer on 12/01/25.
//

import Combine
import Foundation
import FoundationModels
import OSLog
import SwiftData
import SwiftUI

/// Diagnostics information for Apple Foundation Models availability
struct AFMDiagnostics {
    var isAvailable: Bool = false
    var lastCheckTime: Date = Date()
    var reason: String = "Not yet checked"

    var statusColor: Color {
        isAvailable ? .green : .orange
    }

    var reasonText: String {
        reason
    }

    var timeSinceCheck: String {
        let interval = Date().timeIntervalSince(lastCheckTime)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}

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

    /// The message ID this message is replying to (for threaded conversations).
    var replyToMessageID: UUID?

    /// User preference: force all pastes to stay inline regardless of size.
    /// Persisted via UserDefaults.
    @ObservationIgnored
    var forceInlinePaste: Bool {
        get { UserDefaults.standard.bool(forKey: "forceInlinePaste") }
        set { UserDefaults.standard.set(newValue, forKey: "forceInlinePaste") }
    }

    /// Indicates whether the view model is currently streaming/generating a response.
    var isGenerating: Bool = false

    /// Agent IDs currently mentioned in the composer input.
    /// Updated by the composer view via .onChange of input text.
    /// When non-empty, model routing is driven by these mentions instead of manual picker selection.
    var activeMentions: [String] = []

    // MARK: - Agent Iteration Limit UI

    /// Last agent stop reason (if the agent stopped without normal completion).
    var lastAgentStopReason: AgentStopReason?
    /// When true, UI should present the step-limit alert.
    var showAgentStepLimitAlert: Bool = false
    /// When true, UI should present the step-limit configuration sheet.
    var showAgentStepLimitConfigSheet: Bool = false
    /// Which action the config sheet is currently editing.
    var stepLimitConfigMode: StepLimitConfigMode = .continueRun
    /// Input value for "additional steps" when continuing a run.
    var stepLimitAdditionalSteps: Int = 10
    /// Input value for persisted default max iterations.
    var stepLimitDefaultMaxIterations: Int = AgentSettings.maxIterations()

    enum StepLimitConfigMode: String, Sendable {
        case continueRun
        case changeDefault
    }

    /// AFM diagnostics information
    var afmDiagnostics: AFMDiagnostics = AFMDiagnostics()

    // MARK: - Multi-Agent Concurrent Streaming

    /// Per-agent response state for concurrent group chat streaming.
    /// Keyed by agentId, displays in @mention order via orderIndex.
    var multiAgentResponses: [String: AgentResponseState] = [:]

    /// The current context ID for multi-agent streaming (groups responses to same user message).
    private var activeGroupChatContextId: String?

    // MARK: - Multi-Agent Discovery

    /// Discovered agents from the OpenClaw gateway.
    var discoveredAgents: [Agent] = []
    /// Whether agent discovery is currently in progress.
    var isLoadingAgents: Bool = false
    /// Last error during agent discovery, if any.
    var agentDiscoveryError: String?

    // MARK: - Per-Agent Cost Tracking

    /// Per-agent cost snapshots for display in the roster sidebar.
    var agentCostSnapshots: [String: AgentCostSnapshot] = [:]

    /// Records usage for a specific agent (called from OpenClaw provider events).
    func recordAgentUsage(agentID: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int, costUSD: Double) {
        let existing = agentCostSnapshots[agentID]
        agentCostSnapshots[agentID] = AgentCostSnapshot(
            inputTokens: (existing?.inputTokens ?? 0) + inputTokens,
            outputTokens: (existing?.outputTokens ?? 0) + outputTokens,
            cachedTokens: (existing?.cachedTokens ?? 0) + cachedTokens,
            totalCostUSD: (existing?.totalCostUSD ?? 0) + costUSD
        )
    }

    /// Total cost across all agents in the current session.
    var totalAgentCost: AgentCostSnapshot {
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var totalCost: Double = 0
        for snap in agentCostSnapshots.values {
            inputTokens += snap.inputTokens
            outputTokens += snap.outputTokens
            cachedTokens += snap.cachedTokens
            totalCost += snap.totalCostUSD
        }
        return AgentCostSnapshot(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            totalCostUSD: totalCost
        )
    }

    // MARK: - Memory Usage Indicator

    /// Number of memories used in the last response.
    var memoriesUsedCount: Int = 0

    /// Brief summary of memories used (for tooltip).
    var memoriesUsedSummary: String?

    /// Whether to show the memory indicator animation.
    var showMemoryIndicator: Bool = false

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
    /// Coalesces streaming updates to reduce UI churn.
    private var pendingStreamingText: String?
    private var streamingUpdateTask: Task<Void, Never>?
    private let streamingUpdateIntervalNs: UInt64 = 50_000_000
    /// Notification message for context compaction.
    var contextCompactionMessage: String?
    /// Whether to show the context compaction notification.
    var showContextCompactionNotification: Bool = false
    /// Indicates the response was truncated due to max_tokens limit.
    var isTruncated: Bool = false

    // Staging artifacts (files/code pasted into input but not sent yet)
    var stagingArtifacts: [Artifact] = []

    private var task: Task<Void, Never>?
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
            generationID: activeGenerationID,
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

    private func scheduleStreamingUpdate(_ text: String, messageID: UUID) {
        pendingStreamingText = text
        guard streamingUpdateTask == nil else { return }
        streamingUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: streamingUpdateIntervalNs)
            self.applyPendingStreamingUpdate(messageID: messageID)
        }
    }

    private func flushStreamingUpdate(messageID: UUID) {
        streamingUpdateTask?.cancel()
        applyPendingStreamingUpdate(messageID: messageID)
    }

    private func applyPendingStreamingUpdate(messageID: UUID) {
        if let pending = pendingStreamingText {
            streamingText = pending
            setLastVisibleMessage(to: messageID)
        }
        pendingStreamingText = nil
        streamingUpdateTask = nil
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
    /// The active generation task driving the current stream (if any).
    private var generationTask: Task<Void, Never>?
    /// Stable identity for the active generation, used to merge streaming overlay with persisted messages.
    private var activeGenerationID: UUID?

    /// Captures the last run's session ID so we can resume a stopped agent loop.
    private var lastRunSessionID: UUID?
    /// Streaming accumulator for incoming tokens.
    private let streamAccumulator = StreamAccumulator()
    /// Identifier for the current streaming message.
    private var streamingMessageID: UUID?
    /// Timestamp for the streaming message.
    private var streamingStartedAt: Date?

    // MARK: - Tool Execution Timing (STEP 3)

    private var toolExecutionElapsedSeconds: [String: Int] = [:]
    private var toolExecutionCancelHandlers: [String: () -> Void] = [:]
    private var toolExecutionStartDates: [String: Date] = [:]
    private var toolTimerTask: Task<Void, Never>?

    /// Tracks the previous session to trigger cleanup/distillation on switch.
    private var previousSessionID: UUID?

    // Core Actors
    private var workspace: LightweightWorkspace?
    private var authService: ToolAuthorizationService?
    private var toolRegistry: ToolRegistry?
    private var toolExecutor: ToolExecutor?
    private var toolEnvironment: ToolEnvironment = .current

    weak var workbenchVM: WorkbenchViewModel?

    /// Workspace root used for tool/file operations.
    var workspaceRootDisplayPath: String {
        let url =
            toolEnvironment.sandboxRoot
            ?? WorkspaceResolver.resolve(platform: toolEnvironment.platform)
        return url.standardizedFileURL.path
    }

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

        // Preview safety: Canvas previews must not initialize providers/tools or touch the network.
        // Any UI that needs state in previews should use `ChatViewModel.preview(...)`.
        if PreviewMode.isRunning {
            logger.info("PreviewMode: skipping ChatService initialization")
            let emptyToolRegistry = await ToolRegistry(tools: [])
            let emptyToolExecutor = ToolExecutor(registry: emptyToolRegistry, environment: .current)
            let service = ChatService(
                modelContext: modelContext,
                providerRegistry: ProviderRegistry(providerBuilders: []),
                toolRegistry: emptyToolRegistry,
                toolExecutor: emptyToolExecutor,
                toolAuthorizationService: ToolAuthorizationService()
            )
            self.chatService = service
            return service
        }

        // Initialize providers config
        let config = makeDefaultConfig()

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
            { OpenClawProvider(keychain: keychain, config: config.openClaw) },
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
            CodeInterpreterTool(environment: toolEnvironment),
            DataVisualizationTool(),
            ArtifactListTool(),
            ArtifactOpenTool(),
            ArtifactReadTextTool(),
            ArtifactDescribeImageTool(),
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

    // MARK: - Iteration Limit Actions

    func agentStepLimitStopTapped() {
        logger.info("User chose Stop after step limit")
        showAgentStepLimitAlert = false
        showAgentStepLimitConfigSheet = false
        lastAgentStopReason = nil
    }

    func agentStepLimitContinueTapped() {
        logger.info("User chose Continue after step limit")
        stepLimitConfigMode = .continueRun
        stepLimitAdditionalSteps = 10
        showAgentStepLimitConfigSheet = true
    }

    func agentStepLimitChangeDefaultTapped() {
        logger.info("User chose Change Default after step limit")
        stepLimitConfigMode = .changeDefault
        stepLimitDefaultMaxIterations = AgentSettings.maxIterations()
        showAgentStepLimitConfigSheet = true
    }

    func applyAgentStepLimitContinue(modelContext: ModelContext) {
        let additional = AgentSettings.clampMaxIterations(stepLimitAdditionalSteps)
        logger.info("Continuing run with additional steps: \(additional)")
        Task { @MainActor in
            await resumeAfterStepLimit(
                modelContext: modelContext, maxIterationsOverride: additional)
        }
        showAgentStepLimitAlert = false
        showAgentStepLimitConfigSheet = false
    }

    func applyAgentStepLimitDefaultChange(modelContext: ModelContext) {
        let newDefault = AgentSettings.clampMaxIterations(stepLimitDefaultMaxIterations)
        AgentSettings.setMaxIterations(newDefault)
        logger.info("Set default Agent Max Iterations to \(newDefault)")

        // Apply immediately for the current stopped run by granting the delta.
        if case .iterationLimitReached(limit: _, used: let used)? = lastAgentStopReason {
            let additional = max(1, newDefault - used)
            logger.info("Applying new default immediately by resuming with +\(additional) steps")
            Task { @MainActor in
                await resumeAfterStepLimit(
                    modelContext: modelContext, maxIterationsOverride: additional)
            }
        }

        showAgentStepLimitAlert = false
        showAgentStepLimitConfigSheet = false
    }

    // MARK: - Agent Discovery

    /// Fetches available agents from the OpenClaw gateway via /v1/models.
    /// Models with IDs like "openclaw/syntra" are treated as agents.
    func discoverAgents() async {
        isLoadingAgents = true
        agentDiscoveryError = nil
        defer { isLoadingAgents = false }

        let manager = OpenClawManager()
        do {
            let models = try await manager.listModels()
            // Agent models have an "openclaw/<agentId>" format.
            // Extract short IDs and build Agent objects.
            let agents = models.compactMap { model -> Agent? in
                let parts = model.id.split(separator: "/")
                guard parts.count == 2 else { return nil }
                let shortID = String(parts[1])
                guard !shortID.isEmpty, shortID != "default" else { return nil }
                return Agent(
                    id: shortID,
                    name: model.name ?? shortID.capitalized,
                    emoji: Self.emojiForAgent(id: shortID),
                    avatar: nil,
                    status: .online
                )
            }
            discoveredAgents = agents.isEmpty ? Self.defaultAgents : agents
            logger.info("Discovered \(self.discoveredAgents.count) agent(s) from gateway /v1/models")
        } catch {
            agentDiscoveryError = error.localizedDescription
            logger.error("Agent discovery failed: \(error.localizedDescription)")
            // Fall back to hardcoded known agents
            discoveredAgents = Self.defaultAgents
        }
    }

    /// Returns all known agents (already discovered or defaults).
    var allKnownAgents: [Agent] {
        discoveredAgents.isEmpty ? Self.defaultAgents : discoveredAgents
    }

    /// Extracts the current @mention from the text if the cursor is at the end of one.
    /// Returns the partial agent name being typed (without the @).
    func currentMentionAgentSearch(from text: String) -> String? {
        guard let atRange = text.range(of: "@[a-z0-9-]*$", options: .regularExpression) else {
            return nil
        }
        return String(text[atRange].dropFirst())
    }

    /// Extracts @mentions from message text using regex matching.
    /// Returns only agent IDs that are in the validAgentIDs set.
    func extractAgentMentions(from content: String, validAgentIDs: [String]) -> [String] {
        let pattern = "@([a-z0-9-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        let validSet = Set(validAgentIDs.map { $0.lowercased() })
        return matches.compactMap { match -> String? in
            guard let matchRange = Range(match.range(at: 1), in: content) else { return nil }
            let agentName = String(content[matchRange]).lowercased()
            return validSet.contains(agentName) ? agentName : nil
        }
    }

    /// Filters available agents by a search prefix (for @mention autocomplete).
    func agentsMatching(_ prefix: String) -> [Agent] {
        guard !prefix.isEmpty else { return allKnownAgents }
        return allKnownAgents.filter {
            $0.name.lowercased().hasPrefix(prefix.lowercased())
            || $0.id.lowercased().hasPrefix(prefix.lowercased())
        }
    }

    // MARK: - Default Agent Definitions

    private static let defaultAgents: [Agent] = [
        Agent(id: "syntra", name: "Syntra", emoji: "🔵", status: .online),
        Agent(id: "forge", name: "Forge", emoji: "⚒️", status: .online),
        Agent(id: "recon", name: "Recon", emoji: "🔍", status: .online),
        Agent(id: "pulse", name: "Pulse", emoji: "💓", status: .online),
        Agent(id: "council", name: "Council", emoji: "🏛️", status: .online),
    ]

    private static func emojiForAgent(id: String) -> String {
        switch id.lowercased() {
        case "syntra": return "🔵"
        case "forge": return "⚒️"
        case "recon": return "🔍"
        case "pulse": return "💓"
        case "council": return "🏛️"
        default: return "🤖"
        }
    }

    func resumeAfterStepLimit(modelContext: ModelContext, maxIterationsOverride: Int) async {
        guard let sessionID = lastRunSessionID else {
            logger.error("Cannot resume: missing lastRunSessionID")
            return
        }
        guard let generationID = activeGenerationID else {
            logger.error("Cannot resume: missing activeGenerationID")
            return
        }

        // Restart the agent loop from persisted state (safe fallback semantics).
        // Note: ChatService reloads the session each iteration and tool results are persisted as .tool messages.
        do {
            isGenerating = true
            let streamToken = UUID().uuidString
            let streamingID = UUID()
            let streamingStart = Date()

            let (uiStream, uiContinuation) = AsyncStream<String>.makeStream()
            let updateTask = Task { @MainActor in
                for await text in uiStream {
                    self.scheduleStreamingUpdate(text, messageID: streamingID)
                }
                self.flushStreamingUpdate(messageID: streamingID)
            }

            try Task.checkCancellation()
            await streamAccumulator.reset()
            await streamAccumulator.begin(token: streamToken)

            streamingMessageID = streamingID
            streamingStartedAt = streamingStart
            streamingText = nil

            let service = await ensureChatService(modelContext: modelContext)
            let domainSession = try await MainActor.run {
                do {
                    return try service.loadSession(id: sessionID)
                } catch {
                    throw error
                }
            }

            let stream = try await service.streamCompletion(
                for: domainSession,
                userMessage: "",
                generationID: generationID,
                maxIterationsOverride: maxIterationsOverride
            )

            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .token(let text):
                    if let updated = await streamAccumulator.append(token: streamToken, delta: text) {
                        uiContinuation.yield(updated)
                    }

                case .completion(let message):
                    _ = await streamAccumulator.complete(token: streamToken, final: message.content)
                    uiContinuation.finish()
                    _ = await updateTask.result
                    resetStreamingState()
                    isTruncated = false
                    truncatedSessionID = nil
                    executingToolNames.removeAll()
                    setLastVisibleMessage(to: message.id)
                    self.handleStreamCompletion(
                        sessionID: sessionID, modelID: domainSession.model,
                        modelContext: modelContext)

                case .truncated(let message):
                    _ = await streamAccumulator.complete(token: streamToken, final: message.content)
                    uiContinuation.finish()
                    _ = await updateTask.result
                    resetStreamingState()
                    isTruncated = true
                    truncatedSessionID = sessionID
                    executingToolNames.removeAll()
                    setLastVisibleMessage(to: message.id)
                    self.handleStreamCompletion(
                        sessionID: sessionID, modelID: domainSession.model,
                        modelContext: modelContext)

                case .error(let error):
                    await streamAccumulator.fail(token: streamToken, error: error)
                    uiContinuation.finish()
                    _ = await updateTask.result
                    resetStreamingState()
                    isTruncated = false
                    truncatedSessionID = nil
                    executingToolNames.removeAll()
                    self.handleStreamError(
                        sessionID: sessionID, error: error, modelContext: modelContext)

                case .usage, .thinking, .toolUse, .toolExecuting, .toolExecutionStarted,
                    .toolExecutionFinished, .reference, .contextCompacted:
                    // Existing UI hooks are already wired on the primary send path; this continuation
                    // path intentionally stays minimal.
                    break

                case .agentStopped(let reason):
                    uiContinuation.finish()
                    _ = await updateTask.result
                    resetStreamingState()
                    executingToolNames.removeAll()
                    isGenerating = false
                    lastAgentStopReason = reason
                    showAgentStepLimitAlert = true

                case .memoriesUsed(let count, let summary):
                    memoriesUsedCount = count
                    memoriesUsedSummary = summary
                    showMemoryIndicator = true

                    // Auto-hide after 3 seconds
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        self?.showMemoryIndicator = false
                    }
                }
            }

            await streamAccumulator.reset()
            isGenerating = false
            resetStreamingState()
            generationTask = nil

        } catch {
            if error is CancellationError {
                isGenerating = false
                resetStreamingState()
                executingToolNames.removeAll()
                generationTask = nil
                return
            }
            isGenerating = false
            resetStreamingState()
            executingToolNames.removeAll()
            generationTask = nil
            logger.error("Failed to resume after step limit: \(error.localizedDescription)")
        }
    }

    // MARK: - Artifact Staging

    func stageArtifact(_ artifact: Artifact) {
        stagingArtifacts.append(artifact)
    }

    func removeStagedArtifact(id: UUID) {
        stagingArtifacts.removeAll { $0.id == id }
    }

    func clearStagedArtifacts() {
        stagingArtifacts.removeAll()
    }

    // MARK: - Sandbox Import

    /// State for recently imported sandbox artifacts
    var recentlyImportedArtifacts: [SandboxedArtifact] = []

    /// Whether the artifact library panel is visible
    var showArtifactLibrary: Bool = false

    /// Converts a SandboxedArtifact to an Attachment for message sending.
    private func makeAttachment(from sandboxArtifact: SandboxedArtifact) async -> Attachment? {
        let fullPath = await ArtifactSandboxService.shared.artifactPath(for: sandboxArtifact)

        // Determine attachment type from MIME
        let type: AttachmentType
        if sandboxArtifact.mimeType.hasPrefix("image/") {
            type = .image
        } else if sandboxArtifact.mimeType == "application/pdf" {
            type = .pdf
        } else if sandboxArtifact.mimeType.hasPrefix("text/")
            || sandboxArtifact.filename.hasSuffix(".swift")
            || sandboxArtifact.filename.hasSuffix(".py")
            || sandboxArtifact.filename.hasSuffix(".js")
            || sandboxArtifact.filename.hasSuffix(".json") {
            type = .code
        } else {
            type = .text
        }

        // Read preview for text/code files
        let preview: String?
        if type == .code || type == .text {
            if let contents = try? String(contentsOf: fullPath, encoding: .utf8) {
                preview = String(contents.prefix(200))
            } else {
                preview = nil
            }
        } else {
            preview = nil
        }

        return Attachment(
            id: sandboxArtifact.id,
            filename: sandboxArtifact.filename,
            url: fullPath,
            type: type,
            previewText: preview
        )
    }

    /// Import a file from an external location into the artifact sandbox.
    /// This COPIES the file to the sandbox - LLMs can only access the copy.
    ///
    /// - Parameter url: The URL of the file to import.
    /// - Returns: The imported artifact, or nil if import failed.
    @discardableResult
    func importFileToSandbox(url: URL) async -> SandboxedArtifact? {
        do {
            let artifact = try await ArtifactSandboxService.shared.importFile(from: url)
            recentlyImportedArtifacts.append(artifact)

            // AUTO-STAGE: Convert to Attachment and add to staged list
            if let attachment = await makeAttachment(from: artifact) {
                stageAttachmentIfNeeded(attachment)
            }

            logger.info("Imported file to sandbox: \(artifact.filename)")
            return artifact
        } catch {
            logger.error("Failed to import file to sandbox: \(error.localizedDescription)")
            return nil
        }
    }

    /// Import raw data as a file in the artifact sandbox.
    ///
    /// - Parameters:
    ///   - data: The data to save.
    ///   - filename: The desired filename.
    /// - Returns: The created artifact, or nil if import failed.
    @discardableResult
    func importDataToSandbox(data: Data, filename: String) async -> SandboxedArtifact? {
        do {
            let artifact = try await ArtifactSandboxService.shared.importData(
                data, filename: filename)
            recentlyImportedArtifacts.append(artifact)

            // AUTO-STAGE: Convert to Attachment and add to staged list
            if let attachment = await makeAttachment(from: artifact) {
                addAttachment(attachment)
            }
            return artifact
        } catch {
            logger.error("Failed to import data to sandbox: \(error.localizedDescription)")
            return nil
        }
    }

    /// Import an entire folder into the artifact sandbox.
    ///
    /// - Parameter url: The folder URL to import.
    /// - Returns: Array of imported artifacts.
    func importFolderToSandbox(url: URL) async -> [SandboxedArtifact] {
        do {
            let artifacts = try await ArtifactSandboxService.shared.importFolder(from: url)
            recentlyImportedArtifacts.append(contentsOf: artifacts)

            // AUTO-STAGE: Convert to Attachments and add to staged list
            var stagedCount = 0
            for artifact in artifacts {
                if let attachment = await makeAttachment(from: artifact) {
                    if stageAttachmentIfNeeded(attachment) {
                        stagedCount += 1
                    }
                }
            }
            logger.info("✅ Auto-staged \(stagedCount) artifacts as attachments")

            logger.info("Imported folder to sandbox: \(artifacts.count) files")
            return artifacts
        } catch {
            logger.error("Failed to import folder to sandbox: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Large Paste Handling

    /// Handles large pasted text by converting it to an artifact attachment.
    ///
    /// - Parameter text: The pasted text content.
    /// - Returns: A stub string to insert in composer (e.g., "📄 Attached: paste_xxx.json (id: ABC123)"),
    ///            or nil if the paste should remain inline.
    func handleLargePaste(text: String) async -> String? {
        // Evaluate with PasteConversionEngine
        let result = PasteConversionEngine.evaluate(
            text: text,
            forceInline: forceInlinePaste
        )

        // DEBUG-safe logging (no content)
        #if DEBUG
            logger.info(
                "[PASTE] charCount=\(result.charCount), lineCount=\(result.lineCount), action=\(result.action == .attach ? "attach" : "inline"), ext=\(result.detectedExtension)"
            )
        #endif

        // If inline, return nil (no stub needed)
        guard result.action == .attach else {
            return nil
        }

        // Convert text to Data
        guard let data = text.data(using: .utf8) else {
            logger.error("Failed to encode pasted text as UTF-8")
            return nil
        }

        // Import to sandbox
        let artifact = await importDataToSandbox(data: data, filename: result.suggestedFilename)

        guard artifact != nil else {
            logger.error("Failed to import paste to sandbox")
            return nil
        }

        // DEBUG-safe logging
        #if DEBUG
            logger.info(
                "[PASTE] bytesWritten=\(data.count), filename=\(result.suggestedFilename), id=\(result.shortID)"
            )
        #endif

        // Return stub for composer insertion
        return "📄 Attached: \(result.suggestedFilename) (id: \(result.shortID))"
    }

    /// Clear the recently imported artifacts list.
    func clearRecentlyImportedArtifacts() {
        recentlyImportedArtifacts.removeAll()
    }

    /// Get the sandbox path for display in UI.
    var artifactLibraryPath: String {
        ArtifactSandboxService.shared.sandboxURL.path
    }

    /// Refresh tool toggles and authorized tool list, ensuring registry is loaded.
    func refreshToolToggles(modelContext: ModelContext) async {
        guard !PreviewMode.isRunning else { return }
        _ = await ensureChatService(modelContext: modelContext)
        await rebuildToolState(environment: toolEnvironment)
    }

    /// Adds an attachment to the staging area.
    func addAttachment(_ attachment: Attachment) {
        stageAttachmentIfNeeded(attachment)
    }

    @discardableResult
    private func stageAttachmentIfNeeded(_ attachment: Attachment) -> Bool {
        for existing in stagedAttachments {
            if existing.id == attachment.id || existing.url == attachment.url {
                return false
            }
        }
        stagedAttachments.append(attachment)
        #if DEBUG
            let shortID = attachment.id.uuidString.prefix(6)
            let stagedCount = stagedAttachments.count
            logger.info("[ATTACH_STAGE] stagedCount=\(stagedCount), id=\(shortID)")
        #endif
        return true
    }

    /// Removes an attachment from the staging area by index.
    func removeAttachment(at index: Int) {
        guard index >= 0 && index < stagedAttachments.count else { return }
        stagedAttachments.remove(at: index)
    }

    /// Removes an attachment from the staging area by ID.
    func removeStagedAttachment(id: UUID) {
        stagedAttachments.removeAll { $0.id == id }
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
    func rebuildToolState(environment: ToolEnvironment) async {
        guard let registry = toolRegistry else { return }
        let uiDefaults = UIToolDefinition.defaultTools(for: environment)
        var iconMap: [String: String] = [:]
        for tool in uiDefaults {
            let key = tool.name.lowercased()
            iconMap[key] = tool.icon
            iconMap[key.replacingOccurrences(of: " ", with: "_")] = tool.icon
        }

        let tools = await registry.allTools()

        var toggles: [UIToolToggleItem] = []

        for tool in tools {
            let availability = tool.availability(in: environment)
            let permission = authService?.checkAccess(for: tool.name) ?? .notDetermined
            let key = tool.name.lowercased()
            let icon = iconMap[key] ?? "wrench.and.screwdriver"

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
    /// Distillation is intentionally NOT triggered here (archive-only policy).
    func onSessionDeactivated(session: ChatSessionEntity, modelContext: ModelContext) {
        logger.debug(
            "Skipping distillation on session deactivated (archive-only policy, id=\(session.id))")
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

        let targetProvider = modelRegistry.availableProviders()
            .filter { providerName in
                ProviderID.canonicalID(from: providerName) == canonicalSavedProviderID
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
            .first

        if let provider = targetProvider {
            workbenchVM.selectedProvider = provider

            if let model = provider.models.first(where: { model in
                model.modelID == savedModelID
                    || model.modelID.hasSuffix("/\(savedModelID)")
            }) {
                workbenchVM.selectedModel = model
                logger.info("Hydration successful: \(provider.name) -> \(model.name)")
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
            let key = "provider:\(canonicalSavedProviderID)"
            if !Self.loggedMissingModels.contains(key) {
                let available = modelRegistry.availableProviders().joined(separator: ", ")
                logger.warning(
                    "Could not find provider for ID: \(savedProviderID) (canonical: \(canonicalSavedProviderID)). Available: \(available)"
                )
                Self.loggedMissingModels.insert(key)
            }
        }
    }

    // (rest unchanged from your current file)
    // NOTE: leaving everything after hydrateState as-is to avoid unrelated diffs.

    /// Sends a message in the given session.
    func sendMessage(
        messageText: String,
        attachments: [Attachment]? = nil,
        session: ChatSessionEntity,
        modelContext: ModelContext,
        modelRegistry: ModelRegistry? = nil,
        selectedProvider: UILLMProvider? = nil,
        selectedModel: UILLMModel? = nil,
        thinkingPreference: ThinkingPreference = .auto
    ) {
        guard !PreviewMode.isRunning else {
            logger.info("PreviewMode: ignoring sendMessage()")
            return
        }
        // If a generation is already in progress, interrupt: cancel current stream and send the new message.
        if isGenerating {
            let messageTextCopy = messageText
            let attachmentsCopy = attachments
            let selectedProviderCopy = selectedProvider
            let selectedModelCopy = selectedModel
            let thinkingPreferenceCopy = thinkingPreference
            Task { @MainActor in
                await self.stopGeneration()
                self.sendMessage(
                    messageText: messageTextCopy,
                    attachments: attachmentsCopy,
                    session: session,
                    modelContext: modelContext,
                    selectedProvider: selectedProviderCopy,
                    selectedModel: selectedModelCopy,
                    thinkingPreference: thinkingPreferenceCopy
                )
            }
            return
        }
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
        var (providerID, modelID) = mapUISelectionToProviderModel(
            selectedProvider: selectedProvider,
            selectedModel: selectedModel,
            sessionEntity: session
        )

        // Per-message @mention routing: override provider/model for this message only,
        // without mutating the session's default provider/model.
        // Model IDs from the gateway are "openclaw/syntra", "openclaw/forge", etc.
        // Strip the "openclaw/" prefix to get short names for @mention matching.
        // The provider will reconstruct the full "openclaw/<agent>" model ID.
        let registryModelIDs = modelRegistry?.models(for: "OpenClaw").map { $0.id } ?? []
        let shortAgentNames: [String] = registryModelIDs.compactMap { id in
            if id.contains("/") {
                let short = String(id.split(separator: "/").last ?? "")
                return short.isEmpty ? nil : short
            }
            return nil
        }
        let openClawAgentIDs = shortAgentNames.isEmpty
            ? ["syntra", "forge", "recon", "pulse", "council"]
            : shortAgentNames
        // Extract @mentions using regex to avoid false positives
        // (e.g. "forge" in "blacksmith forge" without @ prefix)
        let mentionedAgentIDs = extractAgentMentions(
            from: userMessageText, validAgentIDs: openClawAgentIDs)

        // Single @mention: override provider/model for this message's stream.
        if let firstMention = mentionedAgentIDs.first, mentionedAgentIDs.count == 1 {
            providerID = "openclaw"
            modelID = firstMention
        }

        // Only persist provider/model to session when NOT an @mention override.
        // This keeps the session's default provider stable across messages.
        if mentionedAgentIDs.isEmpty {
            session.providerID = providerID
            session.model = modelID
        }
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
                costBreakdown: nil,
                parentMessageID: replyToMessageID
            )
            // Clear reply state after capturing it
            replyToMessageID = nil

            let userEntity = ChatMessageEntity(message: userDomainMessage)
            userEntity.session = session
            session.updatedAt = Date()
            modelContext.insert(userEntity)
            try modelContext.save()

            // DEBUG-safe attachment metrics (no paths, no content)
            #if DEBUG
                if !messageAttachments.isEmpty {
                    let totalBytes = messageAttachments.reduce(0) { sum, att in
                        let size =
                            (try? FileManager.default.attributesOfItem(atPath: att.url.path)[.size]
                                as? Int) ?? 0
                        return sum + size
                    }
                    let filenames = messageAttachments.map { $0.filename }.joined(separator: ", ")
                    logger.info(
                        "📎 [SEND] attachmentCount=\(messageAttachments.count), totalBytes=\(totalBytes), filenames=[\(filenames)]"
                    )
                }
            #endif
        } catch {
            logger.error("Failed to persist user message: \(error.localizedDescription)")
            return
        }

        // Group chat routing: if multiple agents are @mentioned, handle as group chat.
        if mentionedAgentIDs.count > 1 {
            handleGroupChat(
                messageText: userMessageText,
                mentionedAgentIDs: mentionedAgentIDs,
                session: session,
                modelContext: modelContext
            )
            return
        }

        isGenerating = true
        let streamToken = UUID().uuidString
        let generationID = UUID()
        let streamingID = UUID()
        let streamingStart = Date()

        // Update session's thinking preference from UI before converting to domain
        session.thinkingPreference = thinkingPreference
        logger.info("Using thinkingPreference: \(thinkingPreference.rawValue)")

        let domainSession = session.asDomain()

        generationTask = Task { @MainActor in
            let (uiStream, uiContinuation) = AsyncStream<String>.makeStream()

            let updateTask = Task { @MainActor in
                for await text in uiStream {
                    self.scheduleStreamingUpdate(text, messageID: streamingID)
                }
                self.flushStreamingUpdate(messageID: streamingID)
            }

            do {
                try Task.checkCancellation()
                await streamAccumulator.reset()
                await streamAccumulator.begin(token: streamToken)

                activeGenerationID = generationID
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
                    images: imageAttachments,
                    generationID: generationID
                )

                // Keep enough state to allow an in-place "Continue" after step-limit stop.
                self.lastRunSessionID = sessionID

                for try await event in stream {
                    try Task.checkCancellation()
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

                        resetStreamingState()
                        isTruncated = false
                        truncatedSessionID = nil
                        executingToolNames.removeAll()
                        logger.info(
                            "Completion received, final length: \(message.content.count)")
                        setLastVisibleMessage(to: message.id)

                        // Tag the persisted message with the @mentioned agent's ID
                        // so the UI can show which agent produced this response.
                        if let agentID = mentionedAgentIDs.first {
                            let msgID = message.id
                            await MainActor.run {
                                let desc = FetchDescriptor<ChatMessageEntity>(
                                    predicate: #Predicate { $0.id == msgID })
                                if let entity = try? modelContext.fetch(desc).first {
                                    entity.senderAgentID = agentID
                                    try? modelContext.save()
                                }
                            }
                        }

                        // Ensure environment stability before triggering UI state changes
                        // This gives SwiftUI time to propagate environment updates before
                        // any alert/sheet presentations fire in response to state changes
                        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

                        self.handleStreamCompletion(
                            sessionID: sessionID, modelID: modelID, modelContext: modelContext)

                    case .truncated(let message):
                        _ = await streamAccumulator.complete(
                            token: streamToken,
                            final: message.content
                        )

                        uiContinuation.finish()
                        _ = await updateTask.result

                        resetStreamingState()
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

                        resetStreamingState()
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

                    case .toolExecutionStarted(let id, let name, _):
                        executingToolNames.insert(name)
                        toolExecutionStartDates[id] = Date()
                        let startDate = toolExecutionStartDates[id] ?? Date()
                        let icon =
                            toolToggles.first(where: { $0.id == name })?.icon
                            ?? "wrench.and.screwdriver"

                        if let workbenchVM {
                            workbenchVM.activeToolExecution = ToolExecution(
                                id: id,
                                toolID: name,
                                name: name,
                                icon: icon,
                                status: .running,
                                output: "",
                                elapsedSeconds: 0,
                                timestamp: startDate
                            )
                        }

                        startToolTimer(toolCallID: id) { [weak self] in
                            guard let self else { return }
                            Task { @MainActor in
                                await self.stopGeneration()
                            }
                        }

                        logger.info("Tool execution started: \(name) (id: \(id))")

                    case .toolExecutionFinished(let id, let name, let success, let output):
                        let startDate = toolExecutionStartDates[id] ?? Date()
                        let elapsed = toolExecutionElapsedSeconds[id]
                        let icon =
                            toolToggles.first(where: { $0.id == name })?.icon
                            ?? "wrench.and.screwdriver"
                        let status: ToolExecution.ExecutionStatus = success ? .completed : .failed

                        stopToolTimer(toolCallID: id)
                        executingToolNames.remove(name)

                        if let workbenchVM {
                            workbenchVM.activeToolExecution = ToolExecution(
                                id: id,
                                toolID: name,
                                name: name,
                                icon: icon,
                                status: status,
                                output: output,
                                elapsedSeconds: elapsed,
                                timestamp: startDate
                            )
                        }

                        logger.info(
                            "Tool execution finished: \(name) (id: \(id)), success=\(success)"
                        )

                    case .reference(let ref):
                        logger.debug("Reference: \(ref)")

                    case .contextCompacted(let droppedMessages, let tokensSaved):
                        logger.info(
                            "⚡️ Context compacted: \(droppedMessages) messages dropped, \(tokensSaved) tokens saved"
                        )
                        self.contextCompactionMessage =
                            "⚡️ Context optimized: \(droppedMessages) "
                            + "message\(droppedMessages == 1 ? "" : "s") compacted, "
                            + "\(tokensSaved) tokens saved"
                        self.showContextCompactionNotification = true

                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            self?.showContextCompactionNotification = false
                        }

                    case .agentStopped(let reason):
                        uiContinuation.finish()
                        _ = await updateTask.result

                        resetStreamingState()
                        isTruncated = false
                        truncatedSessionID = nil
                        executingToolNames.removeAll()
                        isGenerating = false

                        logger.warning("Agent stopped: \(String(describing: reason))")
                        lastAgentStopReason = reason

                        // Ensure SwiftData + environment updates complete before showing alert
                        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

                        showAgentStepLimitAlert = true

                    case .memoriesUsed(let count, let summary):
                        memoriesUsedCount = count
                        memoriesUsedSummary = summary
                        showMemoryIndicator = true

                        // Auto-hide after 3 seconds
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            self?.showMemoryIndicator = false
                        }
                    }
                }

                await streamAccumulator.reset()

                isGenerating = false
                resetStreamingState()
                generationTask = nil
                logger.info("Message generation completed")

            } catch {
                if error is CancellationError {
                    uiContinuation.finish()
                    _ = await updateTask.result
                    await streamAccumulator.reset()
                    isGenerating = false
                    resetStreamingState()
                    executingToolNames.removeAll()
                    generationTask = nil
                    logger.info("Generation cancelled")
                    return
                }
                uiContinuation.finish()
                _ = await updateTask.result

                await streamAccumulator.fail(token: streamToken, error: error)
                await streamAccumulator.reset()

                isGenerating = false
                resetStreamingState()
                executingToolNames.removeAll()
                generationTask = nil
                logger.error("Failed to send message: \(error)")

                self.handleStreamError(
                    sessionID: sessionID, error: error, modelContext: modelContext)
            }
        }
    }

    func mapUISelectionToProviderModel(
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

    private func isDeveloperModeManualToolTriggeringEnabled() -> Bool {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "llmHub.appSettings.v1") else { return false }
        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return false
        }
        return settings.developerModeManualToolTriggering
    }

    func triggerTool(
        _ tool: UIToolDefinition,
        workbenchVM: WorkbenchViewModel,
        input: String = "{}"
    ) {
        guard isDeveloperModeManualToolTriggeringEnabled() else {
            let execution = ToolExecution(
                id: UUID().uuidString,
                toolID: tool.id.uuidString,
                name: tool.name,
                icon: tool.icon,
                status: .failed,
                output:
                    "Enable Developer Mode (Manual Tool Triggering) in Settings to run tools manually.",
                timestamp: Date()
            )
            workbenchVM.activeToolExecution = execution
            workbenchVM.toolInspectorVisible = true
            return
        }

        guard let sessionID = workbenchVM.selectedConversationID else {
            let execution = ToolExecution(
                id: UUID().uuidString,
                toolID: tool.id.uuidString,
                name: tool.name,
                icon: tool.icon,
                status: .failed,
                output: "No active conversation selected.",
                timestamp: Date()
            )
            workbenchVM.activeToolExecution = execution
            workbenchVM.toolInspectorVisible = true
            return
        }

        guard let toolExecutor, let authService else {
            let execution = ToolExecution(
                id: UUID().uuidString,
                toolID: tool.id.uuidString,
                name: tool.name,
                icon: tool.icon,
                status: .failed,
                output: "Tool system not initialized.",
                timestamp: Date()
            )
            workbenchVM.activeToolExecution = execution
            workbenchVM.toolInspectorVisible = true
            return
        }

        let toolCallID = UUID().uuidString
        let startedAt = Date()

        toolExecutionStartDates[toolCallID] = startedAt

        workbenchVM.activeToolExecution = ToolExecution(
            id: toolCallID,
            toolID: tool.id.uuidString,
            name: tool.name,
            icon: tool.icon,
            status: .running,
            output: "",
            timestamp: startedAt
        )
        workbenchVM.toolInspectorVisible = true

        let task = Task { [toolEnvironment] in
            let workspacePath =
                toolEnvironment.sandboxRoot
                ?? WorkspaceResolver.resolve(platform: toolEnvironment.platform)
            let context = ToolContext(
                sessionID: sessionID,
                workspacePath: workspacePath,
                session: ToolSession(id: sessionID),
                authorization: authService
            )
            let call = ToolCall(id: toolCallID, name: tool.name, input: input)

            let result = await toolExecutor.executeSingle(call, context: context)

            await MainActor.run {
                if Task.isCancelled {
                    workbenchVM.activeToolExecution = ToolExecution(
                        id: toolCallID,
                        toolID: tool.id.uuidString,
                        name: tool.name,
                        icon: tool.icon,
                        status: .cancelled,
                        output: "Cancelled",
                        elapsedSeconds: self.toolExecutionElapsedSeconds[toolCallID],
                        timestamp: startedAt
                    )
                    self.stopToolTimer(toolCallID: toolCallID)
                    return
                }

                workbenchVM.activeToolExecution = ToolExecution(
                    id: toolCallID,
                    toolID: tool.id.uuidString,
                    name: tool.name,
                    icon: tool.icon,
                    status: result.success ? .completed : .failed,
                    output: result.output,
                    elapsedSeconds: self.toolExecutionElapsedSeconds[toolCallID],
                    timestamp: startedAt
                )
                self.stopToolTimer(toolCallID: toolCallID)
            }
        }

        startToolTimer(toolCallID: toolCallID) { [weak self] in
            task.cancel()
            workbenchVM.activeToolExecution = ToolExecution(
                id: toolCallID,
                toolID: tool.id.uuidString,
                name: tool.name,
                icon: tool.icon,
                status: .cancelled,
                output: "Cancelled",
                elapsedSeconds: self?.toolExecutionElapsedSeconds[toolCallID],
                timestamp: startedAt
            )
            self?.stopToolTimer(toolCallID: toolCallID)
        }
    }

    func generateConversationTitle(for session: ChatSessionEntity, modelName: String) {
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

    func selectEmoji(for content: String) -> String {
        if content.contains("code") || content.contains("swift") || content.contains("python")
            || content.contains("programming") || content.contains("javascript")
            || content.contains("typescript") {
            return "💻"
        } else if content.contains("math") || content.contains("calculate")
            || content.contains("number") || content.contains("equation") {
            return "🧮"
        } else if content.contains("help") || content.contains("how") || content.contains("what")
            || content.contains("why") {
            return "❓"
        } else if content.contains("write") || content.contains("essay") || content.contains("blog")
            || content.contains("article") {
            return "✍️"
        } else if content.contains("search") || content.contains("find") || content.contains("look") {
            return "🔍"
        } else if content.contains("image") || content.contains("photo")
            || content.contains("picture") {
            return "🖼️"
        } else if content.contains("data") || content.contains("analyze")
            || content.contains("analysis") {
            return "📊"
        } else if content.contains("bug") || content.contains("error") || content.contains("fix")
            || content.contains("debug") {
            return "🔧"
        } else {
            return "💬"
        }
    }

    func formatModelName(_ modelID: String) -> String {
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

    func setLastVisibleMessage(to id: UUID?) {
        guard lastVisibleMessageID != id else { return }
        lastVisibleMessageID = id
    }

    func resetStreamingState() {
        streamingText = nil
        streamingMessageID = nil
        streamingStartedAt = nil
        activeGenerationID = nil
        multiAgentResponses.removeAll()
        activeGroupChatContextId = nil
    }

    func handleStreamCompletion(
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

                // Schedule AFM classification after message #3 (debounced; max 1 per conversation)
                if count == 3 {
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
    func scheduleClassification(for session: ChatSessionEntity, modelContext: ModelContext) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard session.afmClassifiedAt == nil else { return }

            let sessionID = session.id
            let debouncer = ConversationClassificationDebouncer.shared
            guard await debouncer.begin(sessionID: sessionID) else { return }
            defer { Task { await debouncer.end(sessionID: sessionID) } }

            // Snapshot value types for background classification.
            let messages = session.messages.sorted { $0.createdAt < $1.createdAt }.map {
                $0.asDomain()
            }

            let service = ConversationClassificationService()

            let task = Task.detached(priority: .utility) {
                return (try? await service.classify(messages: messages))
                    ?? ConversationMetadata.fallback(from: messages)
            }

            let metadata = await task.value

            // Persist back on MainActor.
            session.afmTitle = metadata.title
            session.afmEmoji = metadata.emoji
            session.afmCategory = metadata.category.rawValue
            session.afmIntent = metadata.intent.rawValue
            session.afmTopics = metadata.topics
            session.afmClassifiedAt = Date()
            session.lifecycleIntent = metadata.intent.rawValue
            session.lifecycleRetention = metadata.suggestedRetention.rawValue
            session.isComplete = metadata.isComplete
            session.hasArtifacts = metadata.hasArtifacts

            do {
                try modelContext.save()
                self.logger.info(
                    "Classification completed for session \(session.id): \(metadata.title)")
            } catch {
                self.logger.error("Failed saving classification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Group Chat (@mention routing to multiple agents)

    /// Handles a group chat message where one or more OpenClaw agents are @mentioned.
    /// Routes each agent via the gateway's sessions_send API with dedicated session keys,
    /// ensuring the gateway delivers to the correct agent (not just the first mention).
    /// Streams all agents concurrently using TaskGroup, with per-agent state tracking.
    /// Responses appear in @mention order (orderIndex), not arrival order.
    /// Max 4 agents per message, 120s timeout per agent.
    private func handleGroupChat(
        messageText: String,
        mentionedAgentIDs: [String],
        session: ChatSessionEntity,
        modelContext: ModelContext
    ) {
        // Build Agent objects for the mentioned agents.
        let agentMap = Dictionary(uniqueKeysWithValues: allKnownAgents.map { ($0.id, $0) })
        let targetAgents = mentionedAgentIDs.compactMap { agentMap[$0] }
        guard !targetAgents.isEmpty else { return }

        // Enforce max 4 agents per message
        let cappedAgents = Array(targetAgents.prefix(4))
        if cappedAgents.count < targetAgents.count {
            logger.warning(
                "🔵 [GroupChat] Capped from \(targetAgents.count) to \(cappedAgents.count) agents (max 4)"
            )
        }

        logger.info(
            "🔵 [GroupChat] Concurrent routing to agents: \(cappedAgents.map { $0.id }.joined(separator: ", "))"
        )

        let contextId = UUID().uuidString
        activeGroupChatContextId = contextId
        isGenerating = true
        let generationID = UUID()

        // Initialize per-agent response states in @mention order
        for (index, agent) in cappedAgents.enumerated() {
            multiAgentResponses[agent.id] = AgentResponseState(
                agentId: agent.id,
                contextId: contextId,
                orderIndex: index,
                status: .queued
            )
        }

        // Launch concurrent streaming via the orchestrator
        let orchestrator = GroupChatOrchestrator()

        let agentTasks = orchestrator.startStreaming(
            agents: cappedAgents,
            messageText: messageText,
            contextId: contextId,
            generationID: generationID,
            session: session,
            modelContext: modelContext,
            stateUpdater: { [weak self] state in
                guard let self else { return }
                self.multiAgentResponses[state.id] = state
            },
            onAllComplete: { [weak self] in
                guard let self else { return }
                self.isGenerating = false
                self.generationTask = nil
                self.logger.info("[GroupChat] All agents completed")
            }
        )

        // Store for cancellation via stopGeneration()
        generationTask = Task { @MainActor in
            for task in agentTasks {
                _ = await task.result
            }
        }
    }

    func handleStreamError(sessionID: UUID, error: Error, modelContext: ModelContext) {
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

    /// Stops the current generation if one is in progress
    func stopGeneration() async {
        guard isGenerating else { return }

        // Mark any in-progress multi-agent responses as stale before cancelling
        if !multiAgentResponses.isEmpty {
            _ = activeGroupChatContextId
            for (agentId, _) in multiAgentResponses {
                if var state = multiAgentResponses[agentId] {
                    let isInProgress: Bool
                    switch state.status {
                    case .streaming, .thinking: isInProgress = true
                    default: isInProgress = false
                    }
                    if isInProgress {
                        state.completedAt = Date()
                        multiAgentResponses[agentId] = state
                    }
                }
            }
        }

        // Flip this early to prevent recursive stopGeneration calls via tool cancel handlers.
        isGenerating = false

        if let gen = activeGenerationID {
            await ImageLoader.shared.cancelLoads(for: gen)
        }

        // Cancel all tool executions
        let toolCallIDs = Array(toolExecutionCancelHandlers.keys)
        for toolCallID in toolCallIDs {
            cancelToolExecution(toolCallID: toolCallID)
        }

        // Cancel the active stream task.
        generationTask?.cancel()
        generationTask = nil

        // Reset generation state
        resetStreamingState()
        executingToolNames.removeAll()

        logger.info("Generation stopped by user")
    }

    /// Requests regeneration of an assistant message by re-sending the preceding user message.
    /// - Parameters:
    ///   - messageID: The UUID of the assistant message to regenerate.
    ///   - session: The chat session containing the message.
    ///   - modelContext: The SwiftData model context for persistence.
    func requestRegeneration(
        messageID: UUID,
        session: ChatSessionEntity,
        modelContext: ModelContext
    ) {
        guard !isGenerating else {
            logger.warning("Cannot regenerate while generating")
            return
        }

        logger.info("Regeneration requested for message \(messageID)")

        // Find the assistant message by ID in the session's sorted messages
        let sortedMessages = session.messages.sorted { $0.createdAt < $1.createdAt }

        guard let targetIndex = sortedMessages.firstIndex(where: { $0.id == messageID }) else {
            logger.warning("Message \(messageID) not found in session")
            return
        }

        let targetMessage = sortedMessages[targetIndex]
        guard targetMessage.role == "assistant" else {
            logger.warning("Message \(messageID) is not an assistant message")
            return
        }

        // Find the preceding user message
        let precedingMessages = sortedMessages[..<targetIndex]
        guard let userMessageEntity = precedingMessages.last(where: { $0.role == "user" }) else {
            logger.warning("No preceding user message found for regeneration")
            return
        }

        let userContent = userMessageEntity.content

        // Remove the assistant message and all subsequent messages from SwiftData
        let messagesToRemove = sortedMessages[targetIndex...]
        for message in messagesToRemove {
            modelContext.delete(message)
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save after removing messages: \(error.localizedDescription)")
            return
        }

        // Re-send the user message
        sendMessage(
            messageText: userContent,
            session: session,
            modelContext: modelContext
        )
    }

    // MARK: - AFM Diagnostics

    /// Check if Apple Foundation Models are available
    func checkAFMAvailability(retryDelay: TimeInterval = 0) {
        Task {
            if retryDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }

            // Use FoundationModels framework for availability check
            let isAvailable = await checkFoundationModelsAvailability()

            await MainActor.run {
                afmDiagnostics.isAvailable = isAvailable
                afmDiagnostics.lastCheckTime = Date()
                afmDiagnostics.reason =
                    isAvailable
                    ? "Foundation Models available"
                    : "Foundation Models not available on this system"
            }
        }
    }

    /// Retry AFM check with exponential backoff
    func retryAFMCheck() {
        checkAFMAvailability(retryDelay: 2.0)
    }

    /// Check if Foundation Models are available using system APIs
    func checkFoundationModelsAvailability() async -> Bool {
        if #available(macOS 15.0, iOS 18.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    // MARK: - Tool Execution Timing (STEP 3)

    /// Start tracking elapsed time for a tool execution
    func startToolTimer(toolCallID: String, cancelHandler: @escaping () -> Void) {
        if toolExecutionStartDates[toolCallID] == nil {
            toolExecutionStartDates[toolCallID] = Date()
        }
        toolExecutionElapsedSeconds[toolCallID] = 0
        toolExecutionCancelHandlers[toolCallID] = cancelHandler

        // Start or restart the timer task if needed
        if toolTimerTask == nil || toolTimerTask?.isCancelled == true {
            toolTimerTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                    // Update all active tool timers (throttled to 1 Hz)
                    let toolCallIDs = Array(toolExecutionElapsedSeconds.keys)
                    for toolCallID in toolCallIDs {
                        toolExecutionElapsedSeconds[toolCallID, default: 0] += 1

                        if let workbenchVM,
                            var active = workbenchVM.activeToolExecution,
                            active.id == toolCallID {
                            active.elapsedSeconds = toolExecutionElapsedSeconds[toolCallID]
                            workbenchVM.activeToolExecution = active
                        }
                    }
                }
            }
        }
    }

    /// Stop tracking elapsed time for a tool execution
    func stopToolTimer(toolCallID: String) {
        toolExecutionElapsedSeconds.removeValue(forKey: toolCallID)
        toolExecutionCancelHandlers.removeValue(forKey: toolCallID)
        toolExecutionStartDates.removeValue(forKey: toolCallID)

        // Cancel timer task if no tools are running
        if toolExecutionElapsedSeconds.isEmpty {
            toolTimerTask?.cancel()
            toolTimerTask = nil
        }
    }

    /// Cancel a running tool execution
    func cancelToolExecution(toolCallID: String) {
        guard let cancelHandler = toolExecutionCancelHandlers[toolCallID] else { return }
        toolExecutionCancelHandlers.removeValue(forKey: toolCallID)
        cancelHandler()
        stopToolTimer(toolCallID: toolCallID)
    }

    #if DEBUG
        /// Internal hook used by preview factories to set streaming-related state without initializing runtime services.
        ///
        /// Rationale: streaming join keys (`generationID`) and message IDs are stored in private properties so the
        /// production pipeline can manage them consistently. Previews still need to drive those fields deterministically.
        func _applyPreviewStreamingState(
            isGenerating: Bool,
            streamingText: String?,
            generationID: UUID?,
            streamingMessageID: UUID?,
            streamingStartedAt: Date?,
            executingToolNames: Set<String>
        ) {
            self.executingToolNames = executingToolNames
            self.isGenerating = isGenerating

            if isGenerating, let text = streamingText {
                self.streamingText = text
                self.streamingStartedAt = streamingStartedAt
                self.streamingMessageID = streamingMessageID
                self.activeGenerationID = generationID
            } else {
                self.streamingText = nil
                self.streamingStartedAt = nil
                self.streamingMessageID = nil
                self.activeGenerationID = nil
            }
        }
    #endif
}
