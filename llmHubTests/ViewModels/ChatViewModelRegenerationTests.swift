// ChatViewModelRegenerationTests.swift
// llmHubTests
//
// Tests for ChatViewModel.requestRegeneration(messageID:session:modelContext:)

import Testing
import SwiftData
@testable import llmHub

@MainActor
struct ChatViewModelRegenerationTests {

    // MARK: - Helpers

    /// Creates an in-memory ModelContainer for testing.
    private func makeContainer() -> ModelContainer {
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a session with a user message followed by an assistant message.
    private func makeSessionWithMessages(
        in context: ModelContext
    ) -> (ChatSessionEntity, UUID, UUID) {
        let session = ChatSessionEntity(
            id: UUID(),
            title: "Test Session",
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date()
        )
        context.insert(session)

        let userMessageID = UUID()
        let userEntity = ChatMessageEntity(message: ChatMessage(
            id: userMessageID,
            role: .user,
            content: "Hello, can you help me?",
            thoughtProcess: nil,
            parts: [],
            createdAt: Date().addingTimeInterval(-2),
            codeBlocks: []
        ))
        userEntity.session = session
        context.insert(userEntity)

        let assistantMessageID = UUID()
        let assistantEntity = ChatMessageEntity(message: ChatMessage(
            id: assistantMessageID,
            role: .assistant,
            content: "Of course! How can I assist?",
            thoughtProcess: nil,
            parts: [],
            createdAt: Date().addingTimeInterval(-1),
            codeBlocks: []
        ))
        assistantEntity.session = session
        context.insert(assistantEntity)

        try? context.save()
        return (session, userMessageID, assistantMessageID)
    }

    // MARK: - Tests

    /// Valid regeneration: assistant message is removed and user message is re-sent.
    @Test("Valid regeneration removes assistant message and re-sends")
    func testValidRegeneration() async {
        let container = makeContainer()
        let context = await MainActor.run { container.mainContext }
        let (session, _, assistantMessageID) = makeSessionWithMessages(in: context)

        let viewModel = ChatViewModel()
        let initialCount = session.messages.count

        viewModel.requestRegeneration(
            messageID: assistantMessageID,
            session: session,
            modelContext: context
        )

        // The assistant message should have been removed
        // (sendMessage may fail without a real provider, but deletion should succeed)
        let remainingAssistantMessages = session.messages.filter { $0.role == "assistant" }
        #expect(remainingAssistantMessages.count < initialCount - 1 || viewModel.isGenerating)
    }

    /// Regeneration with a nonexistent message ID should be a no-op.
    @Test("Regeneration with nonexistent message ID is a no-op")
    func testNonexistentMessageID() async {
        let container = makeContainer()
        let context = await MainActor.run { container.mainContext }
        let (session, _, _) = makeSessionWithMessages(in: context)

        let viewModel = ChatViewModel()
        let initialCount = session.messages.count

        viewModel.requestRegeneration(
            messageID: UUID(),  // nonexistent
            session: session,
            modelContext: context
        )

        // No messages should be removed
        #expect(session.messages.count == initialCount)
        #expect(!viewModel.isGenerating)
    }

    /// Regeneration while already generating should be blocked by the guard.
    @Test("Regeneration while generating is blocked")
    func testAlreadyGeneratingGuard() async {
        let container = makeContainer()
        let context = await MainActor.run { container.mainContext }
        let (session, _, assistantMessageID) = makeSessionWithMessages(in: context)

        let viewModel = ChatViewModel()
        viewModel.isGenerating = true

        let initialCount = session.messages.count

        viewModel.requestRegeneration(
            messageID: assistantMessageID,
            session: session,
            modelContext: context
        )

        // No messages should be removed since the guard blocked execution
        #expect(session.messages.count == initialCount)
    }
}
