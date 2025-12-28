//
//  ToolIconToggle.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/11/25.
//

import SwiftUI

/// A tappable icon toggle with neon glow effects.
/// Design spec: "Unified Neon Toggle Tools" from Liquid Glass UI improvements.
struct ToolIconToggle: View {
    let toolName: String
    let iconName: String
    @Binding var isEnabled: Bool

    @State private var didBounce = false

    var body: some View {
        Button {
            isEnabled.toggle()
            if isEnabled {
                triggerBounce()
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(isEnabled ? .orange : .blue.opacity(0.5))
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(isEnabled ? Color.orange.opacity(0.15) : Color.clear)
                        .overlay(
                                Circle()
                                    .stroke(
                                        isEnabled
                                            ? Color.orange.opacity(0.4) : Color.gray.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                }
                .symbolEffect(.bounce, value: didBounce)
                .shadow(color: isEnabled ? .cyan.opacity(0.4) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isEnabled)
        .help(toolName)
    }

    private func triggerBounce() {
        didBounce.toggle()
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        ToolIconToggle(
            toolName: "Terminal",
            iconName: "terminal",
            isEnabled: .constant(true)
        )

        ToolIconToggle(
            toolName: "File System",
            iconName: "folder",
            isEnabled: .constant(false)
        )

        ToolIconToggle(
            toolName: "Web Search",
            iconName: "globe",
            isEnabled: .constant(true)
        )
    }
    .padding()
    .background(Color.black)
}
