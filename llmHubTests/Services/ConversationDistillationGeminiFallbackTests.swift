import XCTest
import SwiftData

@testable import llmHub

final class ConversationDistillationGeminiFallbackTests: XCTestCase {

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

    @MainActor
    func testAFMUnavailableTriggersGeminiFallbackPersistsSidecarMemoryButIsNotPromptInjectable() async throws {
        let schema = Schema([MemoryEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let sessionID = UUID()

        let called = XCTestExpectation(description: "Gemini fallback invoked")

        let geminiJSON: @Sendable (String, String, Double) async throws -> String = { prompt, model, temperature in
            called.fulfill()
            XCTAssertEqual(model, GeminiPinnedModels.afmFallbackFlash)
            XCTAssertEqual(temperature, GeminiPinnedModels.afmFallbackTemperature)
            XCTAssertTrue(prompt.contains("Distill this conversation"))

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
            ),
        ]

        await service.distill(
            sessionID: sessionID,
            providerID: "openai",
            messages: messages,
            modelContext: modelContext
        )

        await fulfillment(of: [called], timeout: 2.0)

        let fetched = try modelContext.fetch(
            FetchDescriptor<MemoryEntity>(predicate: #Predicate { $0.sourceSessionID == sessionID })
        )

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.provenanceChannelRaw, "sidecar")

        // Sidecar memories must never be eligible for retrieval/prompt injection.
        let retrieval = MemoryRetrievalService()
        let hits = await retrieval.retrieveRelevant(
            for: "swift",
            providerID: nil,
            modelContext: modelContext
        )
        XCTAssertTrue(hits.isEmpty)
    }
}
