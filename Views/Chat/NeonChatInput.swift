//
//  NeonChatInput.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonChatInput: View {
    @Binding var messageText: String
    @Binding var toolsEnabled: Bool
    let availableTools: [UIToolDefinition]
    let toolAnimation: Namespace.ID
    let onSend: () -> Void
    let onToolTrigger: (UIToolDefinition) -> Void

    @State private var showToolPicker = false
    @State private var selectedTools: Set<UUID> = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Tool Trigger Bubble
            if toolsEnabled {
                HStack {
                    NeonToolTriggerBubble(
                        showToolPicker: $showToolPicker,
                        selectedTools: $selectedTools,
                        availableTools: availableTools,
                        namespace: toolAnimation,
                        onToolTrigger: onToolTrigger
                    )

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Input Field
            HStack(alignment: .bottom, spacing: 12) {
                // Text Input
                ZStack(alignment: .topLeading) {
                    if messageText.isEmpty {
                        Text("Message...")
                            .font(.system(size: 14))
                            .foregroundColor(.neonGray.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $messageText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 120)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isInputFocused)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.neonCharcoal.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isInputFocused
                                        ? Color.neonElectricBlue.opacity(0.5)
                                        : Color.neonGray.opacity(0.2), lineWidth: 1)
                        )
                )

                // Send Button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(
                            messageText.isEmpty ? .neonGray.opacity(0.3) : .neonElectricBlue)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.neonCharcoal.opacity(0.2)
            }
        )
    }
}

// MARK: - Tool Trigger Bubble

struct NeonToolTriggerBubble: View {
    @Binding var showToolPicker: Bool
    @Binding var selectedTools: Set<UUID>
    let availableTools: [UIToolDefinition]
    let namespace: Namespace.ID
    let onToolTrigger: (UIToolDefinition) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Toggle Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showToolPicker.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 12))
                        .foregroundColor(showToolPicker ? .neonElectricBlue : .neonGray)

                    if !showToolPicker {
                        Text("Tools")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.neonGray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    showToolPicker
                                        ? Color.neonElectricBlue.opacity(0.6)
                                        : Color.neonGray.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .matchedGeometryEffect(id: "toolBubble", in: namespace)

            // Expanded Tool Icons
            if showToolPicker {
                ForEach(availableTools.prefix(5)) { tool in
                    Button(action: { onToolTrigger(tool) }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.neonElectricBlue)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.neonCharcoal.opacity(0.6))
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                Color.neonElectricBlue.opacity(0.4), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                }
            }
        }
    }
}
