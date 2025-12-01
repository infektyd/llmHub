//
//  NeonWelcomeView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonWelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Neon Logo/Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .neonElectricBlue.opacity(0.3),
                                .neonFuchsia.opacity(0.2),
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
                            colors: [.neonElectricBlue, .neonFuchsia],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Neon Agent Workbench")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .neonGray],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("Select a conversation or create a new one to begin")
                    .font(.system(size: 14))
                    .foregroundColor(.neonGray)
            }

            // Quick Actions
            HStack(spacing: 16) {
                QuickActionButton(
                    icon: "plus.bubble.fill",
                    title: "New Chat",
                    color: .neonElectricBlue
                )

                QuickActionButton(
                    icon: "folder.fill",
                    title: "Browse",
                    color: .neonFuchsia
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.neonMidnight)
    }
}

private struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    @State private var isHovered = false

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(isHovered ? 0.6 : 0.3), lineWidth: 1.5)
                    )
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
