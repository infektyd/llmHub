//
//  TranscriptRowBundlingTests.swift
//  llmHubTests
//
//  Unit tests for Tool Run Bundle grouping robustness in transcript mapping.
//  Tests cover interleaved messages, out-of-order tool results, and partial matches.
//

import XCTest
import SwiftData

@testable import llmHub

@MainActor
final class TranscriptRowBundlingTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }
    
    // MARK: - Test Helpers
    
    private func createSession() -> ChatSessionEntity {
        let session = ChatSessionEntity(
            session: ChatSession(
                id: UUID(),
                title: "Test Session",
                providerID: "test",
                model: "test-model",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [],
                metadata: ChatSessionMetadata()
            )
        )
        modelContext.insert(session)
        return session
    }
    
    private func createUserMessage(content: String = "test user", session: ChatSessionEntity) -> ChatMessageEntity {
        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: []
        )
        let entity = ChatMessageEntity(message: message)
        entity.session = session
        modelContext.insert(entity)
        return entity
    }
    
    private func createAssistantMessage(
        content: String = "test assistant",
        toolCalls: [ToolCall]? = nil,
        session: ChatSessionEntity
    ) -> ChatMessageEntity {
        let message = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: [],
            toolCallID: nil,
            toolCalls: toolCalls
        )
        let entity = ChatMessageEntity(message: message)
        entity.session = session
        modelContext.insert(entity)
        return entity
    }
    
    private func createToolMessage(
        content: String = "test tool result",
        toolCallID: String,
        toolName: String = "test_tool",
        success: Bool = true,
        session: ChatSessionEntity
    ) -> ChatMessageEntity {
        let message = ChatMessage(
            id: UUID(),
            role: .tool,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: [],
            toolCallID: toolCallID,
            toolCalls: nil,
            toolResultMeta: ToolResultMeta(
                toolName: toolName,
                success: success
            )
        )
        let entity = ChatMessageEntity(message: message)
        entity.session = session
        modelContext.insert(entity)
        return entity
    }
    
    private func buildRows(from session: ChatSessionEntity) -> [TranscriptRowViewModel] {
        let messages = session.messages.sorted { $0.createdAt < $1.createdAt }
        let toolCallArgumentsByID = buildToolCallArgumentsIndex(messages)
        return buildTranscriptRows(messages, toolCallArgumentsByID: toolCallArgumentsByID)
    }
    
    private func buildToolCallArgumentsIndex(_ messages: [ChatMessageEntity]) -> [String: String] {
        messages.reduce(into: [:]) { partialResult, entity in
            let message = entity.asDomain()
            guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else { return }
            for call in toolCalls {
                partialResult[call.id] = call.input
            }
        }
    }
    
    private func buildTranscriptRows(
        _ messages: [ChatMessageEntity],
        toolCallArgumentsByID: [String: String]
    ) -> [TranscriptRowViewModel] {
        var rows: [TranscriptRowViewModel] = []
        var index = 0
        while index < messages.count {
            let entity = messages[index]
            let message = entity.asDomain()
            if message.role == .assistant,
                let toolCalls = message.toolCalls,
                !toolCalls.isEmpty
            {
                let toolCallIDs = toolCalls.map { $0.id }.filter { !$0.isEmpty }
                let assistantRow = mapToViewModel(entity, toolCallArgumentsByID: toolCallArgumentsByID)
                rows.append(assistantRow)
                if toolCallIDs.count == toolCalls.count,
                    let bundleResult = buildToolRunBundleRow(
                        parentEntity: entity,
                        startIndex: index + 1,
                        expectedToolCallIDs: toolCallIDs,
                        messages: messages,
                        toolCallArgumentsByID: toolCallArgumentsByID
                    )
                {
                    rows.append(bundleResult.bundleRow)
                    index = bundleResult.nextIndex
                    continue
                }
                index += 1
                continue
            }
            
            rows.append(mapToViewModel(entity, toolCallArgumentsByID: toolCallArgumentsByID))
            index += 1
        }
        return rows
    }
    
    private struct ToolRunBundleBuildResult {
        let bundleRow: TranscriptRowViewModel
        let nextIndex: Int
    }
    
    private func buildToolRunBundleRow(
        parentEntity: ChatMessageEntity,
        startIndex: Int,
        expectedToolCallIDs: [String],
        messages: [ChatMessageEntity],
        toolCallArgumentsByID: [String: String]
    ) -> ToolRunBundleBuildResult? {
        let expectedToolCallIDSet = Set(expectedToolCallIDs)
        
        let maxWindowSize = 50
        var toolMessagesByID: [String: (entity: ChatMessageEntity, index: Int)] = [:]
        var cursor = startIndex
        var lastToolIndex = startIndex - 1
        
        while cursor < messages.count && cursor < startIndex + maxWindowSize {
            let nextEntity = messages[cursor]
            let nextMessage = nextEntity.asDomain()
            
            if nextMessage.role == .assistant,
               let toolCalls = nextMessage.toolCalls,
               !toolCalls.isEmpty {
                break
            }
            
            if nextMessage.role == .tool,
               let toolCallID = nextMessage.toolCallID,
               expectedToolCallIDSet.contains(toolCallID) {
                if toolMessagesByID[toolCallID] == nil {
                    toolMessagesByID[toolCallID] = (nextEntity, cursor)
                    lastToolIndex = cursor
                }
            }
            
            cursor += 1
        }
        
        var toolRows: [TranscriptRowViewModel] = []
        var matchedIDs = Set<String>()
        
        for toolCallID in expectedToolCallIDs {
            if let (entity, _) = toolMessagesByID[toolCallID] {
                let message = entity.asDomain()
                toolRows.append(
                    mapToViewModel(
                        message,
                        isStreaming: false,
                        rowID: entity.id,
                        toolCallArgumentsByID: toolCallArgumentsByID
                    )
                )
                matchedIDs.insert(toolCallID)
            }
        }
        
        guard !toolRows.isEmpty else { return nil }
        
        let status = toolRunBundleStatus(
            expectedCount: expectedToolCallIDSet.count,
            toolRows: toolRows
        )
        let bundleID = "tool-bundle:\(parentEntity.id.uuidString)"
        let bundle = ToolRunBundleViewModel(
            id: bundleID,
            parentAssistantMessageID: parentEntity.id,
            title: "Run Bundle",
            label: parentEntity.toolRunLabel,
            toolRows: toolRows,
            expectedToolCount: expectedToolCallIDSet.count,
            status: status
        )
        let bundleRow = TranscriptRowViewModel(
            id: bundleID,
            kind: .toolRunBundle(bundle),
            role: .tool,
            headerLabel: "Tool Run",
            headerMetaText: nil,
            content: "",
            isStreaming: false,
            generationID: parentEntity.generationID,
            artifacts: []
        )
        return ToolRunBundleBuildResult(bundleRow: bundleRow, nextIndex: lastToolIndex + 1)
    }
    
    private func toolRunBundleStatus(
        expectedCount: Int,
        toolRows: [TranscriptRowViewModel]
    ) -> ToolRunBundleStatus {
        guard toolRows.count >= expectedCount else { return .running }
        let successValues = toolRows.compactMap { $0.toolResultMeta?.success }
        guard successValues.count == toolRows.count else { return .running }
        if successValues.allSatisfy({ $0 }) { return .success }
        if successValues.allSatisfy({ !$0 }) { return .failure }
        return .partialFailure
    }
    
    private func mapToViewModel(
        _ entity: ChatMessageEntity,
        toolCallArgumentsByID: [String: String]
    ) -> TranscriptRowViewModel {
        mapToViewModel(
            entity.asDomain(),
            isStreaming: false,
            rowID: entity.id,
            toolCallArgumentsByID: toolCallArgumentsByID
        )
    }
    
    private func mapToViewModel(
        _ message: ChatMessage,
        isStreaming: Bool,
        rowID: UUID,
        toolCallArgumentsByID: [String: String]
    ) -> TranscriptRowViewModel {
        let toolCallArguments = message.toolCallID.flatMap { toolCallArgumentsByID[$0] }
        
        return TranscriptRowViewModel(
            id: rowID.uuidString,
            role: message.role,
            headerLabel: headerLabel(for: message),
            headerMetaText: nil,
            content: message.content,
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: [],
            attachments: [],
            toolCallID: message.toolCallID,
            toolResultMeta: message.toolResultMeta,
            toolCallArguments: toolCallArguments
        )
    }
    
    private func headerLabel(for message: ChatMessage) -> String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }
    
    // MARK: - Baseline Tests
    
    func testBaseline_SequentialToolResults() throws {
        // Given: assistant with 3 tool calls followed by 3 tool results in order
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}"),
            ToolCall(id: "call_3", name: "list_dir", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        let assistant = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        _ = createToolMessage(content: "result 3", toolCallID: "call_3", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should create bundle with all 3 tool results
        XCTAssertEqual(rows.count, 2, "Should have user message + assistant + bundle")
        
        guard case .toolRunBundle(let bundle) = rows[1].kind else {
            XCTFail("Second row should be a tool run bundle")
            return
        }
        
        XCTAssertEqual(bundle.toolRows.count, 3, "Bundle should contain all 3 tool results")
        XCTAssertEqual(bundle.expectedToolCount, 3)
        XCTAssertEqual(bundle.status, .success)
        XCTAssertEqual(bundle.parentAssistantMessageID, assistant.id)
    }
    
    // MARK: - Interleaving Tests
    
    func testInterleaving_UserMessageBetweenToolResults() throws {
        // Given: assistant with 2 tool calls, then tool result, user message, tool result
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        let assistant = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        _ = createUserMessage(content: "Interrupting message", session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should still bundle both tool results despite user message in between
        var bundleFound = false
        for row in rows {
            if case .toolRunBundle(let bundle) = row.kind {
                bundleFound = true
                XCTAssertEqual(bundle.toolRows.count, 2, "Bundle should contain both tool results despite interleaving")
                XCTAssertEqual(bundle.expectedToolCount, 2)
                XCTAssertEqual(bundle.parentAssistantMessageID, assistant.id)
            }
        }
        XCTAssertTrue(bundleFound, "Should have created a bundle")
    }
    
    func testInterleaving_AssistantMessageBetweenToolResults() throws {
        // Given: assistant with 2 tool calls, then tool result, assistant message (no tools), tool result
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        let assistant = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        _ = createAssistantMessage(content: "Thinking...", toolCalls: nil, session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should bundle both tool results despite assistant message in between
        var bundleFound = false
        for row in rows {
            if case .toolRunBundle(let bundle) = row.kind {
                bundleFound = true
                XCTAssertEqual(bundle.toolRows.count, 2, "Bundle should contain both tool results despite assistant message")
                XCTAssertEqual(bundle.expectedToolCount, 2)
                XCTAssertEqual(bundle.parentAssistantMessageID, assistant.id)
            }
        }
        XCTAssertTrue(bundleFound, "Should have created a bundle")
    }
    
    // MARK: - Out-of-Order Tests
    
    func testOutOfOrder_ToolResultsReversed() throws {
        // Given: assistant with tool calls [call_1, call_2, call_3], results arrive as [call_3, call_1, call_2]
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}"),
            ToolCall(id: "call_3", name: "list_dir", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        let assistant = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "result 3", toolCallID: "call_3", session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should bundle all 3 tool results regardless of order
        guard case .toolRunBundle(let bundle) = rows[1].kind else {
            XCTFail("Second row should be a tool run bundle")
            return
        }
        
        XCTAssertEqual(bundle.toolRows.count, 3, "Bundle should contain all 3 tool results")
        XCTAssertEqual(bundle.expectedToolCount, 3)
        XCTAssertEqual(bundle.status, .success)
        
        // Verify rows are assembled in expected order (matching toolCalls order)
        XCTAssertEqual(bundle.toolRows[0].toolCallID, "call_1")
        XCTAssertEqual(bundle.toolRows[1].toolCallID, "call_2")
        XCTAssertEqual(bundle.toolRows[2].toolCallID, "call_3")
    }
    
    func testOutOfOrder_InterleavedAndReversed() throws {
        // Given: assistant with tool calls, results arrive out of order with user messages interleaved
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}"),
            ToolCall(id: "call_3", name: "list_dir", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        let assistant = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        _ = createUserMessage(content: "Still waiting...", session: session)
        _ = createToolMessage(content: "result 3", toolCallID: "call_3", session: session)
        _ = createAssistantMessage(content: "Processing...", toolCalls: nil, session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should bundle all 3 tool results in correct order
        var bundleFound = false
        for row in rows {
            if case .toolRunBundle(let bundle) = row.kind {
                bundleFound = true
                XCTAssertEqual(bundle.toolRows.count, 3, "Bundle should contain all 3 tool results")
                XCTAssertEqual(bundle.expectedToolCount, 3)
                XCTAssertEqual(bundle.parentAssistantMessageID, assistant.id)
                
                // Verify order matches toolCalls, not arrival order
                XCTAssertEqual(bundle.toolRows[0].toolCallID, "call_1")
                XCTAssertEqual(bundle.toolRows[1].toolCallID, "call_2")
                XCTAssertEqual(bundle.toolRows[2].toolCallID, "call_3")
            }
        }
        XCTAssertTrue(bundleFound, "Should have created a bundle")
    }
    
    // MARK: - Partial Match Tests
    
    func testPartialMatch_MissingOneToolResult() throws {
        // Given: assistant with 3 tool calls, only 2 results arrive
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}"),
            ToolCall(id: "call_3", name: "list_dir", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        let assistant = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should create bundle with 2 results, status should be .running
        guard case .toolRunBundle(let bundle) = rows[1].kind else {
            XCTFail("Second row should be a tool run bundle")
            return
        }
        
        XCTAssertEqual(bundle.toolRows.count, 2, "Bundle should contain 2 tool results")
        XCTAssertEqual(bundle.expectedToolCount, 3, "Expected count should still be 3")
        XCTAssertEqual(bundle.status, .running, "Status should be .running when not all results arrived")
    }
    
    func testPartialMatch_NoToolResults() throws {
        // Given: assistant with tool calls, but no tool results arrive
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do some work", session: session)
        _ = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createUserMessage(content: "Next message", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should NOT create a bundle (returns nil when no tool results found)
        XCTAssertEqual(rows.count, 3, "Should have user + assistant + user (no bundle)")
        for row in rows {
            if case .toolRunBundle = row.kind {
                XCTFail("Should not create bundle when no tool results found")
            }
        }
    }
    
    // MARK: - Boundary Tests
    
    func testBoundary_StopsAtNextAssistantWithToolCalls() throws {
        // Given: two consecutive assistant messages with tool calls
        let session = createSession()
        
        let toolCalls1 = [
            ToolCall(id: "call_1", name: "read_file", input: "{}")
        ]
        let toolCalls2 = [
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "First request", session: session)
        let assistant1 = createAssistantMessage(content: "", toolCalls: toolCalls1, session: session)
        _ = createUserMessage(content: "Second request", session: session)
        _ = createAssistantMessage(content: "", toolCalls: toolCalls2, session: session)
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        _ = createToolMessage(content: "result 2", toolCallID: "call_2", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: First assistant should NOT bundle call_1 result (it appears after second assistant)
        // Second assistant should bundle call_2 result
        var firstBundleFound = false
        var secondBundleFound = false
        
        for row in rows {
            if case .toolRunBundle(let bundle) = row.kind {
                if bundle.parentAssistantMessageID == assistant1.id {
                    firstBundleFound = true
                } else {
                    secondBundleFound = true
                    XCTAssertEqual(bundle.toolRows.count, 1)
                    XCTAssertEqual(bundle.toolRows[0].toolCallID, "call_2")
                }
            }
        }
        
        XCTAssertFalse(firstBundleFound, "First assistant should not create bundle (results appear after next assistant)")
        XCTAssertTrue(secondBundleFound, "Second assistant should create bundle")
    }
    
    func testBoundary_WindowSizeLimit() throws {
        // Given: assistant with tool call, result appears beyond reasonable window
        // This is a theoretical edge case - in practice, window size is 50 messages
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}")
        ]
        
        _ = createUserMessage(content: "Request", session: session)
        _ = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        
        // Insert 51 user messages to exceed window
        for i in 0..<51 {
            _ = createUserMessage(content: "Filler \(i)", session: session)
        }
        
        _ = createToolMessage(content: "result 1", toolCallID: "call_1", session: session)
        
        // When
        let rows = buildRows(from: session)
        
        // Then: Should NOT create bundle (result is beyond window)
        for row in rows {
            if case .toolRunBundle = row.kind {
                XCTFail("Should not create bundle when result is beyond window size")
            }
        }
    }
    
    // MARK: - Status Tests
    
    func testStatus_AllSuccess() throws {
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do work", session: session)
        _ = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "success 1", toolCallID: "call_1", toolName: "read_file", success: true, session: session)
        _ = createToolMessage(content: "success 2", toolCallID: "call_2", toolName: "grep_search", success: true, session: session)
        
        let rows = buildRows(from: session)
        
        guard case .toolRunBundle(let bundle) = rows[1].kind else {
            XCTFail("Should have bundle")
            return
        }
        
        XCTAssertEqual(bundle.status, .success)
    }
    
    func testStatus_AllFailure() throws {
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do work", session: session)
        _ = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "error 1", toolCallID: "call_1", toolName: "read_file", success: false, session: session)
        _ = createToolMessage(content: "error 2", toolCallID: "call_2", toolName: "grep_search", success: false, session: session)
        
        let rows = buildRows(from: session)
        
        guard case .toolRunBundle(let bundle) = rows[1].kind else {
            XCTFail("Should have bundle")
            return
        }
        
        XCTAssertEqual(bundle.status, .failure)
    }
    
    func testStatus_PartialFailure() throws {
        let session = createSession()
        
        let toolCalls = [
            ToolCall(id: "call_1", name: "read_file", input: "{}"),
            ToolCall(id: "call_2", name: "grep_search", input: "{}")
        ]
        
        _ = createUserMessage(content: "Do work", session: session)
        _ = createAssistantMessage(content: "", toolCalls: toolCalls, session: session)
        _ = createToolMessage(content: "success", toolCallID: "call_1", toolName: "read_file", success: true, session: session)
        _ = createToolMessage(content: "error", toolCallID: "call_2", toolName: "grep_search", success: false, session: session)
        
        let rows = buildRows(from: session)
        
        guard case .toolRunBundle(let bundle) = rows[1].kind else {
            XCTFail("Should have bundle")
            return
        }
        
        XCTAssertEqual(bundle.status, .partialFailure)
    }
}
