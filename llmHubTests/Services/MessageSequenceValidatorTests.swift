//
//  MessageSequenceValidatorTests.swift
//  llmHubTests
//
//  Unit tests for MessageSequenceValidator focusing on measurability and determinism.
//  Tests cover all acceptance criteria: mutation tracking, drop reasons, and edge cases.
//

import XCTest

@testable import llmHub

final class MessageSequenceValidatorTests: XCTestCase {

    // MARK: - Test Helpers

    /// Creates a test user message.
    private func userMessage(content: String = "test user") -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .user,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        )
    }

    /// Creates a test assistant message with optional tool calls.
    private func assistantMessage(
        content: String = "test assistant",
        toolCalls: [ToolCall]? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .assistant,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: [],
            toolCallID: nil,
            toolCalls: toolCalls
        )
    }

    /// Creates a test tool response message.
    private func toolMessage(
        content: String = "test tool result",
        toolCallID: String
    ) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .tool,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: [],
            toolCallID: toolCallID,
            toolCalls: nil
        )
    }

    /// Creates a test system message.
    private func systemMessage(content: String = "test system") -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .system,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        )
    }

    // MARK: - Valid Sequence Tests

    func testValidSequence_AssistantWithToolCallsFollowedByTool() throws {
        // Given: assistant(with toolCalls) → tool → assistant (valid sequence)
        let toolCall = ToolCall(id: "call_123", name: "read_file", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Read the file"),
            assistantMessage(content: "", toolCalls: [toolCall]),
            toolMessage(content: "File contents", toolCallID: "call_123"),
            assistantMessage(content: "Done"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: No mutations should occur
        XCTAssertFalse(result.didMutate, "Valid sequence should not be mutated")
        XCTAssertEqual(result.droppedMessageCount, 0, "No messages should be dropped")
        XCTAssertEqual(result.droppedUserCount, 0)
        XCTAssertEqual(result.droppedAssistantCount, 0)
        XCTAssertEqual(result.droppedToolCount, 0)
        XCTAssertEqual(result.droppedSystemCount, 0)
        XCTAssertTrue(result.droppedByReason.isEmpty, "No drop reasons for valid sequence")
        XCTAssertEqual(result.sanitizedMessages.count, messages.count)

        // Verify sequences match
        XCTAssertEqual(result.preRoleSequence.count, 4)
        XCTAssertEqual(result.postRoleSequence.count, 4)
        XCTAssertEqual(result.preRoleSequence, result.postRoleSequence)
    }

    func testValidSequence_MultipleToolCalls() throws {
        // Given: assistant with multiple tool calls followed by multiple tool responses
        let toolCall1 = ToolCall(id: "call_1", name: "read_file", input: "{}")
        let toolCall2 = ToolCall(id: "call_2", name: "write_file", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Process files"),
            assistantMessage(content: "", toolCalls: [toolCall1, toolCall2]),
            toolMessage(content: "File 1 result", toolCallID: "call_1"),
            toolMessage(content: "File 2 result", toolCallID: "call_2"),
            assistantMessage(content: "Done"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(result.droppedMessageCount, 0)
        XCTAssertEqual(result.sanitizedMessages.count, messages.count)
    }

    // MARK: - Invalid Sequence Tests

    func testInvalidSequence_AssistantWithToolCallsFollowedByUserThenTool() throws {
        // Given: assistant(with toolCalls) → user → tool (invalid; user interrupts tool sequence)
        let toolCall = ToolCall(id: "call_123", name: "read_file", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Read the file"),
            assistantMessage(content: "", toolCalls: [toolCall]),
            userMessage(content: "Wait, cancel that"),  // User interrupts
            toolMessage(content: "File contents", toolCallID: "call_123"),  // Tool result orphaned
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: Tool message should be kept (it still has valid origin)
        // The current implementation doesn't drop based on user interruption,
        // only on missing origin or duplicate. This is PASS-THROUGH behavior.
        XCTAssertFalse(result.didMutate, "Current implementation allows tool after user")
        XCTAssertEqual(result.sanitizedMessages.count, messages.count)
    }

    func testOrphanTool_NoMatchingAssistantToolCall() throws {
        // Given: tool message without prior assistant toolCall
        let messages: [ChatMessage] = [
            userMessage(content: "Hello"),
            toolMessage(content: "Orphaned tool result", toolCallID: "call_orphan"),
            assistantMessage(content: "Response"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: Tool message should be dropped
        XCTAssertTrue(result.didMutate, "Orphan tool should trigger mutation")
        XCTAssertEqual(result.droppedMessageCount, 1)
        XCTAssertEqual(result.droppedToolCount, 1)
        XCTAssertEqual(result.droppedByReason["orphanTool"], 1)
        XCTAssertEqual(result.sanitizedMessages.count, 2)  // Only user and assistant remain

        // Verify role sequences
        XCTAssertEqual(result.preRoleSequence.count, 3)
        XCTAssertEqual(result.postRoleSequence.count, 2)
        XCTAssertEqual(result.preRoleSequence[0], "user")
        XCTAssertTrue(result.preRoleSequence[1].starts(with: "tool"))
        XCTAssertEqual(result.postRoleSequence[0], "user")
        XCTAssertEqual(result.postRoleSequence[1], "assistant")
    }

    func testDuplicateTool_SameToolCallID() throws {
        // Given: duplicate tool messages with same toolCallID
        let toolCall = ToolCall(id: "call_123", name: "read_file", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Read file"),
            assistantMessage(content: "", toolCalls: [toolCall]),
            toolMessage(content: "First result", toolCallID: "call_123"),
            toolMessage(content: "Duplicate result", toolCallID: "call_123"),  // Duplicate
            assistantMessage(content: "Done"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: Second tool message should be dropped
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.droppedMessageCount, 1)
        XCTAssertEqual(result.droppedToolCount, 1)
        XCTAssertEqual(result.droppedByReason["duplicateTool"], 1)
        XCTAssertEqual(result.sanitizedMessages.count, 4)

        // Verify the first tool result was kept, second dropped
        let sanitizedRoles = result.sanitizedMessages.map { $0.role }
        XCTAssertEqual(sanitizedRoles, [.user, .assistant, .tool, .assistant])
    }

    func testTrailingEmptyAssistant() throws {
        // Given: trailing empty assistant placeholder
        let messages: [ChatMessage] = [
            userMessage(content: "Hello"),
            assistantMessage(content: "Response"),
            assistantMessage(content: "   \n\t  ", toolCalls: nil),  // Trailing empty
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: Empty trailing assistant should be dropped
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.droppedMessageCount, 1)
        XCTAssertEqual(result.droppedAssistantCount, 1)
        XCTAssertEqual(result.droppedByReason["trailingEmptyAssistant"], 1)
        XCTAssertEqual(result.sanitizedMessages.count, 2)
    }

    func testToolMissingID() throws {
        // Given: tool message without toolCallID
        var toolMsgWithoutID = toolMessage(content: "Result", toolCallID: "dummy")
        toolMsgWithoutID.toolCallID = nil  // Remove the ID

        let messages: [ChatMessage] = [
            userMessage(content: "Hello"),
            toolMsgWithoutID,
            assistantMessage(content: "Response"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.droppedMessageCount, 1)
        XCTAssertEqual(result.droppedToolCount, 1)
        XCTAssertEqual(result.droppedByReason["toolMissingID"], 1)
    }

    func testToolOriginDropped() throws {
        // Given: tool message whose parent assistant was dropped (trailing empty)
        let toolCall = ToolCall(id: "call_123", name: "read_file", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Read file"),
            assistantMessage(content: "  ", toolCalls: [toolCall]),  // Trailing empty with toolCalls - won't be dropped
            toolMessage(content: "Result", toolCallID: "call_123"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: The assistant has toolCalls so it won't be dropped as trailing empty
        XCTAssertFalse(
            result.didMutate, "Assistant with toolCalls should not be dropped even if empty")
        XCTAssertEqual(result.sanitizedMessages.count, 3)
    }

    // MARK: - Multiple Drop Reasons Test

    func testMultipleDropReasons() throws {
        // Given: multiple drop scenarios in one sequence
        let toolCall = ToolCall(id: "call_valid", name: "read_file", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Start"),
            assistantMessage(content: "", toolCalls: [toolCall]),
            toolMessage(content: "Valid result", toolCallID: "call_valid"),
            toolMessage(content: "Orphan", toolCallID: "call_orphan"),  // Orphan
            toolMessage(content: "Duplicate", toolCallID: "call_valid"),  // Duplicate
            assistantMessage(content: "   "),  // Trailing empty
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.droppedMessageCount, 3)
        XCTAssertEqual(result.droppedToolCount, 2)
        XCTAssertEqual(result.droppedAssistantCount, 1)
        XCTAssertEqual(result.droppedByReason["orphanTool"], 1)
        XCTAssertEqual(result.droppedByReason["duplicateTool"], 1)
        XCTAssertEqual(result.droppedByReason["trailingEmptyAssistant"], 1)
        XCTAssertEqual(result.sanitizedMessages.count, 3)
    }

    // MARK: - Role Sequence Tracking Tests

    func testRoleSequenceTracking() throws {
        // Given: sequence with tool calls
        let toolCall = ToolCall(id: "call_abc", name: "test_tool", input: "{}")

        let messages: [ChatMessage] = [
            systemMessage(content: "System prompt"),
            userMessage(content: "User query"),
            assistantMessage(content: "", toolCalls: [toolCall]),
            toolMessage(content: "Tool result", toolCallID: "call_abc"),
            assistantMessage(content: "Final response"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: Verify role sequence annotations
        XCTAssertEqual(result.preRoleSequence.count, 5)
        XCTAssertEqual(result.postRoleSequence.count, 5)

        XCTAssertEqual(result.preRoleSequence[0], "system")
        XCTAssertEqual(result.preRoleSequence[1], "user")
        XCTAssertTrue(
            result.preRoleSequence[2].contains("[+1tc]"), "Assistant should show tool call count")
        XCTAssertTrue(
            result.preRoleSequence[3].contains("[→call_abc]"), "Tool should show shortened call ID")
        XCTAssertEqual(result.preRoleSequence[4], "assistant")
    }

    // MARK: - Determinism Tests

    func testDeterministicBehavior_SameInputProducesSameOutput() throws {
        // Given: same input sequence
        let toolCall = ToolCall(id: "call_deterministic", name: "test", input: "{}")

        let messages: [ChatMessage] = [
            userMessage(content: "Query"),
            assistantMessage(content: "", toolCalls: [toolCall]),
            toolMessage(content: "Orphan", toolCallID: "call_orphan"),
            toolMessage(content: "Valid", toolCallID: "call_deterministic"),
        ]

        // When: Run sanitization multiple times
        let result1 = MessageSequenceValidator.sanitize(messages: messages, provider: "Test")
        let result2 = MessageSequenceValidator.sanitize(messages: messages, provider: "Test")

        // Then: Results should be identical
        XCTAssertEqual(result1.didMutate, result2.didMutate)
        XCTAssertEqual(result1.droppedMessageCount, result2.droppedMessageCount)
        XCTAssertEqual(result1.droppedByReason, result2.droppedByReason)
        XCTAssertEqual(result1.sanitizedMessages.count, result2.sanitizedMessages.count)
    }

    // MARK: - Empty Sequence Tests

    func testEmptySequence() throws {
        // Given: empty message array
        let messages: [ChatMessage] = []

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(result.droppedMessageCount, 0)
        XCTAssertEqual(result.sanitizedMessages.count, 0)
        XCTAssertTrue(result.preRoleSequence.isEmpty)
        XCTAssertTrue(result.postRoleSequence.isEmpty)
    }

    // MARK: - System and User Messages Always Pass Through

    func testSystemAndUserMessagesAlwaysPassThrough() throws {
        // Given: only system and user messages
        let messages: [ChatMessage] = [
            systemMessage(content: "System 1"),
            systemMessage(content: "System 2"),
            userMessage(content: "User 1"),
            userMessage(content: "User 2"),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(result.droppedUserCount, 0)
        XCTAssertEqual(result.droppedSystemCount, 0)
        XCTAssertEqual(result.sanitizedMessages.count, 4)
    }

    // MARK: - Legacy Compatibility Tests

    func testLegacyProperties() throws {
        // Given: sequence with drops
        let messages: [ChatMessage] = [
            userMessage(content: "Hello"),
            toolMessage(content: "Orphan", toolCallID: "call_orphan"),
            assistantMessage(content: "  "),
        ]

        // When
        let result = MessageSequenceValidator.sanitize(messages: messages, provider: "TestProvider")

        // Then: Verify legacy properties work
        XCTAssertEqual(result.wasModified, result.didMutate)
        XCTAssertEqual(result.droppedCount, result.droppedMessageCount)
        XCTAssertEqual(result.droppedRoles.count, 2)  // Should contain both drop reasons
    }
}
