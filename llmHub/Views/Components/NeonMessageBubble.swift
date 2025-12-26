//
//  NeonMessageBubble.swift
//  llmHub
//
//  Created by AI Assistant on 12/26/25.
//

import SwiftUI

/// A message bubble view with neon-style glass effects for the chat interface
struct NeonMessageBubble: View, Equatable {
    let message: ChatMessageEntity
    let isStreaming: Bool
    
    static func == (lhs: NeonMessageBubble, rhs: NeonMessageBubble) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.content == rhs.message.content &&
        lhs.isStreaming == rhs.isStreaming
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Role indicator
            Circle()
                .fill(message.role == .user ? Color.neonElectricBlue : Color.neonCyan)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                // Role label
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Message content
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                // Timestamp
                if !isStreaming {
                    Text(message.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Streaming indicator
                if isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.neonCyan)
                                .frame(width: 4, height: 4)
                                .opacity(0.6)
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
            
            Spacer()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            message.role == .user
                                ? Color.neonElectricBlue.opacity(0.3)
                                : Color.neonCyan.opacity(0.3),
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        NeonMessageBubble(
            message: ChatMessageEntity(
                message: ChatMessage(
                    id: UUID(),
                    role: .user,
                    content: "Hello, how can you help me today?",
                    thoughtProcess: nil,
                    parts: [],
                    createdAt: Date(),
                    codeBlocks: [],
                    tokenUsage: nil,
                    costBreakdown: nil,
                    toolCallID: nil,
                    toolCalls: nil
                )
            ),
            isStreaming: false
        )
        
        NeonMessageBubble(
            message: ChatMessageEntity(
                message: ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "I'd be happy to help you with that...",
                    thoughtProcess: nil,
                    parts: [],
                    createdAt: Date(),
                    codeBlocks: [],
                    tokenUsage: nil,
                    costBreakdown: nil,
                    toolCallID: nil,
                    toolCalls: nil
                )
            ),
            isStreaming: true
        )
    }
    .padding()
    .background(Color.black)
}
