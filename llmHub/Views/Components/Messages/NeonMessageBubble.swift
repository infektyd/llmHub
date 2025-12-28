//
//  NeonMessageBubble.swift
//  llmHub
//
//  Created by AI Assistant on 12/26/25.
//

import SwiftData
import SwiftUI

/// A message bubble view with neon-style glass effects for the chat interface
struct NeonMessageBubble: View, Equatable {
    @Environment(\.theme) private var theme

    let message: ChatMessageEntity
    let isStreaming: Bool

    private var isUserMessage: Bool {
        message.role == MessageRole.user.rawValue
    }

    static func == (lhs: NeonMessageBubble, rhs: NeonMessageBubble) -> Bool {
        let idsMatch = lhs.message.id == rhs.message.id
        let contentMatches = lhs.message.content == rhs.message.content
        let streamingMatches = lhs.isStreaming == rhs.isStreaming
        return idsMatch && contentMatches && streamingMatches
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            roleIndicator

            VStack(alignment: .leading, spacing: 8) {
                roleLabel
                messageContent
                timestampView
                streamingIndicator
            }

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Subviews

    private var roleIndicator: some View {
        Circle()
            .fill(isUserMessage ? theme.accent : theme.accentSecondary)
            .frame(width: 8, height: 8)
            .padding(.top, 8)
    }

    private var roleLabel: some View {
        Text(isUserMessage ? "You" : "Assistant")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var messageContent: some View {
        Text(message.content)
            .textSelection(.enabled)
            .font(.body)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var timestampView: some View {
        if !isStreaming {
            Text(message.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if isStreaming {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(theme.accentSecondary)
                        .frame(width: 4, height: 4)
                        .opacity(0.1)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: isStreaming
                        )
                }
                Text("Streaming...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: theme.cornerRadius)
            .fill(theme.usesGlassEffect ? Color.black.opacity(0) : theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        isUserMessage
                            ? theme.accent.opacity(0)
                            : theme.accentSecondary.opacity(0),
                        lineWidth: theme.borderWidth
                    )
            }
    }
}

// MARK: - Previews

#Preview("User Message") {
    NeonMessageBubble(
        message: MockData.userMessage(),
        isStreaming: false
    )
    .padding()
    .previewEnvironment()
}

#Preview("Assistant Streaming") {
    NeonMessageBubble(
        message: MockData.assistantMessage(content: "I'm thinking..."),
        isStreaming: true
    )
    .padding()
    .previewEnvironment()
}
