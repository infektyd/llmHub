//
//  NordicSidebar.swift
//  llmHub
//
//  Clean conversation list sidebar for Nordic theme.
//

import SwiftUI

/// A minimalist sidebar demonstrating Nordic theme styling
struct NordicSidebar: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    // Demo data - in real implementation, this would come from ConversationStore
    @State private var conversations: [DemoConversation] = [
        DemoConversation(id: UUID(), title: "Swift Concurrency Help", isSelected: true),
        DemoConversation(id: UUID(), title: "UI Design Discussion", isSelected: false),
        DemoConversation(id: UUID(), title: "Code Review", isSelected: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Conversations")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)

            // New Chat button
            NordicButton("New Chat", style: .secondary) {
                // Create new conversation
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Divider()
                .background(colorScheme == .dark ? Color(hex: "44403C") : Color(hex: "E7E5E4"))

            // Conversation list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(conversations) { conversation in
                        NordicSidebarRow(
                            conversation: conversation,
                            isSelected: conversation.isSelected
                        ) {
                            selectConversation(conversation)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .frame(width: 240)
        .background(colorScheme == .dark ? Color(hex: "1C1917") : Color(hex: "F0EEEB"))
    }

    private func selectConversation(_ conversation: DemoConversation) {
        for index in conversations.indices {
            conversations[index].isSelected = (conversations[index].id == conversation.id)
        }
    }
}

/// Demo conversation model for Nordic sidebar
struct DemoConversation: Identifiable {
    let id: UUID
    let title: String
    var isSelected: Bool
}

/// A sidebar row for conversation items
struct NordicSidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let conversation: DemoConversation
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(conversation.title)
                .font(.system(size: 14))
                .foregroundColor(textColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(hex: "7BA382")  // Sage when selected
        }
        if isHovered {
            return colorScheme == .dark ? Color(hex: "292524") : Color(hex: "E7E5E4")
        }
        return Color.clear
    }

    private var textColor: Color {
        if isSelected {
            return .white
        }
        return colorScheme == .dark ? Color(hex: "FAFAF9") : Color(hex: "1C1917")
    }
}
