//
//  Canvas2PreviewFixtures.swift
//  llmHub
//
//  Deterministic fixtures for Canvas2 previews.
//

import Foundation
import SwiftData

@MainActor
// swiftlint:disable:next type_body_length
enum Canvas2PreviewFixtures {
    // MARK: - Stable constants

    static let baseDate = Date(timeIntervalSince1970: 1_735_689_600)  // 2024-12-31 00:00:00 UTC

    enum IDs {
        static let sessionA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        static let sessionB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        static let user1 = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        static let assistant1 = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        static let assistant2 = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

        static let streamingMessage = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        static let streamingGeneration = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
    }

    // MARK: - Markdown fixtures

    static let markdownShort: String = """
        Hi — here’s a quick checklist:

        - Parse markdown
        - Render code
        - Keep previews deterministic

        Inline code like `let x = 1` should be styled.
        """

    static let markdownLongWithCode: String = """
        # Canvas2 Preview Fixture

        This message is intentionally long and includes common Markdown constructs:

        ## Lists

        1. Ordered list item one
        2. Ordered list item two

        - Unordered item A
        - Unordered item B

        > A blockquote that should render as a block.

        ## Fenced code

        ```swift
        struct Example {
            let name: String
            func greet() -> String { "Hello, \\(name)!" }
        }
        ```

        ## Inline code + emphasis

        Use `@MainActor` for UI-facing state. **Bold** and _italic_ should render.
        """

    static let markdownVeryLong: String = (0..<20)
        .map { index in "Paragraph \(index + 1): \(markdownShort)" }
        .joined(separator: "\n\n")

    // MARK: - Artifacts

    static func toolResultArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            title: "Tool Result • http_request",
            kind: .toolResult,
            status: .success,
            previewText: """
                {
                  "status": 200,
                  "contentType": "application/json",
                  "body": { "ok": true, "items": [1,2,3] }
                }
                """,
            actions: [.copy],
            metadata: nil
        )
    }

    static func codeFileArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            title: "Snippet.swift",
            kind: .code,
            status: .success,
            previewText: """
                import SwiftUI

                struct TinyView: View {
                    var body: some View {
                        Text("Hello from an artifact")
                            .padding()
                    }
                }
                """,
            actions: [.copy, .open],
            metadata: nil
        )
    }

    static func errorArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            title: "Tool Result • shell",
            kind: .toolResult,
            status: .failure,
            previewText: """
                exit code: 127
                stderr: command not found: rg
                """,
            actions: [.copy],
            metadata: nil
        )
    }

    // MARK: - More Artifacts

    /// Sample text artifact.
    static func textArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "Summary",
            kind: .text,
            status: .success,
            previewText:
                "The analysis shows a 15% improvement in response latency after the optimization.",
            actions: [.copy],
            metadata: nil
        )
    }

    /// Sample pending artifact.
    static func pendingArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Processing...",
            kind: .other,
            status: .pending,
            previewText: "Waiting for tool output...",
            actions: [],
            metadata: nil
        )
    }

    // MARK: - Tool Executions

    /// Sample tool execution (running).
    static func runningExecution() -> ToolExecution {
        ToolExecution(
            id: "exec-001",
            toolID: "http_request",
            name: "http_request",
            icon: "network",
            status: .running,
            output: "GET https://api.openai.com/v1/models...",
            timestamp: baseDate
        )
    }

    /// Sample tool execution (completed).
    static func completedExecution() -> ToolExecution {
        ToolExecution(
            id: "exec-002",
            toolID: "run_command",
            name: "run_command",
            icon: "terminal",
            status: .completed,
            output: """
                total 24
                drwxr-xr-x  5 user  staff   160 Jan  1 00:00 .
                drwxr-xr-x  3 user  staff    96 Jan  1 00:00 ..
                """,
            timestamp: baseDate.addingTimeInterval(-60)
        )
    }

    /// Sample tool execution (failed).
    static func failedExecution() -> ToolExecution {
        ToolExecution(
            id: "exec-003",
            toolID: "file_read",
            name: "file_read",
            icon: "doc.text",
            status: .failed,
            output: "Error: File not found: /path/to/missing/file.txt",
            timestamp: baseDate.addingTimeInterval(-120)
        )
    }

    // MARK: - Transcript rows

    static func shortTranscriptRows() -> [TranscriptRowViewModel] {
        [
            TranscriptRowViewModel(
                id: "message:\(IDs.user1.uuidString)",
                role: .user,
                headerLabel: "You",
                content: "Can you show me Canvas2 previews with markdown + artifacts?",
                isStreaming: false,
                generationID: nil,
                artifacts: []
            ),
            TranscriptRowViewModel(
                id: "message:\(IDs.assistant1.uuidString)",
                role: .assistant,
                headerLabel: "Assistant",
                content: markdownShort,
                isStreaming: false,
                generationID: UUID(uuidString: "12121212-1212-1212-1212-121212121212"),
                artifacts: [toolResultArtifact()]
            )
        ]
    }

    static func longTranscriptRows(messageCount: Int = 20) -> [TranscriptRowViewModel] {
        return (0..<messageCount).map { index in
            let isUser = (index % 2 == 0)
            let id =
                isUser
                ? UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
                : UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index + 1))!
            let header = isUser ? "You" : "Assistant"
            let content =
                (index == 3)
                ? markdownLongWithCode
                : "Message \(index + 1) • deterministic preview content (no Date.now)"
            let artifacts: [ArtifactPayload] = {
                if index == 5 { return [codeFileArtifact()] }
                if index == 8 { return [toolResultArtifact(), errorArtifact()] }
                return []
            }()
            return TranscriptRowViewModel(
                id: "message:\(id.uuidString)",
                role: isUser ? .user : .assistant,
                headerLabel: header,
                content: content,
                isStreaming: false,
                generationID: isUser
                    ? nil
                    : UUID(uuidString: String(format: "33333333-3333-3333-3333-%012d", index + 1)),
                artifacts: artifacts
            )
        }
    }

    static func streamingRow(headerLabel: String = "Assistant") -> TranscriptRowViewModel {
        TranscriptRowViewModel(
            id: "streaming:\(IDs.sessionA.uuidString):\(IDs.streamingGeneration.uuidString)",
            role: .assistant,
            headerLabel: headerLabel,
            content: "Streaming… partial assistant message that is still being generated.",
            isStreaming: true,
            generationID: IDs.streamingGeneration,
            artifacts: []
        )
    }

    // MARK: - SwiftData seeding (for root previews)

    // swiftlint:disable:next function_body_length
    static func seedSessions(into context: ModelContext) throws {
        let sessionA = ChatSessionEntity(
            session: ChatSession(
                id: IDs.sessionA,
                title: "Canvas2 • Preview Session",
                providerID: "openai",
                model: "gpt-4o",
                createdAt: baseDate,
                updatedAt: baseDate.addingTimeInterval(60),
                messages: [],
                metadata: ChatSessionMetadata(
                    lastTokenUsage: nil, totalCostUSD: 0, referenceID: "preview-a")
            )
        )

        let sessionB = ChatSessionEntity(
            session: ChatSession(
                id: IDs.sessionB,
                title: "Canvas2 • Empty Session",
                providerID: "anthropic",
                model: "claude-3-5-sonnet-latest",
                createdAt: baseDate.addingTimeInterval(-3600),
                updatedAt: baseDate.addingTimeInterval(-1800),
                messages: [],
                metadata: ChatSessionMetadata(
                    lastTokenUsage: nil, totalCostUSD: 0, referenceID: "preview-b")
            )
        )

        // Messages for sessionA
        let message1 = ChatMessageEntity(
            message: ChatMessage(
                id: IDs.user1,
                role: .user,
                content: "Please render markdown and artifacts.",
                parts: [.text("Please render markdown and artifacts.")],
                createdAt: baseDate.addingTimeInterval(10),
                codeBlocks: []
            )
        )
        message1.session = sessionA

        let message2 = ChatMessageEntity(
            message: ChatMessage(
                id: IDs.assistant1,
                role: .assistant,
                content: markdownLongWithCode,
                parts: [.text(markdownLongWithCode)],
                createdAt: baseDate.addingTimeInterval(20),
                codeBlocks: []
            )
        )
        message2.session = sessionA

        let message3 = ChatMessageEntity(
            message: ChatMessage(
                id: IDs.assistant2,
                role: .assistant,
                content: "Here is an attached artifact for inspection.",
                parts: [.text("Here is an attached artifact for inspection.")],
                attachments: [
                    Attachment(
                        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                        filename: "Snippet.swift",
                        url: URL(fileURLWithPath: "/tmp/Snippet.swift"),
                        type: .code,
                        previewText: "print(\"hi\")\n"
                    )
                ],
                createdAt: baseDate.addingTimeInterval(30),
                codeBlocks: []
            )
        )
        message3.session = sessionA

        context.insert(sessionA)
        context.insert(sessionB)
        context.insert(message1)
        context.insert(message2)
        context.insert(message3)

        try context.save()
    }

    static func ensureSeeded(into context: ModelContext) {
        do {
            let sessionAID = IDs.sessionA
            let existing = try context.fetchCount(
                FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionAID })
            )
            guard existing == 0 else { return }
            try seedSessions(into: context)
        } catch {
            // Best-effort: previews should never crash due to fixture seeding.
            // If seeding fails, previews will simply render the empty state.
        }
    }
}
