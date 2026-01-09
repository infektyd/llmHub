import XCTest
import SwiftData

@testable import llmHub

final class AgentIterationLimitTests: XCTestCase {

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

    @MainActor
    func testIterationLimitEmitsStopReason() async throws {
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
        let service = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor,
            toolAuthorizationService: nil
        )

        let session = try service.createSession(providerID: provider.id, model: "fake")

        let stream = try await service.streamCompletion(
            for: session,
            userMessage: "",
            generationID: UUID(),
            maxIterationsOverride: 1
        )

        var didStop = false
        for try await event in stream {
            if case .agentStopped(let reason) = event {
                XCTAssertEqual(reason, .iterationLimitReached(limit: 1, used: 1))
                didStop = true
            }
        }

        XCTAssertTrue(didStop)
    }

    @MainActor
    func testContinueWithMoreIterationsProceeds() async throws {
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
        let service = ChatService(
            modelContext: modelContext,
            providerRegistry: registry,
            toolRegistry: toolRegistry,
            toolExecutor: toolExecutor,
            toolAuthorizationService: nil
        )

        let session = try service.createSession(providerID: provider.id, model: "fake")

        // First run: allow 1 loop.
        let stream1 = try await service.streamCompletion(
            for: session,
            userMessage: "",
            generationID: UUID(),
            maxIterationsOverride: 1
        )
        for try await _ in stream1 { }

        // Second run: grant 2 more loops.
        let stream2 = try await service.streamCompletion(
            for: session,
            userMessage: "",
            generationID: UUID(),
            maxIterationsOverride: 2
        )
        for try await _ in stream2 { }

        // Each iteration executes exactly one noop tool call, which is persisted as a .tool message.
        let reloaded = try service.loadSession(id: session.id)
        let toolMessages = reloaded.messages.filter { $0.role == .tool }
        XCTAssertGreaterThanOrEqual(toolMessages.count, 3)
    }
}
