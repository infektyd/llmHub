//
//  NordicMessageBubble.swift
//  llmHub
//
//  Message bubble component for Nordic theme.
//  ZERO beta APIs - fully compatible with View Hierarchy Debugger.
//

import SwiftUI

/// Message bubble for Nordic theme - user and assistant messages
struct NordicMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text("AI Assistant")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(NordicColors.textPrimary(colorScheme))
                }

                bubbleContent

                // Timestamp
                Text(message.createdAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(NordicColors.textMuted(colorScheme))
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 15))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(NordicColors.accentPrimary(colorScheme))
            )
    }

    private var assistantBubble: some View {
        HStack(spacing: 0) {
            // Sage accent bar
            Rectangle()
                .fill(NordicColors.accentSecondary(colorScheme))
                .frame(width: 3)

            // Content
            Text(message.content)
                .font(.system(size: 15))
                .foregroundColor(NordicColors.textPrimary(colorScheme))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(NordicColors.surface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(NordicColors.border(colorScheme), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Previews

#Preview("User - Short") {
    NordicMessageBubble(
        message: ChatMessage(
            id: UUID(),
            role: .user,
            content: PreviewData.shortUserMessage,
            parts: [.text(PreviewData.shortUserMessage)],
            attachments: [],
            createdAt: PreviewData.sampleTimestamp,
            codeBlocks: []
        )
    )
    .padding()
}

#Preview("User - Long") {
    NordicMessageBubble(
        message: ChatMessage(
            id: UUID(),
            role: .user,
            content: PreviewData.longUserMessage,
            parts: [.text(PreviewData.longUserMessage)],
            attachments: [],
            createdAt: PreviewData.sampleTimestamp,
            codeBlocks: []
        )
    )
    .padding()
}

#Preview("Assistant - Short") {
    NordicMessageBubble(
        message: ChatMessage(
            id: UUID(),
            role: .assistant,
            content: PreviewData.shortAssistantMessage,
            parts: [.text(PreviewData.shortAssistantMessage)],
            attachments: [],
            createdAt: PreviewData.sampleTimestamp,
            codeBlocks: []
        )
    )
    .padding()
}

#Preview("Assistant - Long") {
    NordicMessageBubble(
        message: ChatMessage(
            id: UUID(),
            role: .assistant,
            content: PreviewData.longAssistantMessage,
            parts: [.text(PreviewData.longAssistantMessage)],
            attachments: [],
            createdAt: PreviewData.sampleTimestamp,
            codeBlocks: []
        )
    )
    .padding()
}

#Preview("Conversation - Dark Mode") {
    VStack(spacing: 0) {
        NordicMessageBubble(
            message: ChatMessage(
                id: UUID(),
                role: .user,
                content: "Can you help me with SwiftUI?",
                parts: [.text("Can you help me with SwiftUI?")],
                attachments: [],
                createdAt: Date(),
                codeBlocks: []
            )
        )

        NordicMessageBubble(
            message: ChatMessage(
                id: UUID(),
                role: .assistant,
                content:
                    "Of course! I'd be happy to help you with SwiftUI. What specific aspect would you like to learn about?",
                parts: [
                    .text(
                        "Of course! I'd be happy to help you with SwiftUI. What specific aspect would you like to learn about?"
                    )
                ],
                attachments: [],
                createdAt: Date(),
                codeBlocks: []
            )
        )
    }
    .background(NordicColors.Dark.canvas)
    .preferredColorScheme(.dark)
}
