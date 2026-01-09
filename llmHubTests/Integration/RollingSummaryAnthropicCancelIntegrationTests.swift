import Foundation
import SwiftData
import XCTest

@testable import llmHub

final class RollingSummaryAnthropicCancelIntegrationTests: XCTestCase {

    private actor Probe {
        var lastRequestBody: String?
        var didCancel: Bool = false

        func record(body: String) {
            lastRequestBody = body
        }

        func recordCancelled() {
            didCancel = true
        }
    }

    @MainActor
    private struct AnthropicStreamingTestProvider: LLMProvider {
        nonisolated let id: String = "anthropic"
        nonisolated let name: String = "Anthropic (Claude) [Test]"

        private let underlying: AnthropicProvider
        private let probe: Probe

        init(underlying: AnthropicProvider, probe: Probe) {
            self.underlying = underlying
            self.probe = probe
        }

        var endpoint: URL { underlying.endpoint }
        var supportsStreaming: Bool { true }
        var supportsToolCalling: Bool { underlying.supportsToolCalling }
        var availableModels: [LLMModel] { underlying.availableModels }
        var pricing: PricingMetadata { underlying.pricing }

        var defaultHeaders: [String: String] {
            get async { await underlying.defaultHeaders }
        }

        var isConfigured: Bool {
            get async { await underlying.isConfigured }
        }

        func fetchModels() async throws -> [LLMModel] {
            try await underlying.fetchModels()
        }

        func buildRequest(
            messages: [ChatMessage],
            model: String,
            tools: [ToolDefinition]?,
            options: LLMRequestOptions
        ) async throws -> URLRequest {
            try await underlying.buildRequest(messages: messages, model: model, tools: tools, options: options)
        }

        func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        await probe.record(body: body)

                        // Summarize-mode: respond immediately with a deterministic summary.
                        if body.contains("ROLLING_SUMMARY_MODE") {
                            let msg = ChatMessage(
                                id: UUID(),
                                role: .assistant,
                                content: "Test summary (integration).",
                                parts: [.text("Test summary (integration).")],
                                createdAt: Date(),
                                codeBlocks: []
                            )
                            continuation.yield(.completion(message: msg))
                            continuation.finish()
                            return
                        }

                        // Main stream: emit tokens until cancelled.
                        while !Task.isCancelled {
                            continuation.yield(.token(text: "a"))
                            try await Task.sleep(nanoseconds: 20_000_000)
                        }
                        continuation.finish()
                    } catch {
                        if error is CancellationError {
                            continuation.finish()
                            return
                        }
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    Task { await probe.recordCancelled() }
                    task.cancel()
                }
            }
        }

        func parseTokenUsage(from response: Data) throws -> TokenUsage? {
            try underlying.parseTokenUsage(from: response)
        }
    }

    @MainActor
    func testLongChatTriggersRollingSummaryAnthropicReceivesSystemSummaryAndStopCancelsStream() async throws {
        // In-memory SwiftData container.
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        // Build an Anthropic provider with a test key.
        let providersConfig = makeDefaultConfig()
        let keychain = KeychainStore(backend: InMemoryKeychainBacking(), accessGroups: [])
        try await keychain.updateKey("test", for: .anthropic)
        let anthropic = AnthropicProvider(keychain: keychain, config: providersConfig.anthropic)

        let probe = Probe()
        let provider: any LLMProvider = AnthropicStreamingTestProvider(underlying: anthropic, probe: probe)
        let registry = ProviderRegistry(providerBuilders: [{ provider }])

        let toolRegistry = await ToolRegistry(tools: [])
        let toolExecutor = ToolExecutor(registry: toolRegistry, environment: .current)

        // Enable rolling-summary and make it trigger quickly.
        let contextConfig = ContextConfig(
            enabled: true,
            summarizationEnabled: true,
            summarizeAtTurnCount: 2,
            preserveLastTurns: 1,
            summaryMaxTokens: 200,
            defaultMaxTokens: 120_000,
            preserveSystemPrompt: true,
            preserveRecentMessages: 2,
            providerOverrides: [:]
        )
        let contextManager = ContextManagementService(config: contextConfig)

        let chatService = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor,
            toolAuthorizationService: nil,
            contextManager: contextManager
        )

        // Persist a session with several turns.
        let session = ChatSession(
            id: UUID(),
            title: "Integration",
            providerID: "anthropic",
            model: providersConfig.anthropic.models.first?.id ?? "claude-3-5-haiku-20241022",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: "ref")
        )
        let sessionEntity = ChatSessionEntity(session: session)
        modelContext.insert(sessionEntity)

        // Add a system + 3 turns, then save.
        let system = ChatMessageEntity(message: ChatMessage(
            id: UUID(),
            role: .system,
            content: "SYSTEM BASE",
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        ))
        system.session = sessionEntity
        sessionEntity.messages.append(system)

        for i in 1...3 {
            let u = ChatMessageEntity(message: ChatMessage(
                id: UUID(),
                role: .user,
                content: "User \(i)",
                parts: [.text("User \(i)")],
                createdAt: Date(),
                codeBlocks: []
            ))
            u.session = sessionEntity
            sessionEntity.messages.append(u)

            let a = ChatMessageEntity(message: ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Assistant \(i)",
                parts: [.text("Assistant \(i)")],
                createdAt: Date(),
                codeBlocks: []
            ))
            a.session = sessionEntity
            sessionEntity.messages.append(a)
        }

        sessionEntity.updatedAt = Date()
        try modelContext.save()

        let domainSession = sessionEntity.asDomain()

        let stream = try await chatService.streamCompletion(
            for: domainSession,
            userMessage: "User 3",
            attachments: [],
            references: [],
            images: []
        )

        // Consume briefly then cancel (simulates "Stop").
        let consumeTask = Task {
            for try await _ in stream {
                // no-op
            }
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        consumeTask.cancel()

        // Wait a beat for cancellation propagation.
        try await Task.sleep(nanoseconds: 80_000_000)

        // Verify: provider request included rolling summary in Anthropic `system` field.
        let body = await probe.lastRequestBody
        XCTAssertNotNil(body)
        let bodyStr = body ?? ""
        XCTAssertTrue(bodyStr.contains("\"system\""))
        XCTAssertTrue(bodyStr.contains("<rolling_summary>"))
        XCTAssertTrue(bodyStr.contains("Test summary (integration)."))

        // Verify: stream cancellation propagated to provider.
        XCTAssertTrue(await probe.didCancel)
    }
}
