//
//  ComposerBar.swift
//  llmHub
//
//  Bottom overlay composer bar (input + send + stop)
//  Flat design with shadow, no glass effects
//

import SwiftData
import SwiftUI

/// Bottom composer bar for input and controls
/// Flat matte surface with shadow (no glass blur)
struct ComposerBar: View {
    @Binding var leftSidebarVisible: Bool
    @Binding var rightSidebarVisible: Bool
    @Binding var showSettings: Bool

    let selectedSession: ChatSessionEntity?
    let modelRegistry: ModelRegistry
    let viewModel: WorkbenchViewModel

    @Environment(ChatViewModel.self) private var chatVM
    @State private var inputText: String = ""
    @State private var thinkingPreference: ThinkingPreference = .auto
    @FocusState private var isInputFocused: Bool

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            // Left sidebar toggle
            Button {
                withAnimation {
                    leftSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        leftSidebarVisible ? AppColors.accent : AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            // Input field
            HStack(spacing: 8) {
                TextField("Type a message…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }

                // Send / Stop button
                if chatVM.isGenerating {
                    Button {
                        Task {
                            await chatVM.stopGeneration()
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                inputText.isEmpty ? AppColors.textTertiary : AppColors.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.backgroundSecondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
            }

            // Right sidebar toggle
            Button {
                withAnimation {
                    rightSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        rightSidebarVisible ? AppColors.accent : AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            // Settings button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surface)
                .shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: -4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
        }
        .onAppear {
            print("DEBUG: ComposerBar chatVM ID: \(ObjectIdentifier(chatVM))")
        }
    }

    // MARK: - Private Methods

    private func sendMessage() {
        guard !inputText.isEmpty, let session = selectedSession else { return }

        let messageCopy = inputText
        inputText = ""

        // Trigger generation using ChatViewModel
        chatVM.sendMessage(
            messageText: messageCopy,
            attachments: nil,
            session: session,
            modelContext: modelContext,
            selectedProvider: viewModel.selectedProvider,
            selectedModel: viewModel.selectedModel,
            thinkingPreference: thinkingPreference
        )
    }
}
