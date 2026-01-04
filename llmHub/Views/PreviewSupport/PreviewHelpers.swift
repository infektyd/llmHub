import Foundation
import SwiftData
import SwiftUI

// MARK: - Preview Container

@MainActor
class PreviewContainer {
    static let shared = PreviewContainer()

    let container: ModelContainer
    let context: ModelContext

    private init() {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}

// MARK: - Mock Data Factories

enum MockData {
    // MARK: - Messages

    static func userMessage(
        content: String = "Can you help me understand SwiftUI previews?",
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ChatMessageEntity {
        ChatMessageEntity(
            message: ChatMessage(
                id: id,
                role: .user,
                content: content,
                parts: [],
                createdAt: createdAt,
                codeBlocks: []
            )
        )
    }

    static func assistantMessage(
        content: String = "SwiftUI previews allow you to see live renderings of your views.",
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ChatMessageEntity {
        ChatMessageEntity(
            message: ChatMessage(
                id: id,
                role: .assistant,
                content: content,
                parts: [],
                createdAt: createdAt,
                codeBlocks: []
            )
        )
    }

    static func toolMessage(
        content: String = "Command executed successfully",
        toolCallID: String = "call_123",
        id: UUID = UUID()
    ) -> ChatMessageEntity {
        let msg = ChatMessage(
            id: id,
            role: .tool,
            content: content,
            parts: [],
            createdAt: Date(),
            codeBlocks: [],
            toolCallID: toolCallID
        )
        return ChatMessageEntity(message: msg)
    }

    // MARK: - Sessions

    static func chatSession(
        title: String = "Preview Chat",
        messageCount: Int = 3
    ) -> ChatSessionEntity {
        let session = ChatSession(
            id: UUID(),
            title: title,
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date(),
            messages: (0..<messageCount).map { i in
                ChatMessage(
                    id: UUID(),
                    role: i % 2 == 0 ? .user : .assistant,
                    content: "Message \(i + 1)",
                    parts: [],
                    createdAt: Date(),
                    codeBlocks: []
                )
            },
            metadata: ChatSessionMetadata(
                lastTokenUsage: nil,
                totalCostUSD: 0,
                referenceID: UUID().uuidString
            )
        )
        return ChatSessionEntity(session: session)
    }

    // MARK: - View Models

    static func workbenchViewModel() -> WorkbenchViewModel {
        WorkbenchViewModel()
    }

    static func modelRegistry() -> ModelRegistry {
        ModelRegistry()
    }

    static func sidebarViewModel() -> SidebarViewModel {
        SidebarViewModel()
    }

    // MARK: - UI Model Types

    static func uiLLMProvider(
        id: UUID = UUID(),
        name: String = "OpenAI",
        icon: String = "sparkles",
        models: [UILLMModel] = [uiLLMModel()],
        isActive: Bool = true
    ) -> UILLMProvider {
        UILLMProvider(
            id: id,
            name: name,
            icon: icon,
            models: models,
            isActive: isActive
        )
    }

    static func uiLLMModel(
        id: UUID = UUID(),
        modelID: String = "gpt-4o",
        name: String = "GPT-4o",
        contextWindow: Int = 128000
    ) -> UILLMModel {
        UILLMModel(
            id: id,
            modelID: modelID,
            name: name,
            contextWindow: contextWindow
        )
    }

    // MARK: - Tool Calls

    static func toolCall(
        name: String = "run_command",
        input: String = "{\"command\": \"ls -la\"}"
    ) -> ToolCall {
        ToolCall(
            id: "call_\(UUID().uuidString.prefix(8))",
            name: name,
            input: input
        )
    }

    // MARK: - Attachments

    static func imageAttachment(filename: String = "screenshot.png") -> Attachment {
        Attachment(
            filename: filename,
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            type: .image
        )
    }

    static func codeAttachment(filename: String = "example.swift") -> Attachment {
        Attachment(
            filename: filename,
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            type: .code,
            previewText: "func example() {\n    print(\"Hello\")\n}"
        )
    }

    // MARK: - References

    static func chatReference(text: String = "Selected text") -> ChatReference {
        ChatReference(
            text: text,
            sourceMessageID: UUID(),
            role: .assistant
        )
    }
}

// MARK: - Canvas2 Preview Fixtures

/// Preview fixtures for Canvas2 inspector and artifact views.
enum Canvas2PreviewFixtures {
    /// Base date for consistent preview timestamps.
    static let baseDate = Date(timeIntervalSince1970: 1735689600) // 2025-01-01 00:00:00 UTC
    
    /// Sample tool result artifact.
    static func toolResultArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "HTTP Response",
            kind: .toolResult,
            status: .success,
            previewText: """
            {
              "status": 200,
              "body": {
                "models": ["gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"]
              }
            }
            """,
            actions: [.copy],
            metadata: ["tool": "http_request", "duration_ms": "234"]
        )
    }
    
    /// Sample code file artifact.
    static func codeFileArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "example.swift",
            kind: .code,
            status: .success,
            previewText: """
            import Foundation
            
            struct Example {
                let name: String
                let value: Int
                
                func describe() -> String {
                    "\\(name): \\(value)"
                }
            }
            """,
            actions: [.copy, .open],
            metadata: ["language": "swift", "lines": "11"]
        )
    }
    
    /// Sample error artifact.
    static func errorArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Failed Request",
            kind: .toolResult,
            status: .failure,
            previewText: "Error: Connection refused (ECONNREFUSED)\nHost: localhost:8080\nTimeout: 30s",
            actions: [.copy, .retry],
            metadata: ["tool": "http_request", "error_code": "ECONNREFUSED"]
        )
    }
    
    /// Sample text artifact.
    static func textArtifact() -> ArtifactPayload {
        ArtifactPayload(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "Summary",
            kind: .text,
            status: .success,
            previewText: "The analysis shows a 15% improvement in response latency after the optimization.",
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
            output: "total 24\ndrwxr-xr-x  5 user  staff   160 Jan  1 00:00 .\ndrwxr-xr-x  3 user  staff    96 Jan  1 00:00 ..",
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
}

// MARK: - Preview Modifiers

extension View {
    /// Convenient modifier to inject preview environment
    @MainActor
    func previewEnvironment() -> some View {
        self
            .environment(\.modelContext, PreviewContainer.shared.context)
            .environment(MockData.workbenchViewModel())
            .environmentObject(MockData.modelRegistry())
            .environment(
                \.keychainStore, KeychainStore(backend: InMemoryKeychainBacking(), accessGroups: [])
            )

    }
}
