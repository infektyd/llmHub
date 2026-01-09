import XCTest

@testable import llmHub

@MainActor
final class RollingSummaryCompactionTests: XCTestCase {

    func testSummarizeOldestInsertsRollingSummaryIntoFirstSystemAndPreservesLastTurns() async throws {
        let compactor = ContextCompactor()

        var messages: [ChatMessage] = [
            ChatMessage(
                id: UUID(),
                role: .system,
                content: "SYSTEM: base prompt",
                parts: [],
                createdAt: Date(),
                codeBlocks: []
            )
        ]

        // 3 user turns.
        for turn in 1...3 {
            messages.append(
                ChatMessage(
                    id: UUID(),
                    role: .user,
                    content: "User \(turn)",
                    parts: [.text("User \(turn)")],
                    createdAt: Date(),
                    codeBlocks: []
                )
            )
            messages.append(
                ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "Assistant \(turn)",
                    parts: [.text("Assistant \(turn)")],
                    createdAt: Date(),
                    codeBlocks: []
                )
            )
        }

        let config = ContextCompactor.CompactionConfig(
            maxTokens: 999_999,
            preserveSystemPrompt: true,
            preserveRecentMessages: 0,
            summarizationEnabled: true,
            summarizeAtTurnCount: 2,
            preserveLastTurns: 1,
            summaryMaxTokens: 200
        )

        let result = try await compactor.compact(
            messages: messages,
            config: config,
            strategy: .summarizeOldest,
            rollingSummaryGenerator: { _, _ in
                "Summary of older turns."
            }
        )

        XCTAssertTrue(result.summaryGenerated)
        XCTAssertEqual(result.compactedMessages.first?.role, .system)
        XCTAssertTrue(result.compactedMessages.first?.content.contains("<rolling_summary>") == true)
        XCTAssertTrue(
            result.compactedMessages.first?.content.contains("Summary of older turns.") == true
        )

        // Preserve last 1 turn: should still include "User 3" + "Assistant 3".
        let contents = result.compactedMessages.map(\.content)
        XCTAssertTrue(contents.contains("User 3"))
        XCTAssertTrue(contents.contains("Assistant 3"))

        // Earlier turns should be removed from the message list (they live in the summary now).
        XCTAssertFalse(contents.contains("User 1"))
        XCTAssertFalse(contents.contains("Assistant 1"))
        XCTAssertFalse(contents.contains("User 2"))
        XCTAssertFalse(contents.contains("Assistant 2"))
    }

    func testSummarizeOldestFallsBackToTruncationIfSummarizerThrows() async throws {
        let compactor = ContextCompactor()

        // Make the transcript huge so truncation must happen if summarization fails.
        let huge = String(repeating: "x", count: 20_000)
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .system, content: "SYSTEM", parts: [], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .user, content: huge, parts: [.text(huge)], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .assistant, content: huge, parts: [.text(huge)], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .user, content: huge, parts: [.text(huge)], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .assistant, content: huge, parts: [.text(huge)], createdAt: Date(), codeBlocks: [])
        ]

        let config = ContextCompactor.CompactionConfig(
            maxTokens: 500, // force compaction
            preserveSystemPrompt: true,
            preserveRecentMessages: 1,
            summarizationEnabled: true,
            summarizeAtTurnCount: 1,
            preserveLastTurns: 1,
            summaryMaxTokens: 50
        )

        struct TestError: Error {}

        let result = try await compactor.compact(
            messages: messages,
            config: config,
            strategy: .summarizeOldest,
            rollingSummaryGenerator: { _, _ in
                throw TestError()
            }
        )

        XCTAssertFalse(result.summaryGenerated)
        XCTAssertGreaterThan(result.droppedCount, 0)
        XCTAssertLessThanOrEqual(result.finalTokens, config.maxTokens)
    }

    func testSummarizeOldestFallsBackToTruncationIfSummaryStillTooLarge() async throws {
        let compactor = ContextCompactor()

        let huge = String(repeating: "x", count: 40_000)
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .system, content: "SYSTEM", parts: [], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .user, content: "u1", parts: [.text("u1")], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .assistant, content: "a1", parts: [.text("a1")], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .user, content: "u2", parts: [.text("u2")], createdAt: Date(), codeBlocks: []),
            ChatMessage(id: UUID(), role: .assistant, content: "a2", parts: [.text("a2")], createdAt: Date(), codeBlocks: [])
        ]

        let config = ContextCompactor.CompactionConfig(
            maxTokens: 300, // keep tight so summary won't fit
            preserveSystemPrompt: true,
            preserveRecentMessages: 1,
            summarizationEnabled: true,
            summarizeAtTurnCount: 1,
            preserveLastTurns: 1,
            summaryMaxTokens: 10_000
        )

        let result = try await compactor.compact(
            messages: messages,
            config: config,
            strategy: .summarizeOldest,
            rollingSummaryGenerator: { _, _ in
                // Intentionally too large so we must fall back to truncation.
                huge
            }
        )

        XCTAssertTrue(result.summaryGenerated)
        XCTAssertLessThanOrEqual(result.finalTokens, config.maxTokens)
        XCTAssertEqual(result.compactedMessages.first?.role, .system)
    }
}
