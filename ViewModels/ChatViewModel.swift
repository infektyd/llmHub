//
//  ChatViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
class ChatViewModel {
    var messageText: String = ""
    var toolsEnabled: Bool = true
    var availableTools: [UIToolDefinition] = UIToolDefinition.sampleTools

    // This would be initialized with a specific session entity in a real app
    // For now, it manages the transient state of the chat view

    func sendMessage(session: ChatSessionEntity, modelContext: ModelContext) {
        guard !messageText.isEmpty else { return }

        let newMessage = ChatMessage(
            id: UUID(),
            role: .user,
            content: messageText,
            parts: [.text(messageText)],
            createdAt: Date(),
            codeBlocks: []
        )

        let messageEntity = ChatMessageEntity(message: newMessage)
        session.messages.append(messageEntity)
        session.updatedAt = Date()

        messageText = ""

        // Simulate AI response
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                let responseMessage = ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "This is a simulated response for: \"\(newMessage.content)\"",
                    parts: [.text("This is a simulated response for: \"\(newMessage.content)\"")],
                    createdAt: Date(),
                    codeBlocks: []
                )
                let responseEntity = ChatMessageEntity(message: responseMessage)
                session.messages.append(responseEntity)
            }
        }
    }

    func triggerTool(_ tool: UIToolDefinition, workbenchVM: WorkbenchViewModel) {
        let execution = ToolExecution(
            id: UUID(),
            name: tool.name,
            icon: tool.icon,
            status: .running,
            output: "Executing \(tool.name)...",
            timestamp: Date()
        )

        workbenchVM.activeToolExecution = execution
        workbenchVM.toolInspectorVisible = true

        // Simulate completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            workbenchVM.activeToolExecution = ToolExecution(
                id: execution.id,
                name: tool.name,
                icon: tool.icon,
                status: .success,
                output: "Successfully executed \(tool.name)\n\nResult: Sample output data...",
                timestamp: execution.timestamp
            )
        }
    }
}
