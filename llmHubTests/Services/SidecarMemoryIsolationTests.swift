import XCTest
import SwiftData

@testable import llmHub

final class SidecarMemoryIsolationTests: XCTestCase {

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

    @MainActor
    func testAppendMessageSkipsSidecar() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self,
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

        let reloaded = try modelContext.fetch(
            FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == session.id })
        ).first

        XCTAssertEqual(reloaded?.messages.count ?? -1, 0)
    }

    @MainActor
    func testStreamCompletionFiltersSidecarMessagesFromPrompt() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self,
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

        // Persist a session with 2 user turns (so retrieval injection doesn't run), plus a sidecar message.
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

        XCTAssertFalse(
            provider.capturedMessages.contains(where: { $0.provenance.channel == .sidecar }),
            "Sidecar messages must not be included in chat prompting"
        )
        XCTAssertFalse(
            provider.capturedMessages.contains(where: { $0.content.contains("SIDE-CAR-IN-PERSISTENCE") }),
            "Sidecar content must not leak into provider request"
        )
    }
}
