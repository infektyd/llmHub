//
//  NeonWelcomeView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftData
import SwiftUI

struct NeonWelcomeView: View {
    @Environment(WorkbenchViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    
    var body: some View {
        VStack(spacing: 24) {
            // Mark
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.accent.opacity(0.18),
                                Color.purple.opacity(0.10),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "sparkles")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.accent, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("llmHub")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(theme.textPrimary)

                Text("Select a conversation or create a new one to begin")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
            }

            // Quick Actions
            HStack(spacing: 16) {
                QuickActionButton(
                    icon: "plus.bubble.fill",
                    title: "New Chat",
                    color: theme.accent,
                    action: {
                        viewModel.createNewConversation(modelContext: modelContext)
                    }
                )

                QuickActionButton(
                    icon: "folder.fill",
                    title: "Browse",
                    color: theme.textSecondary,
                    action: {
                        // Scroll to show all conversations in sidebar
                        viewModel.clearSelection()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(width: 140, height: 100)
            .glassEffect(
                isHovered ? .regular.tint(color.opacity(0.3)).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
