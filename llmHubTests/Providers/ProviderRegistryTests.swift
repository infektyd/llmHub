import XCTest

@testable import llmHub

final class ProviderRegistryTests: XCTestCase {

    @MainActor
    private struct StubProvider: LLMProvider {
        nonisolated let id: String
        nonisolated let name: String
        nonisolated let endpoint: URL = URL(string: "https://example.com")!
        nonisolated let supportsStreaming: Bool = false
        nonisolated let availableModels: [LLMModel] = []
        nonisolated var defaultHeaders: [String: String] { get async { [:] } }
        nonisolated let pricing: PricingMetadata = PricingMetadata(
            inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD"
        )
        nonisolated var isConfigured: Bool { get async { true } }

        func fetchModels() async throws -> [LLMModel] { [] }
        func buildRequest(messages: [ChatMessage], model: String) async throws -> URLRequest {
            URLRequest(url: endpoint)
        }
        func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) async throws
            -> URLRequest {
            URLRequest(url: endpoint)
        }
        func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func parseTokenUsage(from response: Data) throws -> TokenUsage? { nil }
    }

    func testPersistedOpenAIResolvesToCanonicalProvider() async throws {
        let registry = ProviderRegistry(providerBuilders: [
            { StubProvider(id: "openai", name: "OpenAI") },
            { StubProvider(id: "google", name: "Google AI (Gemini)") }
        ])

        let provider = try registry.provider(for: "OpenAI")
        let canonicalID = await MainActor.run { provider.id }
        XCTAssertEqual(canonicalID, "openai")
    }
}
