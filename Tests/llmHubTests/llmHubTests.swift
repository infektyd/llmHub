//
//  llmHubTests.swift
//  llmHubTests
//
//  Created by Hans Axelsson on 11/27/25.
//

import Testing
import SwiftData
import Foundation

@testable import llmHub

struct llmHubTests {

    private struct NoopTool: Tool {
        let name: String = "noop"
        let description: String = "No-op tool used for tests"

        var parameters: ToolParametersSchema {
            ToolParametersSchema(properties: [:], required: [])
        }

        let permissionLevel: ToolPermissionLevel = .sensitive
        let requiredCapabilities: [ToolCapability] = []
        let weight: ToolWeight = .fast
        let isCacheable: Bool = false

        func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
            ToolResult.success("ok")
        }
    }

    private final class LoopingToolUseProvider: LLMProvider {
        let id: String
        let name: String
        let endpoint: URL = URL(string: "https://example.invalid")!

        let supportsStreaming: Bool = true
        let supportsToolCalling: Bool = true
        let availableModels: [LLMModel] = [LLMModel(id: "fake", name: "fake", maxOutputTokens: 1024)]

        init(id: String = "mock", name: String = "Mock") {
            self.id = id
            self.name = name
        }

        var defaultHeaders: [String: String] { get async { [:] } }
        var pricing: PricingMetadata { PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD") }
        var isConfigured: Bool { get async { true } }

        func fetchModels() async throws -> [LLMModel] { availableModels }

        func buildRequest(
            messages: [ChatMessage],
            model: String,
            tools: [ToolDefinition]?,
            options: LLMRequestOptions
        ) async throws -> URLRequest {
            URLRequest(url: endpoint)
        }

        func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
            AsyncThrowingStream { continuation in
                let toolCallID = UUID().uuidString
                continuation.yield(.toolUse(id: toolCallID, name: "noop", input: "{}"))

                let assistant = ChatMessage(
                    id: UUID(),
                    generationID: nil,
                    role: .assistant,
                    content: "",
                    thoughtProcess: nil,
                    parts: [],
                    attachments: [],
                    createdAt: Date(),
                    codeBlocks: [],
                    tokenUsage: nil,
                    costBreakdown: nil,
                    provenance: .chat,
                    toolCallID: nil,
                    toolCalls: nil,
                    toolResultMeta: nil
                )
                continuation.yield(.completion(message: assistant))
                continuation.finish()
            }
        }

        func parseTokenUsage(from response: Data) throws -> TokenUsage? { nil }
    }

    private final class CapturingProvider: LLMProvider {
        let id: String
        let name: String
        let endpoint: URL = URL(string: "https://example.invalid")!
        let supportsStreaming: Bool = true
        let supportsToolCalling: Bool = false
        let availableModels: [LLMModel] = [LLMModel(id: "fake", name: "fake", maxOutputTokens: 1024)]

        private(set) var capturedMessages: [ChatMessage] = []

        init(id: String = "fake", name: String = "Fake") {
            self.id = id
            self.name = name
        }

        var defaultHeaders: [String: String] { get async { [:] } }
        var pricing: PricingMetadata { PricingMetadata(inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD") }
        var isConfigured: Bool { get async { true } }

        func fetchModels() async throws -> [LLMModel] { availableModels }

        func buildRequest(
            messages: [ChatMessage],
            model: String,
            tools: [ToolDefinition]?,
            options: LLMRequestOptions
        ) async throws -> URLRequest {
            capturedMessages = messages
            return URLRequest(url: endpoint)
        }

        func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
            AsyncThrowingStream { continuation in
                let msg = ChatMessage(
                    id: UUID(),
                    generationID: nil,
                    role: .assistant,
                    content: "ok",
                    thoughtProcess: nil,
                    parts: [.text("ok")],
                    attachments: [],
                    createdAt: Date(),
                    codeBlocks: [],
                    tokenUsage: nil,
                    costBreakdown: nil,
                    provenance: .chat,
                    toolCallID: nil,
                    toolCalls: nil,
                    toolResultMeta: nil
                )
                continuation.yield(.completion(message: msg))
                continuation.finish()
            }
        }

        func parseTokenUsage(from response: Data) throws -> TokenUsage? { nil }
    }

    private struct TestKeyProvider: APIKeyProviding {
        let key: String
        func apiKey(for provider: KeychainStore.ProviderKey) async -> String? {
            switch provider {
            case .google:
                return key
            default:
                return nil
            }
        }
    }

    private actor GeminiCallRecorder {
        var called: Bool = false
        var observedModel: String?

        func record(model: String) {
            called = true
            observedModel = model
        }

        func snapshot() -> (called: Bool, observedModel: String?) {
            (called, observedModel)
        }
    }

    @Test @MainActor
    func agentIterationLimitEmitsStopReason() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let provider = LoopingToolUseProvider()
        let registry = ProviderRegistry(providerBuilders: [{ provider }])
        let toolRegistry = await ToolRegistry(tools: [NoopTool()])
        let toolExecutor = ToolExecutor(registry: toolRegistry, environment: .current)
        let chatService = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor,
            toolAuthorizationService: nil
        )

        let session = try chatService.createSession(providerID: provider.id, model: "fake")

        let stream = try await chatService.streamCompletion(
            for: session,
            userMessage: "",
            generationID: UUID(),
            maxIterationsOverride: 1
        )

        var stopReason: AgentStopReason?
        for try await event in stream {
            if case .agentStopped(let reason) = event {
                stopReason = reason
            }
        }

        #expect(stopReason == .iterationLimitReached(limit: 1, used: 1))
    }

    @Test @MainActor
    func agentIterationLimitContinueAllowsAdditionalToolSteps() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let provider = LoopingToolUseProvider()
        let registry = ProviderRegistry(providerBuilders: [{ provider }])
        let toolRegistry = await ToolRegistry(tools: [NoopTool()])
        let toolExecutor = ToolExecutor(registry: toolRegistry, environment: .current)
        let chatService = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor,
            toolAuthorizationService: nil
        )

        let session = try chatService.createSession(providerID: provider.id, model: "fake")

        let stream1 = try await chatService.streamCompletion(
            for: session,
            userMessage: "",
            generationID: UUID(),
            maxIterationsOverride: 1
        )
        for try await _ in stream1 { }

        let stream2 = try await chatService.streamCompletion(
            for: session,
            userMessage: "",
            generationID: UUID(),
            maxIterationsOverride: 2
        )
        for try await _ in stream2 { }

        let reloaded = try chatService.loadSession(id: session.id)
        let toolMessages = reloaded.messages.filter { $0.role == .tool }
        #expect(toolMessages.count >= 3)
    }

    @Test
    @MainActor
    func contextMenuClickedInsideSelectionTargetsSelection() {
        let a = UUID()
        let b = UUID()
        let selection: Set<UUID> = [a, b]

        let targets = ConversationContextMenuTargetResolver.targetIDs(
            clickedID: a,
            selectedIDs: selection
        )

        #expect(targets == selection)
    }

    @Test
    @MainActor
    func contextMenuClickedOutsideSelectionTargetsOnlyClicked() {
        let a = UUID()
        let b = UUID()
        let clicked = UUID()
        let selection: Set<UUID> = [a, b]

        let targets = ConversationContextMenuTargetResolver.targetIDs(
            clickedID: clicked,
            selectedIDs: selection
        )

        #expect(targets == [clicked])
    }

    @Test
    @MainActor
    func contextMenuNoSelectionTargetsClicked() {
        let clicked = UUID()

        let targets = ConversationContextMenuTargetResolver.targetIDs(
            clickedID: clicked,
            selectedIDs: []
        )

        #expect(targets == [clicked])
    }

    @Test @MainActor
    func sidecarAppendMessageIsNotPersisted() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let provider = CapturingProvider()
        let registry = ProviderRegistry(providerBuilders: [{ provider }])
        let toolRegistry = await ToolRegistry(tools: [])
        let toolExecutor = ToolExecutor(registry: toolRegistry, environment: .current)

        let chatService = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor
        )

        let session = ChatSession(
            id: UUID(),
            title: "T",
            providerID: provider.id,
            model: "fake",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref")
        )
        let entity = ChatSessionEntity(session: session)
        modelContext.insert(entity)
        try modelContext.save()

        let sidecarMsg = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "SIDE-CAR",
            thoughtProcess: nil,
            parts: [.text("SIDE-CAR")],
            createdAt: Date(),
            codeBlocks: [],
            provenance: .sidecar(model: "gemini-2.0-flash-001")
        )

        try chatService.appendMessage(sidecarMsg, to: session.id)

        let reloaded = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>()).first(where: { $0.id == session.id })

        #expect((reloaded?.messages.count ?? -1) == 0)
    }

    @Test @MainActor
    func sidecarMessagesAreFilteredFromPrompting() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let provider = CapturingProvider()
        let registry = ProviderRegistry(providerBuilders: [{ provider }])
        let toolRegistry = await ToolRegistry(tools: [])
        let toolExecutor = ToolExecutor(registry: toolRegistry, environment: .current)

        let chatService = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor
        )

        let session = ChatSession(
            id: UUID(),
            title: "T",
            providerID: provider.id,
            model: "fake",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref")
        )
        let sessionEntity = ChatSessionEntity(session: session)
        modelContext.insert(sessionEntity)

        let system = ChatMessageEntity(message: ChatMessage(
            id: UUID(),
            role: .system,
            content: "SYSTEM",
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        ))
        system.session = sessionEntity
        sessionEntity.messages.append(system)

        let user1 = ChatMessageEntity(message: ChatMessage(
            id: UUID(),
            role: .user,
            content: "u1",
            parts: [.text("u1")],
            createdAt: Date(),
            codeBlocks: []
        ))
        user1.session = sessionEntity
        sessionEntity.messages.append(user1)

        let assistant1 = ChatMessageEntity(message: ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "a1",
            parts: [.text("a1")],
            createdAt: Date(),
            codeBlocks: []
        ))
        assistant1.session = sessionEntity
        sessionEntity.messages.append(assistant1)

        let user2 = ChatMessageEntity(message: ChatMessage(
            id: UUID(),
            role: .user,
            content: "u2",
            parts: [.text("u2")],
            createdAt: Date(),
            codeBlocks: []
        ))
        user2.session = sessionEntity
        sessionEntity.messages.append(user2)

        // Bypass ChatService.appendMessage guard by inserting directly.
        let sidecar = ChatMessageEntity(message: ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "SIDE-CAR-IN-PERSISTENCE",
            parts: [.text("SIDE-CAR-IN-PERSISTENCE")],
            createdAt: Date(),
            codeBlocks: [],
            provenance: .sidecar(model: "gemini-2.0-flash-001")
        ))
        sidecar.session = sessionEntity
        sessionEntity.messages.append(sidecar)

        try modelContext.save()

        let domainSession = try chatService.loadSession(id: session.id)

        let stream = try await chatService.streamCompletion(
            for: domainSession,
            userMessage: "u2",
            attachments: [],
            references: [],
            images: [],
            generationID: UUID()
        )

        for try await event in stream {
            if case .completion = event { break }
        }

        #expect(!provider.capturedMessages.contains(where: { $0.provenance.channel == .sidecar }))
        #expect(!provider.capturedMessages.contains(where: { $0.content.contains("SIDE-CAR-IN-PERSISTENCE") }))
    }

    @Test @MainActor
    func geminiFallbackDistillationDoesNotPersistMemory() async throws {
        let schema = Schema([MemoryEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let sessionID = UUID()
        let recorder = GeminiCallRecorder()

        let geminiJSON: @Sendable (String, String, Double) async throws -> String = { prompt, model, _ in
            await recorder.record(model: model)
            #expect(prompt.contains("Distill this conversation"))

            return """
            {
              "summary": "A short summary.",
              "userFacts": [{"statement": "User likes Swift", "category": "preference"}],
              "preferences": [{"topic": "language", "value": "Swift"}],
              "decisions": [{"decision": "Use SwiftData", "context": "Persistence"}],
              "artifacts": [{"type": "code", "description": "Snippet", "language": "swift"}],
              "keywords": ["swift", "swiftdata", "llmhub"]
            }
            """
        }

        let service = ConversationDistillationService(
            keyProvider: TestKeyProvider(key: "test"),
            geminiJSONGenerator: geminiJSON,
            afmAvailabilityOverride: { false }
        )

        let messages: [ChatMessage] = [
            ChatMessage(
                id: UUID(), role: .user, content: "Hi", thoughtProcess: nil,
                parts: [.text("Hi")], createdAt: Date(), codeBlocks: []
            ),
            ChatMessage(
                id: UUID(), role: .assistant, content: "Hello", thoughtProcess: nil,
                parts: [.text("Hello")], createdAt: Date(), codeBlocks: []
            ),
            ChatMessage(
                id: UUID(), role: .user, content: "Please remember I like Swift", thoughtProcess: nil,
                parts: [.text("Please remember I like Swift")], createdAt: Date(), codeBlocks: []
            )
        ]

        await service.distill(
            sessionID: sessionID,
            providerID: "openai",
            messages: messages,
            modelContext: modelContext
        )

        let snapshot = await recorder.snapshot()
        #expect(snapshot.called)
        #expect(snapshot.observedModel == GeminiPinnedModels.afmFallbackFlash)

        let fetchedAll = try modelContext.fetch(FetchDescriptor<MemoryEntity>())
        let fetchedForSession = fetchedAll.filter { $0.sourceSessionID == sessionID }
        #expect(fetchedForSession.count == 1)
        #expect(fetchedForSession.first?.provenanceChannelRaw == "sidecar")

        let retrieval = MemoryRetrievalService()
        let hits = await retrieval.retrieveRelevant(
            for: "swift",
            providerID: nil,
            modelContext: modelContext
        )
        #expect(hits.isEmpty)
    }

    // MARK: - Session deletion vs distillation

    @MainActor
    private final class FakeDistillationScheduler: ConversationDistillationScheduling {
        struct ScheduleCall: Equatable {
            let sessionID: UUID
            let reason: SessionEndReason
        }

        private(set) var scheduleCalls: [ScheduleCall] = []
        private(set) var cancelledSessionIDs: [UUID] = []

        func scheduleDistillation(
            sessionID: UUID,
            providerID: String,
            messages: [ChatMessage],
            modelContext: ModelContext,
            reason: SessionEndReason
        ) {
            scheduleCalls.append(ScheduleCall(sessionID: sessionID, reason: reason))
        }

        func cancelDistillation(sessionID: UUID) {
            cancelledSessionIDs.append(sessionID)
        }

        func cancelDistillation(sessionIDs: [UUID]) {
            cancelledSessionIDs.append(contentsOf: sessionIDs)
        }
    }

    @Test @MainActor
    func deletingASessionDoesNotScheduleDistillation() throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let session = ChatSession(
            id: UUID(),
            title: "T",
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref")
        )
        let entity = ChatSessionEntity(session: session)
        modelContext.insert(entity)
        try modelContext.save()

        let fake = FakeDistillationScheduler()
        let lifecycle = ConversationLifecycleService(distillationScheduler: fake)

        lifecycle.delete(session: entity, modelContext: modelContext)

        #expect(fake.scheduleCalls.isEmpty)
        #expect(fake.cancelledSessionIDs.contains(entity.id))
    }

    @Test @MainActor
    func bulkDeleteDoesNotScheduleDistillationForAnyDeletedSession() throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let s1 = ChatSession(
            id: UUID(),
            title: "S1",
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref1")
        )
        let s2 = ChatSession(
            id: UUID(),
            title: "S2",
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref2")
        )

        let e1 = ChatSessionEntity(session: s1)
        let e2 = ChatSessionEntity(session: s2)
        modelContext.insert(e1)
        modelContext.insert(e2)
        try modelContext.save()

        let fake = FakeDistillationScheduler()
        let lifecycle = ConversationLifecycleService(distillationScheduler: fake)

        lifecycle.deleteAll([e1, e2], modelContext: modelContext)

        #expect(fake.scheduleCalls.isEmpty)
        #expect(fake.cancelledSessionIDs.contains(e1.id))
        #expect(fake.cancelledSessionIDs.contains(e2.id))
    }

    @Test @MainActor
    func archivingSchedulesDistillation() throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let messages: [ChatMessage] = [
            ChatMessage(
                id: UUID(), role: .user, content: "u1", thoughtProcess: nil,
                parts: [.text("u1")], createdAt: Date(), codeBlocks: []
            ),
            ChatMessage(
                id: UUID(), role: .assistant, content: "a1", thoughtProcess: nil,
                parts: [.text("a1")], createdAt: Date(), codeBlocks: []
            ),
            ChatMessage(
                id: UUID(), role: .user, content: "u2", thoughtProcess: nil,
                parts: [.text("u2")], createdAt: Date(), codeBlocks: []
            )
        ]

        let session = ChatSession(
            id: UUID(),
            title: "T",
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date(),
            messages: messages,
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref")
        )
        let entity = ChatSessionEntity(session: session)
        modelContext.insert(entity)
        try modelContext.save()

        let fake = FakeDistillationScheduler()
        let lifecycle = ConversationLifecycleService(distillationScheduler: fake)

        lifecycle.archive(session: entity, modelContext: modelContext)

        #expect(fake.scheduleCalls.count == 1)
        #expect(fake.scheduleCalls.first?.sessionID == entity.id)
        #expect(fake.scheduleCalls.first?.reason == .userArchived)
    }
}
