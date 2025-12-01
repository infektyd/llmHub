//
//  NeonToolbar.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonToolbar: View {
    let session: ChatSessionEntity
    @Binding var selectedProvider: UILLMProvider?
    @Binding var selectedModel: UILLMModel?
    let scrollOffset: CGFloat
    @Binding var toolInspectorVisible: Bool

    private var toolbarOpacity: Double {
        // Fade toolbar when scrolling down
        let threshold: CGFloat = 50
        if scrollOffset > threshold {
            return 1.0
        } else if scrollOffset < -threshold {
            return 0.7
        } else {
            return 1.0 - (abs(scrollOffset) / threshold) * 0.3
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Conversation Title
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("\(session.messages.count) messages")
                    .font(.system(size: 11))
                    .foregroundColor(.neonGray)
            }

            Spacer()

            // Model Picker
            NeonModelPicker(
                selectedProvider: $selectedProvider,
                selectedModel: $selectedModel
            )

            // Tool Inspector Toggle
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    toolInspectorVisible.toggle()
                }
            }) {
                Image(systemName: toolInspectorVisible ? "sidebar.right.fill" : "sidebar.right")
                    .font(.system(size: 16))
                    .foregroundColor(toolInspectorVisible ? .neonElectricBlue : .neonGray)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.neonCharcoal.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial
                .opacity(toolbarOpacity)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.neonGray.opacity(0.2)),
            alignment: .bottom
        )
    }
}
