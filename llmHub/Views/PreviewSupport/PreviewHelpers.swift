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

    static func toolCallBlock(
        name: String = "run_command",
        input: String = "{\"command\": \"ls -la\"}",
        output: String? = "file1.txt\nfile2.swift"
    ) -> ToolCallBlock {
        ToolCallBlock(
            id: "call_\(UUID().uuidString.prefix(8))",
            name: name,
            input: input,
            output: output
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

// MARK: - Preview Modifiers

extension View {
    /// Convenient modifier to inject preview environment
    @MainActor
    func previewEnvironment() -> some View {
        self
            .environment(\.modelContext, PreviewContainer.shared.context)
            .environment(MockData.workbenchViewModel())
            .environmentObject(MockData.modelRegistry())
            .environment(\.keychainStore, KeychainStore(backend: InMemoryKeychainBacking(), accessGroups: []))
            
    }
}
