//
//  NordicChatView.swift
//  llmHub
//
//  Main chat container demonstrating Nordic theme.
//

import SwiftUI

/// A demonstration chat view showcasing the Nordic theme
struct NordicChatView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText = ""
    @State private var demoMessages: [DemoChatMessage] = [
        DemoChatMessage(
            id: UUID(),
            role: .user,
            content: "Can you help me understand Swift concurrency?",
            createdAt: Date().addingTimeInterval(-300)
        ),
        DemoChatMessage(
            id: UUID(),
            role: .assistant,
            content:
                "Of course! Swift concurrency is built around async/await and actors. The key concepts are:\n\n1. **async/await** - For asynchronous code\n2. **Actors** - For thread-safe state management\n3. **Tasks** - For structured concurrency\n\nWould you like me to explain any of these in more detail?",
            createdAt: Date().addingTimeInterval(-240)
        ),
        DemoChatMessage(
            id: UUID(),
            role: .user,
            content: "Yes, please explain actors",
            createdAt: Date().addingTimeInterval(-120)
        ),
    ]

    var body: some View {
        HSplitView {
            NordicSidebar()
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Main chat area
            VStack(spacing: 0) {
                // Header
                chatHeader

                Divider()
                    .background(colorScheme == .dark ? Color(hex: "44403C") : Color(hex: "E7E5E4"))

                // Messages
                messagesArea

                // Input
                NordicInputBar(text: $inputText) {
                    sendMessage()
                }
            }
            .background(colorScheme == .dark ? Color(hex: "1C1917") : Color(hex: "FAF9F7"))
        }
    }

    private var chatHeader: some View {
        HStack {
            Text("AI Assistant")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color(hex: "FAFAF9") : Color(hex: "1C1917"))

            Spacer()

            // Theme indicator
            Text("Nordic Theme")
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color(hex: "292524") : Color(hex: "E7E5E4"))
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(colorScheme == .dark ? Color(hex: "1C1917") : Color(hex: "FAF9F7"))
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(demoMessages) { message in
                        SimplifiedNordicMessageRow(
                            message: message,
                            isUser: message.role == .user
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let newMessage = DemoChatMessage(
            id: UUID(),
            role: .user,
            content: inputText,
            createdAt: Date()
        )
        demoMessages.append(newMessage)
        inputText = ""

        // Simulate AI response after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let response = DemoChatMessage(
                id: UUID(),
                role: .assistant,
                content:
                    "This is a demo response in the Nordic theme. The actual AI integration would happen here.",
                createdAt: Date()
            )
            demoMessages.append(response)
        }
    }
}

/// Demo message model
struct DemoChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date
}

/// Simplified message row for Nordic demo
struct SimplifiedNordicMessageRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let message: DemoChatMessage
    let isUser: Bool

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text("AI Assistant")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }

                messageContent

                // Timestamp
                Text(message.createdAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var messageContent: some View {
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
                    .fill(Color(hex: "CD6F4E"))  // Terracotta
            )
    }

    private var assistantBubble: some View {
        HStack(spacing: 0) {
            // Left accent bar
            Rectangle()
                .fill(Color(hex: "7BA382"))  // Sage
                .frame(width: 3)

            // Content
            Text(message.content)
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(hex: "292524") : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            colorScheme == .dark ? Color(hex: "44403C") : Color(hex: "E7E5E4"),
                            lineWidth: 1
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
