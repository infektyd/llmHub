//
//  NeonDarkTranscriptPreview.swift
//  llmHub
//
//  Created by AI Assistant on 2025-12-13.
//

import MarkdownUI
import SwiftUI

struct NeonDarkTranscriptPreview: View {
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        NeonChatView(session: mockSession)
            .environment(WorkbenchViewModel())  // Stub viewModel
            .environment(\.theme, NeonGlassTheme())  // Preview with Neon theme
            .environmentObject(ModelRegistry())
            .preferredColorScheme(.dark)
            .onAppear {
                themeManager.setTranscriptStyle(.neonDark)
            }
    }

    var mockSession: ChatSessionEntity {
        let messages = [
            ChatMessage(
                id: UUID(),
                role: .user,
                content: "Hallo hallo",
                parts: [],
                createdAt: Date(),
                codeBlocks: []
            ),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content:
                    "Hals' on your mind today? Working on llmHub, diving deeper into SYNTRA, or something entirely different?",
                parts: [],
                createdAt: Date(),
                codeBlocks: []
            ),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "",
                parts: [],
                createdAt: Date(),
                codeBlocks: [],
                toolCalls: [
                    ToolCall(id: "call_1", name: "Tool Name", input: "{}")
                ]
            ),
            ChatMessage(
                id: UUID(),
                role: .tool,
                content: "Sample output\nSample output message",
                parts: [],
                createdAt: Date(),
                codeBlocks: [],
                toolCallID: "call_1"
            ),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Here is some code for you to check out:",
                parts: [],
                createdAt: Date(),
                codeBlocks: []
            ),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "```swift\nfunc helloWorld() {\n    print(\"Hello World\")\n}\n```",
                parts: [],
                createdAt: Date(),
                codeBlocks: []
            ),
        ]

        let session = ChatSession(
            id: UUID(),
            title: "Neon Dark Preview",
            providerID: "mock",
            model: "mock-model",
            createdAt: Date(),
            updatedAt: Date(),
            messages: messages,
            metadata: ChatSessionMetadata(
                lastTokenUsage: nil,
                totalCostUSD: 0,
                referenceID: ""
            )
        )

        return ChatSessionEntity(session: session)
    }
}

#Preview {
    NeonDarkTranscriptPreview()
}
