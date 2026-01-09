//
//  ChatService.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Shared URLSession for LLM traffic
/// Centralized session tuned to reduce QUIC log noise and multipath churn.
enum LLMURLSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        #if os(iOS) || os(visionOS)
            if #available(iOS 11.0, visionOS 1.0, *) {
                configuration.multipathServiceType = .none
            }
        #endif
        // QUIC log spam on simulators is a known OS issue.
        // We keep HTTP/2 default negotiation and avoid HTTP/3-only paths.
        return URLSession(configuration: configuration)
    }()

    static func data(
        for request: URLRequest,
        maxRetries: Int = 1,
        backoffSeconds: TimeInterval = 0.5
    ) async throws -> (Data, URLResponse) {
        try await retrying(maxRetries: maxRetries, backoffSeconds: backoffSeconds) {
            try await shared.data(for: request)
        }
    }

    static func data(
        from url: URL,
        maxRetries: Int = 1,
        backoffSeconds: TimeInterval = 0.5
    ) async throws -> (Data, URLResponse) {
        try await retrying(maxRetries: maxRetries, backoffSeconds: backoffSeconds) {
            try await shared.data(from: url)
        }
    }

    static func bytes(
        for request: URLRequest,
        maxRetries: Int = 1,
        backoffSeconds: TimeInterval = 0.5
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await retrying(maxRetries: maxRetries, backoffSeconds: backoffSeconds) {
            try await shared.bytes(for: request)
        }
    }

    private static func retrying<T>(
        maxRetries: Int,
        backoffSeconds: TimeInterval,
        operation: () async throws -> T
    ) async throws -> T {
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                if (error is CancellationError) || attempt >= maxRetries || !shouldRetry(error) {
                    throw error
                }
                let delay = backoffDelay(base: backoffSeconds, attempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw URLError(.unknown)
    }

    private static func backoffDelay(base: TimeInterval, attempt: Int) -> TimeInterval {
        base * pow(2.0, Double(attempt))
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case URLError.timedOut.rawValue,
                URLError.cannotFindHost.rawValue,
                URLError.cannotConnectToHost.rawValue,
                URLError.networkConnectionLost.rawValue,
                URLError.dnsLookupFailed.rawValue,
                URLError.notConnectedToInternet.rawValue,
                URLError.secureConnectionFailed.rawValue,
                URLError.cannotLoadFromNetwork.rawValue,
                URLError.internationalRoamingOff.rawValue,
                URLError.callIsActive.rawValue,
                URLError.dataNotAllowed.rawValue:
                return true
            default:
                break
            }
        }
        return false
    }
}

/// Service responsible for managing chat sessions, messages, and interactions with LLM providers.
/// Service responsible for managing chat sessions, messages, and interactions with LLM providers.
final class ChatService {
    /// The SwiftData model context.
    let modelContext: ModelContext
    /// Registry of available LLM providers.
    let providerRegistry: ProviderRegistry
    /// Calculator for session costs.
    private let costCalculator: CostCalculator
    /// Tool environment snapshot.
    private let toolEnvironment: ToolEnvironment
    /// Registry of available tools.
    private let toolRegistry: ToolRegistry
    /// Execution engine for tools.
    private let toolExecutor: ToolExecutor
    /// User authorization service for tools (optional).
    private let toolAuthorizationService: ToolAuthorizationService?
    /// Context management service for compaction.
    private let contextManager: ContextManagementService
    /// Service for retrieving relevant memories.
    private let memoryRetrievalService: MemoryRetrievalService
    /// Service for memory management.
    private let memoryManagementService: MemoryManagementService

    /// Logger instance.
    private let logger = Logger(subsystem: "com.llmhub", category: "ChatService")

    /// Default maximum number of tool execution loops to prevent infinite recursion.
    /// Note: this is overridden per-run by the persisted user setting in `AgentSettings`.
    private let defaultMaxToolIterations = AgentSettings.defaultMaxIterations

    private struct TokenBatcher {
        private(set) var buffer: String = ""
        private var lastFlushTime: TimeInterval = Date().timeIntervalSinceReferenceDate
        private let flushInterval: TimeInterval

        init(flushInterval: TimeInterval = 0.05) {
            self.flushInterval = flushInterval
        }

        mutating func append(_ delta: String) -> String? {
            guard !delta.isEmpty else { return nil }
            buffer += delta
            if shouldFlush(afterAppending: delta) {
                return flush()
            }
            return nil
        }

        mutating func flush() -> String? {
            guard !buffer.isEmpty else { return nil }
            let out = buffer
            buffer = ""
            lastFlushTime = Date().timeIntervalSinceReferenceDate
            return out
        }

        private func shouldFlush(afterAppending delta: String) -> Bool {
            if delta.contains("\n") { return true }
            if endsWithBoundary(buffer) { return true }
            let now = Date().timeIntervalSinceReferenceDate
            return (now - lastFlushTime) >= flushInterval
        }

        private func endsWithBoundary(_ s: String) -> Bool {
            guard let last = s.unicodeScalars.last else { return false }
            switch last {
            case ".", "!", "?", ":", ";", ")", "]", "}":
                return true
            default:
                return false
            }
        }
    }

    /// Initializes a new `ChatService`.
    /// - Parameters:
    ///   - modelContext: The SwiftData context.
    ///   - providerRegistry: The provider registry.
    ///   - costCalculator: The cost calculator (default: new instance).
    ///   - toolRegistry: The tool registry.
    ///   - toolExecutor: The tool executor.
    ///   - contextManager: The context management service (default: new instance).
    init(
        modelContext: ModelContext,
        providerRegistry: ProviderRegistry,
        costCalculator: CostCalculator = CostCalculator(),
        toolRegistry: ToolRegistry,
        toolExecutor: ToolExecutor,
        toolAuthorizationService: ToolAuthorizationService? = nil,
        contextManager: ContextManagementService = ContextManagementService(),
        memoryRetrievalService: MemoryRetrievalService = MemoryRetrievalService(),
        memoryManagementService: MemoryManagementService = MemoryManagementService()
    ) {
        self.modelContext = modelContext
        self.providerRegistry = providerRegistry
        self.costCalculator = costCalculator
        let environment = ToolEnvironment.current
        self.toolEnvironment = environment
        self.toolRegistry = toolRegistry
        self.toolExecutor = toolExecutor
        self.toolAuthorizationService = toolAuthorizationService
        self.contextManager = contextManager
        self.memoryRetrievalService = memoryRetrievalService
        self.memoryManagementService = memoryManagementService
    }

    // MARK: - Timeout Helper

    /// Races an async operation against a timeout.
    /// - Parameters:
    ///   - seconds: Timeout in seconds
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation if it completes before timeout
    /// - Throws: ToolError.timeout if timeout is reached, or the operation's error
    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw ToolError.timeout(after: TimeInterval(seconds))
            }

            // Return first result (either completion or timeout)
            guard let result = try await group.next() else {
                group.cancelAll()
                throw ToolError.executionFailed(
                    "Task group completed without result", retryable: true)
            }

            group.cancelAll()
            return result
        }
    }

    // MARK: - Sessions

    /// Loads all chat sessions from storage, sorted by update time.
    /// - Returns: An array of `ChatSession`.
    func loadSessions() throws -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSessionEntity>(sortBy: [
            SortDescriptor(\.updatedAt, order: .reverse)
        ])
        let entities = try modelContext.fetch(descriptor)

        // Rationale: Persisted provider IDs may come from legacy UI/model registries (e.g. "OpenAI", "openAI").
        // Normalize in-place so subsequent lookups and UI hydration are stable.
        var didMigrate = false
        for entity in entities {
            let canonical =
                providerRegistry.canonicalProviderID(for: entity.providerID)
                ?? ProviderID.canonicalID(from: entity.providerID)
            if entity.providerID != canonical {
                entity.providerID = canonical
                didMigrate = true
            }
        }
        if didMigrate {
            do {
                try modelContext.save()
            } catch {
                logger.error(
                    "Failed to persist providerID migration: \(error.localizedDescription)")
            }
        }

        return entities.map { $0.asDomain() }
    }

    /// Creates a new chat session.
    /// - Parameters:
    ///   - providerID: The ID of the LLM provider.
    ///   - model: The model identifier.
    /// - Returns: The created `ChatSession`.
    func createSession(providerID: String, model: String) throws -> ChatSession {
        let referenceID = ReferenceFormatter.newReferenceID()
        // Rationale: Store canonical provider IDs to avoid case/alias drift.
        let canonicalProviderID =
            providerRegistry.canonicalProviderID(for: providerID)
            ?? ProviderID.canonicalID(from: providerID)
        let session = ChatSession(
            id: UUID(),
            title: "Untitled",
            providerID: canonicalProviderID,
            model: model,
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(
                lastTokenUsage: nil, totalCostUSD: .zero, referenceID: referenceID)
        )
        let entity = ChatSessionEntity(session: session)
        modelContext.insert(entity)
        try modelContext.save()
        return session
    }

    /// Appends a message to an existing session.
    /// - Parameters:
    ///   - message: The message to append.
    ///   - sessionID: The ID of the session.
    func appendMessage(_ message: ChatMessage, to sessionID: UUID) throws {
        // Hard guard: never persist sidecar-origin messages into the main transcript.
        // Sidecar outputs are allowed only as ephemeral UI artifacts/logs.
        if message.provenance.channel == .sidecar {
            logger.info(
                "Skipping append of sidecar message (id=\(message.id), model=\(message.provenance.model ?? "unknown"))"
            )
            return
        }

        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }

        // Defensive guard: avoid inserting duplicate message IDs that would crash LazyVStack.
        if entity.messages.contains(where: { $0.id == message.id }) {
            logger.error(
                "Duplicate message id detected (\(message.id)); skipping append to maintain unique IDs."
            )
            return
        }

        let messageEntity = ChatMessageEntity(message: message)
        messageEntity.session = entity
        entity.messages.append(messageEntity)
        entity.updatedAt = Date()
        try modelContext.save()

        // Example usage (Phase 1): schedule a single background classification after message #3.
        // User messages are often persisted outside ChatService, so this is best-effort.
        if entity.messages.count == 3 {
            scheduleClassificationIfNeeded(sessionID: sessionID)
        }
    }

    /// Schedules a single debounced classification after message #3.
    /// - Note: Runs classification in `Task.detached(priority: .utility)` and persists results on MainActor.
    func scheduleClassificationIfNeeded(sessionID: UUID) {
        Task { @MainActor in
            guard
                let session = try? self.modelContext.fetch(
                    FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
                ).first
            else { return }

            guard session.afmClassifiedAt == nil else { return }
            guard session.messages.count >= 3 else { return }

            let debouncer = ConversationClassificationDebouncer.shared
            guard await debouncer.begin(sessionID: sessionID) else { return }
            defer { Task { await debouncer.end(sessionID: sessionID) } }

            let messages = session.messages.sorted { $0.createdAt < $1.createdAt }.map {
                $0.asDomain()
            }

            let service = ConversationClassificationService()

            let task = Task.detached(priority: .utility) {
                return (try? await service.classify(messages: messages))
                    ?? ConversationMetadata.fallback(from: messages)
            }

            let metadata = await task.value

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

            try? self.modelContext.save()
        }
    }

    /// Streams a completion response from the LLM for a given session.
    /// - Parameters:
    ///   - session: The chat session.
    ///   - userMessage: The user's input message.
    ///   - attachments: Optional attachments to persist with the user message.
    ///   - images: Optional images to include in the request.
    /// - Returns: An async throwing stream of `ProviderEvent`.
    func streamCompletion(
        for session: ChatSession,
        userMessage: String,
        attachments: [Attachment] = [],
        references: [ChatReference] = [],
        images: [Data] = [],
        generationID: UUID,
        maxIterationsOverride: Int? = nil
    ) async throws -> AsyncThrowingStream<ProviderEvent, Error> {

        // User messages are persisted by the caller (ChatViewModel) to avoid
        // double-insertion/ghost rendering. This method only streams the response.

        logger.debug("Using provider: \(session.providerID), model: \(session.model)")
        logger.info(
            "🔵 [ChatService] streamCompletion called - provider: \(session.providerID), model: \(session.model), userMessage length: \(userMessage.count)"
        )

        let provider = try providerRegistry.provider(for: session.providerID)
        logger.info("🟢 [ChatService] Provider resolved: \(type(of: provider))")
        let sessionID = session.id
        let registry = self.toolRegistry
        let executor = self.toolExecutor
        let maxIterations = AgentSettings.clampMaxIterations(
            maxIterationsOverride ?? AgentSettings.maxIterations()
        )
        let logger = self.logger
        let service = self
        // Capture environment for ToolContext
        let env = self.toolEnvironment
        // Session-scoped tool state (cache, shell sessions) for this chat session.
        let toolSession = ToolSession(id: sessionID)

        return AsyncThrowingStream(ProviderEvent.self) { continuation in
            let task = Task {
                do {
                    var iterationCount = 0
                    var continueLoop = true
                    var lastToolNameAttempted: String? = nil

                    while continueLoop && iterationCount < maxIterations {
                        try Task.checkCancellation()
                        iterationCount += 1
                        continueLoop = false

                        // Reload session to get updated history (including any tool results)
                        let currentSession = try await MainActor.run {
                            try service.loadSession(id: sessionID)
                        }

                        // Start from persisted history, but enrich the most recent user message
                        // with any inline images/attachments for this request only.
                        var llmMessages = currentSession.messages

                        // Defense-in-depth: never include sidecar-origin content in chat prompting,
                        // even if it somehow made it into persistence.
                        llmMessages.removeAll { $0.provenance.channel == .sidecar }
                        if !images.isEmpty || !attachments.isEmpty || !references.isEmpty,
                            let lastUserIndex = llmMessages.lastIndex(where: { $0.role == .user })
                        {
                            let baseUserMessage = llmMessages[lastUserIndex]

                            // Build updated parts by appending images if provided
                            var updatedParts = baseUserMessage.parts
                            if updatedParts.isEmpty {
                                updatedParts = [.text(baseUserMessage.content)]
                            }
                            if !images.isEmpty {
                                for imgData in images {
                                    let mimeType = detectImageMimeType(from: imgData)
                                    updatedParts.append(.image(imgData, mimeType: mimeType))
                                }
                            }

                            // Build updated attachments if provided
                            let updatedAttachments =
                                attachments.isEmpty ? baseUserMessage.attachments : attachments

                            // Append references as a clearly delimited block for this request only.
                            if !references.isEmpty {
                                let refBlock = ReferenceFormatter.formatForRequest(references)
                                if !refBlock.isEmpty {
                                    updatedParts.append(.text("\n\n" + refBlock))
                                }
                            }

                            // Append attachment contents for this request only (do not persist inline in chat).
                            if !updatedAttachments.isEmpty {
                                let attachmentBlock = service.formatAttachmentsForRequest(
                                    updatedAttachments)
                                if !attachmentBlock.isEmpty {
                                    updatedParts.append(.text("\n\n" + attachmentBlock))
                                }
                            }

                            // Create a new ChatMessage copying all fields, but with updated parts/attachments
                            let updatedUserMessage = ChatMessage(
                                id: baseUserMessage.id,
                                role: baseUserMessage.role,
                                content: baseUserMessage.content,
                                thoughtProcess: baseUserMessage.thoughtProcess,
                                parts: updatedParts,
                                attachments: updatedAttachments,
                                createdAt: baseUserMessage.createdAt,
                                codeBlocks: baseUserMessage.codeBlocks,
                                tokenUsage: baseUserMessage.tokenUsage,
                                costBreakdown: baseUserMessage.costBreakdown,
                                toolCallID: baseUserMessage.toolCallID,
                                toolCalls: baseUserMessage.toolCalls
                            )

                            llmMessages[lastUserIndex] = updatedUserMessage
                        }

                        // Compact context if needed before sending to provider
                        // RETRIEVAL (Phase 2): On first user message, prepend relevant memories
                        // as plain XML in the system prompt BEFORE compaction so it is token-accounted.
                        var messagesForCompaction = llmMessages
                        let isFirstInteraction = llmMessages.filter { $0.role == .user }.count == 1

                        if isFirstInteraction {
                            let snapshots = await service.memoryRetrievalService
                                .retrieveRelevantSnapshots(
                                    for: userMessage,
                                    providerID: currentSession.providerID,
                                    modelContext: service.modelContext
                                )
                            let memoryXML = await Task {
                                MemoryRetrievalService.formatSnapshotsForSystemPrompt(snapshots)
                            }.value

                            if !snapshots.isEmpty {
                                logger.debug(
                                    "Injected \(snapshots.count) memories into system prompt")

                                if var firstMsg = messagesForCompaction.first,
                                    firstMsg.role == .system
                                {
                                    firstMsg.content = "\(memoryXML)\n\n\(firstMsg.content)"
                                    messagesForCompaction[0] = firstMsg
                                } else {
                                    let systemMsg = ChatMessage(
                                        id: UUID(),
                                        role: .system,
                                        content: memoryXML,
                                        parts: [],
                                        createdAt: Date(),
                                        codeBlocks: []
                                    )
                                    messagesForCompaction.insert(systemMsg, at: 0)
                                }
                            }
                        }

                        // Build tool definitions for provider, filtered by user authorization.
                        let availableTools = await registry.availableTools(in: env)

                        // SECURITY: Always check authorization, even if auth service is nil.
                        // Secure-by-default: tools are disabled unless explicitly authorized.
                        var enabledTools: [any Tool] = []
                        if let auth = service.toolAuthorizationService {
                            // Conversation-scoped authorization check
                            for tool in availableTools {
                                let status = auth.checkAccess(for: tool.name, conversationID: currentSession.conversationID)
                                if status == .authorized {
                                    enabledTools.append(tool)
                                } else {
                                    logger.debug("🔒 Tool '\(tool.name)' blocked (status: \(status)) for conversation \(currentSession.conversationID.uuidString.prefix(8))")
                                }
                            }
                        } else {
                            // No authorization service = no tools enabled (secure by default)
                            logger.warning("⚠️ No authorization service configured, all tools disabled")
                        }

                        let exportedToolDefs = enabledTools.compactMap { ToolDefinition(from: $0) }
                        let allToolDefs: [ToolDefinition] = exportedToolDefs

                        // Inject an authoritative tool manifest into the system prompt so models don't hallucinate tooling.
                        let toolManifest = ToolManifest.systemPrompt(
                            tools: allToolDefs,
                            toolCallingAvailable: provider.supportsToolCalling
                        )
                        if var firstMsg = messagesForCompaction.first, firstMsg.role == .system {
                            firstMsg.content = ToolManifest.upsert(
                                into: firstMsg.content,
                                toolManifest: toolManifest
                            )
                            messagesForCompaction[0] = firstMsg
                        } else {
                            let systemMsg = ChatMessage(
                                id: UUID(),
                                role: .system,
                                content: toolManifest,
                                parts: [],
                                createdAt: Date(),
                                codeBlocks: []
                            )
                            messagesForCompaction.insert(systemMsg, at: 0)
                        }

                        let compactionResult = try await service.contextManager.compact(
                            messages: messagesForCompaction,
                            maxTokens: nil,  // Will use model's context window or config default
                            providerID: currentSession.providerID,
                            rollingSummaryGenerator: {
                                @MainActor messagesToSummarize, summaryMaxTokens in
                                try await service.generateRollingSummary(
                                    provider: provider,
                                    model: currentSession.model,
                                    messagesToSummarize: messagesToSummarize,
                                    summaryMaxTokens: summaryMaxTokens
                                )
                            }
                        )

                        // Notify UI if compaction occurred
                        if compactionResult.droppedCount > 0 {
                            let tokensSaved =
                                compactionResult.originalTokens - compactionResult.finalTokens
                            continuation.yield(
                                .contextCompacted(
                                    droppedMessages: compactionResult.droppedCount,
                                    tokensSaved: tokensSaved
                                ))
                        }

                        // Use compacted messages for the request
                        let compactedMessages = compactionResult.compactedMessages

                        let toolDefsForProvider: [ToolDefinition]? =
                            (provider.supportsToolCalling && !allToolDefs.isEmpty)
                            ? allToolDefs : nil

                        let options = LLMRequestOptions(
                            thinkingPreference: currentSession.thinkingPreference,
                            thinkingBudgetTokens: nil
                        )

                        // Use compacted messages for the request
                        let messagesForRequest = compactedMessages

                        logger.info(
                            "🔵 [ChatService] Building request - messages: \(messagesForRequest.count), tools: \(toolDefsForProvider?.count ?? 0), thinking: \(options.thinkingPreference.rawValue)"
                        )

                        let request = try await provider.buildRequest(
                            messages: messagesForRequest,
                            model: currentSession.model,
                            tools: toolDefsForProvider,
                            options: options
                        )

                        logger.info("🟢 [ChatService] Request built successfully")

                        // Track accumulated tool calls for this iteration
                        var accumulatedToolCalls: [ToolCall] = []
                        var assistantTextBuffer = ""
                        var tokenBatcher = TokenBatcher()
                        var didPersistAssistantMessage = false

                        // Stream response
                        logger.info("🔵 [ChatService] Starting to stream response from provider...")
                        var eventCount = 0
                        for try await event in provider.streamResponse(from: request) {
                            try Task.checkCancellation()
                            eventCount += 1
                            if eventCount <= 3 {
                                logger.info(
                                    "🟢 [ChatService] Received event #\(eventCount): \(String(describing: type(of: event)))"
                                )
                            }
                            switch event {
                            case .token(let text):
                                assistantTextBuffer += text
                                if let flushed = tokenBatcher.append(text) {
                                    continuation.yield(.token(text: flushed))
                                }

                            case .thinking(let thought):
                                continuation.yield(.thinking(thought))

                            case .toolUse(let id, let name, let input):
                                logger.debug("ChatService: Tool call detected: \(name)")
                                lastToolNameAttempted = name
                                if let flushed = tokenBatcher.flush() {
                                    continuation.yield(.token(text: flushed))
                                }
                                // Notify UI of tool use
                                continuation.yield(.toolUse(id: id, name: name, input: input))

                                // Accumulate the tool call
                                accumulatedToolCalls.append(
                                    ToolCall(id: id, name: name, input: input))

                            case .toolExecuting:
                                // This event is only emitted by ChatService, not providers.
                                break

                            case .usage(let usage):
                                if let flushed = tokenBatcher.flush() {
                                    continuation.yield(.token(text: flushed))
                                }
                                continuation.yield(.usage(usage))

                            case .reference(let ref):
                                continuation.yield(.reference(ref))

                            case .completion(let msg):
                                if let flushed = tokenBatcher.flush() {
                                    continuation.yield(.token(text: flushed))
                                }
                                // Some providers only include tool calls on the final completion
                                // message with empty content. If so, treat them as pending tool uses
                                // and keep the agent loop going.
                                if accumulatedToolCalls.isEmpty,
                                    let toolCalls = msg.toolCalls,
                                    !toolCalls.isEmpty
                                {
                                    logger.info(
                                        "Completion contained tool calls: \(toolCalls.count), continuing agent loop."
                                    )
                                    accumulatedToolCalls = toolCalls
                                    for tc in toolCalls {
                                        continuation.yield(
                                            .toolUse(
                                                id: tc.id, name: tc.name,
                                                input: tc.input))  // Rough serialization
                                    }
                                }

                                // If we have tool calls, save assistant message with them
                                if !accumulatedToolCalls.isEmpty {
                                    var assistantMsg = msg
                                    assistantMsg.generationID = generationID
                                    if assistantMsg.content.isEmpty && !assistantTextBuffer.isEmpty
                                    {
                                        // Rebuild message to update immutable `parts`
                                        assistantMsg = ChatMessage(
                                            id: msg.id,
                                            generationID: generationID,
                                            role: msg.role,
                                            content: assistantTextBuffer,
                                            thoughtProcess: msg.thoughtProcess,
                                            parts: [.text(assistantTextBuffer)],
                                            attachments: msg.attachments,
                                            createdAt: msg.createdAt,
                                            codeBlocks: msg.codeBlocks,
                                            tokenUsage: msg.tokenUsage,
                                            costBreakdown: msg.costBreakdown,
                                            toolCallID: msg.toolCallID,
                                            toolCalls: accumulatedToolCalls
                                        )
                                    } else {
                                        // Keep existing parts; just attach tool calls
                                        assistantMsg.toolCalls = accumulatedToolCalls
                                    }
                                    try await MainActor.run {
                                        try service.appendMessage(assistantMsg, to: sessionID)
                                    }
                                    didPersistAssistantMessage = true
                                } else {
                                    // Normal completion - save and we're done
                                    var persisted = msg
                                    persisted.generationID = generationID
                                    try await MainActor.run {
                                        try service.appendMessage(persisted, to: sessionID)
                                    }
                                    continuation.yield(.completion(message: persisted))
                                    didPersistAssistantMessage = true
                                }

                            case .error(let error):
                                if let flushed = tokenBatcher.flush() {
                                    continuation.yield(.token(text: flushed))
                                }
                                continuation.yield(.error(error))

                            case .truncated(let msg):
                                if let flushed = tokenBatcher.flush() {
                                    continuation.yield(.token(text: flushed))
                                }
                                // Response was truncated due to max_tokens limit
                                // Handle like completion but forward the truncated event
                                if accumulatedToolCalls.isEmpty,
                                    let toolCalls = msg.toolCalls,
                                    !toolCalls.isEmpty
                                {
                                    accumulatedToolCalls = toolCalls
                                    for tc in toolCalls {
                                        continuation.yield(
                                            .toolUse(
                                                id: tc.id, name: tc.name,
                                                input: tc.input))
                                    }
                                }

                                if !accumulatedToolCalls.isEmpty {
                                    var assistantMsg = msg
                                    assistantMsg.generationID = generationID
                                    assistantMsg.toolCalls = accumulatedToolCalls
                                    try await MainActor.run {
                                        try service.appendMessage(assistantMsg, to: sessionID)
                                    }
                                    didPersistAssistantMessage = true
                                } else {
                                    var persisted = msg
                                    persisted.generationID = generationID
                                    try await MainActor.run {
                                        try service.appendMessage(persisted, to: sessionID)
                                    }
                                    continuation.yield(.truncated(message: persisted))
                                    didPersistAssistantMessage = true
                                }

                            case .contextCompacted:
                                break

                            case .agentStopped:
                                // Providers never emit this; only ChatService emits agentStopped.
                                break
                            }
                        }

                        if let flushed = tokenBatcher.flush() {
                            continuation.yield(.token(text: flushed))
                        }

                        // After stream completes, execute any pending tool calls
                        if !accumulatedToolCalls.isEmpty {
                            try Task.checkCancellation()
                            if !didPersistAssistantMessage {
                                let assistantMsg = ChatMessage(
                                    id: UUID(),
                                    generationID: generationID,
                                    role: .assistant,
                                    content: assistantTextBuffer,
                                    thoughtProcess: nil,
                                    parts: assistantTextBuffer.isEmpty
                                        ? [] : [.text(assistantTextBuffer)],
                                    createdAt: Date(),
                                    codeBlocks: [],
                                    tokenUsage: nil,
                                    costBreakdown: nil,
                                    toolCallID: nil,
                                    toolCalls: accumulatedToolCalls
                                )
                                try await MainActor.run {
                                    try service.appendMessage(assistantMsg, to: sessionID)
                                }
                            }

                            // Execute using ToolExecutor
                            // This runs concurrently and handles caching/slots
                            let workspacePath =
                                env.sandboxRoot ?? WorkspaceResolver.resolve(platform: env.platform)
                            let context = ToolContext(
                                sessionID: sessionID,
                                workspacePath: workspacePath,
                                session: toolSession,
                                authorization: service.toolAuthorizationService
                            )

                            // Emit tool execution events *before* starting ToolExecutor work.
                            // Rationale: ToolResultCard UI needs "executing" state to appear live.
                            for call in accumulatedToolCalls {
                                continuation.yield(.toolExecuting(name: call.name))
                            }

                            // Streaming execution output from ToolExecutor if needed, or just await all
                            let executionStream = await executor.execute(
                                calls: accumulatedToolCalls, context: context)

                            for await callResult in executionStream {
                                let toolName = callResult.toolName
                                lastToolNameAttempted = toolName
                                let toolResultOutput = callResult.output
                                let toolCallID = callResult.id  // Correlation ID

                                logger.info(
                                    "Executed tool: \(toolName), success: \(callResult.success)"
                                )

                                // Create and save tool result message
                                let toolMeta = ToolResultMeta(
                                    toolName: toolName,
                                    success: callResult.success,
                                    truncated: callResult.result.truncated,
                                    error: callResult.success ? nil : callResult.output,
                                    metadata: callResult.result.metadata.isEmpty
                                        ? nil : callResult.result.metadata
                                )

                                let toolResultMessage = ChatMessage(
                                    id: UUID(),
                                    role: .tool,
                                    content: toolResultOutput,
                                    thoughtProcess: nil,
                                    parts: [],
                                    createdAt: Date(),
                                    codeBlocks: [],
                                    tokenUsage: nil,
                                    costBreakdown: nil,
                                    toolCallID: toolCallID,
                                    toolResultMeta: toolMeta
                                )

                                try await MainActor.run {
                                    try service.appendMessage(toolResultMessage, to: sessionID)
                                }

                            }

                            // Continue the loop to let LLM process tool results
                            continueLoop = true
                        }
                    }

                    if iterationCount >= maxIterations {
                        let lastTool = lastToolNameAttempted ?? "none"
                        logger.warning(
                            "Agent loop reached maximum iterations (limit=\(maxIterations), used=\(iterationCount), lastTool=\(lastTool))"
                        )
                        continuation.yield(
                            .agentStopped(
                                reason: .iterationLimitReached(limit: maxIterations, used: iterationCount)
                            )
                        )
                    }

                    continuation.finish()
                } catch {
                    if error is CancellationError {
                        continuation.finish()
                        return
                    }
                    logger.error("Stream completion error: \(error)")
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Rolling Summary ("Summarize Mode")

    /// Generates a rolling summary of older conversation turns for context compaction.
    ///
    /// Important: This runs in a dedicated summarize mode that MUST NOT re-enter
    /// `streamCompletion` (agent loop/tool execution). It calls the provider directly with
    /// `tools: nil` and consumes the provider's stream locally.
    @MainActor
    private func generateRollingSummary(
        provider: any LLMProvider,
        model: String,
        messagesToSummarize: [ChatMessage],
        summaryMaxTokens: Int
    ) async throws -> String {
        func format(_ messages: [ChatMessage]) -> String {
            messages.map { msg in
                let role = msg.role.rawValue.uppercased()
                // Keep each message bounded to avoid pathological prompt sizes.
                let content = String(msg.content.prefix(2_000))
                return "\(role): \(content)"
            }.joined(separator: "\n\n")
        }

        let transcript = format(messagesToSummarize)

        let instruction = """
            You are generating a rolling summary for context compaction.

            Output rules:
            - Be concise, factual, and actionable.
            - Preserve user intent, constraints, decisions, plans, and open tasks.
            - Avoid fluff and avoid quoting large blocks.
            - Do not mention tool schemas or tool manifests.
            - Hard limit: ~\(summaryMaxTokens) tokens.

            TRANSCRIPT (oldest → newest):
            \(transcript)
            """

        let system = ChatMessage(
            id: UUID(),
            role: .system,
            content: "ROLLING_SUMMARY_MODE: enabled",
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        )
        let user = ChatMessage(
            id: UUID(),
            role: .user,
            content: instruction,
            parts: [.text(instruction)],
            createdAt: Date(),
            codeBlocks: []
        )

        let options = LLMRequestOptions(thinkingPreference: .off, thinkingBudgetTokens: nil)
        let request = try await provider.buildRequest(
            messages: [system, user],
            model: model,
            tools: nil,
            options: options
        )

        var summary = ""
        for try await event in provider.streamResponse(from: request) {
            switch event {
            case .token(let text):
                summary += text
            case .completion(let message):
                if !message.content.isEmpty { summary = message.content }
                return summary
            case .truncated(let message):
                if !message.content.isEmpty { summary = message.content }
                return summary
            case .error(let err):
                throw err
            case .toolUse, .toolExecuting, .usage, .reference, .thinking, .contextCompacted, .agentStopped:
                continue
            }
        }

        return summary
    }

    // Helper to load single session
    /// Loads a specific session by ID.
    func loadSession(id: UUID) throws -> ChatSession {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == id })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }
        // Rationale: Ensure we return canonical IDs even if the DB still contains legacy values.
        let canonical =
            providerRegistry.canonicalProviderID(for: entity.providerID)
            ?? ProviderID.canonicalID(from: entity.providerID)
        if entity.providerID != canonical {
            entity.providerID = canonical
            do {
                try modelContext.save()
            } catch {
                logger.error(
                    "Failed to persist providerID migration for session \(id): \(error.localizedDescription)"
                )
            }
        }
        return entity.asDomain()
    }

    /// Updates the token usage and cost for a specific message.
    func updateMessageTokenUsage(
        messageID: UUID, tokenUsage: TokenUsage, costBreakdown: CostBreakdown
    ) throws {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatMessageEntity>(predicate: #Predicate { $0.id == messageID })
            ).first
        else {
            throw ChatServiceError.messageMissing
        }
        entity.tokenUsageInputTokens = tokenUsage.inputTokens
        entity.tokenUsageOutputTokens = tokenUsage.outputTokens
        entity.tokenUsageCachedTokens = tokenUsage.cachedTokens
        entity.costBreakdownInputCost = costBreakdown.inputCost
        entity.costBreakdownOutputCost = costBreakdown.outputCost
        entity.costBreakdownCachedCost = costBreakdown.cachedCost
        entity.costBreakdownTotalCost = costBreakdown.totalCost
        try modelContext.save()
    }

    /// Updates the session metadata (last usage, total cost).
    func updateSessionMetadata(sessionID: UUID, lastTokenUsage: TokenUsage, additionalCost: Decimal)
        throws
    {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }
        entity.lastTokenUsageInputTokens = lastTokenUsage.inputTokens
        entity.lastTokenUsageOutputTokens = lastTokenUsage.outputTokens
        entity.lastTokenUsageCachedTokens = lastTokenUsage.cachedTokens
        entity.totalCostUSD += additionalCost
        try modelContext.save()
    }

    // MARK: - Folders

    /// Loads all chat folders.
    func loadFolders() throws -> [ChatFolder] {
        let descriptor = FetchDescriptor<ChatFolderEntity>(sortBy: [SortDescriptor(\.orderIndex)])
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    /// Creates a new chat folder.
    func createFolder(name: String, icon: String, color: String) throws -> ChatFolder {
        let folder = ChatFolder(
            id: UUID(),
            name: name,
            icon: icon,
            color: color,
            orderIndex: try loadFolders().count,
            createdAt: Date(),
            updatedAt: Date()
        )
        let entity = ChatFolderEntity(folder: folder)
        modelContext.insert(entity)
        try modelContext.save()
        return folder
    }

    /// Updates an existing chat folder.
    func updateFolder(_ folder: ChatFolder) throws {
        let folderID = folder.id
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatFolderEntity>(predicate: #Predicate { $0.id == folderID })
            ).first
        else {
            throw ChatServiceError.folderMissing
        }
        entity.name = folder.name
        entity.icon = folder.icon
        entity.color = folder.color
        entity.updatedAt = Date()
        try modelContext.save()
    }

    /// Deletes a chat folder.
    func deleteFolder(id: UUID) throws {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatFolderEntity>(predicate: #Predicate { $0.id == id })
            ).first
        else {
            throw ChatServiceError.folderMissing
        }
        // Sessions in this folder will have their folder relationship set to null (nullify rule)
        modelContext.delete(entity)
        try modelContext.save()
    }

    /// Moves a session to a specific folder.
    func moveSession(_ sessionID: UUID, to folderID: UUID?) throws {
        guard
            let sessionEntity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }

        if let folderID = folderID {
            guard
                let folderEntity = try modelContext.fetch(
                    FetchDescriptor<ChatFolderEntity>(predicate: #Predicate { $0.id == folderID })
                ).first
            else {
                throw ChatServiceError.folderMissing
            }
            sessionEntity.folder = folderEntity
            sessionEntity.parentProjectID = folderID
        } else {
            sessionEntity.folder = nil
            sessionEntity.parentProjectID = nil
        }
        try modelContext.save()
    }

    // MARK: - Tags

    /// Loads all chat tags.
    func loadTags() throws -> [ChatTag] {
        let descriptor = FetchDescriptor<ChatTagEntity>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    /// Creates a new tag.
    func createTag(name: String, color: String) throws -> ChatTag {
        let tag = ChatTag(id: UUID(), name: name, color: color)
        let entity = ChatTagEntity(tag: tag)
        modelContext.insert(entity)
        try modelContext.save()
        return tag
    }

    /// Deletes a tag.
    func deleteTag(id: UUID) throws {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<ChatTagEntity>(predicate: #Predicate { $0.id == id })
            ).first
        else {
            throw ChatServiceError.tagMissing
        }
        modelContext.delete(entity)
        try modelContext.save()
    }

    /// Adds a tag to a session.
    func addTag(tagID: UUID, to sessionID: UUID) throws {
        guard
            let sessionEntity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }
        guard
            let tagEntity = try modelContext.fetch(
                FetchDescriptor<ChatTagEntity>(predicate: #Predicate { $0.id == tagID })
            ).first
        else {
            throw ChatServiceError.tagMissing
        }

        if !sessionEntity.tags.contains(where: { $0.id == tagID }) {
            sessionEntity.tags.append(tagEntity)
            try modelContext.save()
        }
    }

    /// Removes a tag from a session.
    func removeTag(tagID: UUID, from sessionID: UUID) throws {
        guard
            let sessionEntity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }
        sessionEntity.tags.removeAll(where: { $0.id == tagID })
        try modelContext.save()
    }

    // MARK: - Pinning

    /// Toggles the pinned state of a session.
    func togglePin(sessionID: UUID) throws {
        guard
            let sessionEntity = try modelContext.fetch(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
            ).first
        else {
            throw ChatServiceError.sessionMissing
        }
        sessionEntity.isPinned.toggle()
        try modelContext.save()
    }

    // MARK: - Attachment Helpers

    /// Formats non-image attachments into a request-only prompt block.
    /// This keeps the persisted chat transcript clean while still giving the model the file contents.
    private func formatAttachmentsForRequest(_ attachments: [Attachment]) -> String {
        let maxBytes = 100 * 1024

        var blocks: [String] = []

        for attachment in attachments {
            guard attachment.type != .image else { continue }

            let sizeBytes: Int = {
                let attrs = try? FileManager.default.attributesOfItem(atPath: attachment.url.path)
                if let number = attrs?[.size] as? NSNumber { return number.intValue }
                if let number = attrs?[.size] as? Int { return number }
                return attachment.previewText?.utf8.count ?? 0
            }()

            if attachment.type == .pdf {
                blocks.append(
                    "[Attachment: \(attachment.filename) (\(formatFileSize(sizeBytes))) — PDF not inlined]"
                )
                continue
            }

            guard let (text, truncated) = loadTextAttachment(attachment, maxBytes: maxBytes) else {
                blocks.append(
                    "[Attachment: \(attachment.filename) (\(formatFileSize(sizeBytes))) — could not read]"
                )
                continue
            }

            let fence = fenceLanguage(for: attachment.filename, type: attachment.type)
            let fenceLine = fence.map { "```\($0)" } ?? "```"

            var block = "[Attachment: \(attachment.filename) (\(formatFileSize(sizeBytes)))]\n"
            if truncated {
                block += "[Truncated to \(formatFileSize(maxBytes))]\n"
            }
            block += "\(fenceLine)\n\(text)\n```"
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n")
    }

    private func loadTextAttachment(_ attachment: Attachment, maxBytes: Int) -> (
        text: String, truncated: Bool
    )? {
        do {
            let data = try Data(contentsOf: attachment.url, options: .mappedIfSafe)
            let truncated = data.count > maxBytes
            let slice = data.prefix(maxBytes)
            let text = String(data: slice, encoding: .utf8) ?? ""
            return (text, truncated)
        } catch {
            return nil
        }
    }

    private func fenceLanguage(for filename: String, type: AttachmentType) -> String? {
        let ext = filename.split(separator: ".").last?.lowercased()
        switch ext {
        case "json": return "json"
        case "swift": return "swift"
        case "py": return "python"
        case "js", "ts": return "javascript"
        case "md": return "markdown"
        default:
            return type == .code ? "text" : nil
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Image Helpers

    /// Detects the image MIME type from the file's magic bytes.
    private func detectImageMimeType(from data: Data) -> String {
        guard data.count >= 12 else { return "image/jpeg" }

        let bytes = [UInt8](data.prefix(12))

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }

        // GIF: 47 49 46 38 (GIF8)
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return "image/gif"
        }

        // WebP: RIFF....WEBP (bytes 0-3: RIFF, bytes 8-11: WEBP)
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50
        {
            return "image/webp"
        }

        // TIFF: 49 49 2A 00 (little-endian) or 4D 4D 00 2A (big-endian)
        if (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00)
            || (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A)
        {
            return "image/tiff"
        }

        // BMP: 42 4D (BM)
        if bytes[0] == 0x42 && bytes[1] == 0x4D {
            return "image/bmp"
        }

        // Default fallback
        return "image/jpeg"
    }
}

/// Errors thrown by the ChatService.
enum ChatServiceError: LocalizedError {
    /// The session could not be found.
    case sessionMissing
    /// The message could not be found.
    case messageMissing
    /// The folder could not be found.
    case folderMissing
    /// The tag could not be found.
    case tagMissing

    /// A localized description of the error.
    var errorDescription: String? {
        switch self {
        case .sessionMissing:
            return "Chat session missing"
        case .messageMissing:
            return "Chat message missing"
        case .folderMissing:
            return "Folder missing"
        case .tagMissing:
            return "Tag missing"
        }
    }
}
