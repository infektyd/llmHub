//
//  NordicMessageRow.swift
//  llmHub
//
//  Message row component for Nordic theme - NO BUBBLES, text on canvas.
//  ZERO beta APIs - fully compatible with View Hierarchy Debugger.
//

import SwiftUI

/// Message row for Nordic theme - NO bubbles, just text on canvas
struct NordicMessageRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 80)
            }

            HStack(alignment: .top, spacing: 12) {
                // Left accent bar for assistant only
                if !isUser {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(NordicColors.accentSecondary(colorScheme))
                        .frame(width: 3)
                }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    // Content - NO background
                    Text(message.content)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(NordicColors.textPrimary(colorScheme))
                        .textSelection(.enabled)
                        .multilineTextAlignment(isUser ? .trailing : .leading)

                    // Timestamp
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 11))
                        .foregroundColor(NordicColors.textSecondary(colorScheme))
                }
            }
            // NO .background() — text floats on canvas

            if !isUser {
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

// MARK: - Previews

#Preview("User Message") {
    VStack(spacing: 0) {
        NordicMessageRow(
            message: ChatMessage(
                id: UUID(),
                role: .user,
                content: "Can you help me with SwiftUI concurrency?",
                parts: [.text("Can you help me with SwiftUI concurrency?")],
                attachments: [],
                createdAt: Date(),
                codeBlocks: []
            )
        )
    }
    .background(NordicColors.Light.canvas)
    .preferredColorScheme(.light)
}

#Preview("Assistant Message") {
    VStack(spacing: 0) {
        NordicMessageRow(
            message: ChatMessage(
                id: UUID(),
                role: .assistant,
                content:
                    "Of course! Swift concurrency is built around async/await and actors. The key concepts are:\n\n1. **async/await** - For asynchronous code\n2. **Actors** - For thread-safe state management\n3. **Tasks** - For structured concurrency\n\nWould you like me to explain any of these in more detail?",
                parts: [
                    .text("Of course! Swift concurrency is built around async/await and actors...")
                ],
                attachments: [],
                createdAt: Date(),
                codeBlocks: []
            )
        )
    }
    .background(NordicColors.Light.canvas)
    .preferredColorScheme(.light)
}

#Preview("Conversation - Dark Mode") {
    VStack(spacing: 0) {
        NordicMessageRow(
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

        NordicMessageRow(
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

        NordicMessageRow(
            message: ChatMessage(
                id: UUID(),
                role: .user,
                content: "How do I create custom views?",
                parts: [.text("How do I create custom views?")],
                attachments: [],
                createdAt: Date(),
                codeBlocks: []
            )
        )
    }
    .background(NordicColors.Dark.canvas)
    .preferredColorScheme(.dark)
}
