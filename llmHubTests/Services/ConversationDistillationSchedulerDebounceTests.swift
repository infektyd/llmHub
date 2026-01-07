import XCTest
import SwiftData

@testable import llmHub

final class ConversationDistillationSchedulerDebounceTests: XCTestCase {

    @MainActor
    private final class FakeDistillationService: ConversationDistillationServicing {
        struct Call: Sendable {
            let sessionID: UUID
            let providerID: String
            let messageCount: Int
            let lastMessage: String
        }

        private(set) var calls: [Call] = []

        func distill(
            sessionID: UUID,
            providerID: String,
            messages: [ChatMessage],
            modelContext: ModelContext
        ) async {
            calls.append(Call(
                sessionID: sessionID,
                providerID: providerID,
                messageCount: messages.count,
                lastMessage: messages.last?.content ?? ""
            ))
        }
    }

    @MainActor
    func testDebounceUsesNewestSnapshot() async throws {
        let schema = Schema([MemoryEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)

        let service = FakeDistillationService()
        let scheduler = ConversationDistillationScheduler(
            distillationService: service,
            debounceSeconds: 0.05,
            postFlightDebounceSeconds: 0.0
        )

        let sessionID = UUID()
        let providerID = "openai"

        let msgs1: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "u1", parts: [.text("u1")], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .assistant, content: "a1", parts: [.text("a1")], createdAt: Date(), codeBlocks: [])
        ]

        let msgs2: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "u1", parts: [.text("u1")], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .assistant, content: "a1", parts: [.text("a1")], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .user, content: "u2-newest", parts: [.text("u2-newest")], createdAt: Date(), codeBlocks: [])
        ]

        scheduler.scheduleDistillation(
            sessionID: sessionID,
            providerID: providerID,
            messages: msgs1,
            modelContext: modelContext,
            reason: .userArchived
        )

        scheduler.scheduleDistillation(
            sessionID: sessionID,
            providerID: providerID,
            messages: msgs2,
            modelContext: modelContext,
            reason: .userArchived
        )

        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(service.calls.count, 1)
        XCTAssertEqual(service.calls.first?.sessionID, sessionID)
        XCTAssertEqual(service.calls.first?.lastMessage, "u2-newest")
        XCTAssertEqual(service.calls.first?.messageCount, 3)
    }
}
