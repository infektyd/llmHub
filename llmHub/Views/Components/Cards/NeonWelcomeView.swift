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

    var body: some View {
        VStack(spacing: 24) {
            // Mark
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.accent.opacity(0.18),
                                Color.green.opacity(0.10),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.accent, Color.blue.opacity(0.7)],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("llmHub")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Select a conversation or create a new one to begin")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }

            // Quick Actions
            HStack(spacing: 16) {
                QuickActionButton(
                    icon: "plus.bubble.fill",
                    title: "New Chat",
                    color: AppColors.accent,
                    action: {
                        viewModel.createNewConversation(modelContext: modelContext)
                    }
                )

                QuickActionButton(
                    icon: "folder.fill",
                    title: "Browse",
                    color: AppColors.textSecondary,
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

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = true

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
                isHovered
                    ? .regular.tint(color.opacity(0.3)).interactive() : .regular.interactive(),
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
// MARK: - Previews

#Preview("Welcome View - Default") {
    NeonWelcomeView()
        .previewEnvironment()
        .frame(width: 800, height: 600)
}
#Preview("Welcome View - Large") {
    NeonWelcomeView()
        .previewEnvironment()
        .frame(width: 1200, height: 800)
}

#Preview("Quick Action Button - New Chat") {
    QuickActionButton(
        icon: "plus.bubble.fill",
        title: "New Chat",
        color: .blue,
        action: { print("New Chat tapped") }
    )
    .previewEnvironment()
    .padding()
}

#Preview("Quick Action Button - Browse") {
    QuickActionButton(
        icon: "folder.fill",
        title: "Browse",
        color: .secondary,
        action: { print("Browse tapped") }
    )
    .previewEnvironment()
    .padding()
}

