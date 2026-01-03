//
//  ComposerBar.swift
//  llmHub
//
//  Bottom overlay composer bar (input + send + stop)
//  Flat design with shadow, no glass effects
//

import SwiftData
import SwiftUI

/// Pure, preview-friendly composer UI (no SwiftData, no providers).
struct ComposerBarView: View {
    @Binding var leftSidebarVisible: Bool
    @Binding var rightSidebarVisible: Bool
    @Binding var showSettings: Bool
    @Binding var inputText: String

    let isStreaming: Bool
    let stagingArtifacts: [Artifact]
    let stagedAttachments: [Attachment]
    let onSend: () -> Void
    let onStop: () -> Void
    let onRemoveArtifact: (UUID) -> Void
    let onRemoveAttachment: (UUID) -> Void

    @FocusState private var isInputFocused: Bool

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

            // Input Container (Bubble)
            VStack(alignment: .leading, spacing: 8) {
                // Staged Artifacts
                if !stagingArtifacts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stagingArtifacts) { artifact in
                                ArtifactPreviewChip(artifact: artifact) {
                                    onRemoveArtifact(artifact.id)
                                }
                            }
                        }
                        // Padding to align with input text
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                }

                // Input field + Send Button
                HStack(spacing: 8) {
                    TextField("Type a message…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                        .onSubmit { onSend() }

                    // Send / Stop button
                    if isStreaming {
                        Button(action: onStop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(
                                    inputText.isEmpty ? AppColors.textTertiary : AppColors.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.isEmpty)
                    }
                }
                // Staged attachments (images/files)
                if !stagedAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stagedAttachments) { attachment in
                                AttachmentPreviewChip(attachment: attachment) {
                                    onRemoveAttachment(attachment.id)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
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
    }
}

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

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ComposerBarView(
            leftSidebarVisible: $leftSidebarVisible,
            rightSidebarVisible: $rightSidebarVisible,
            showSettings: $showSettings,
            inputText: $inputText,
            isStreaming: chatVM.isGenerating,
            stagingArtifacts: chatVM.stagingArtifacts,
            stagedAttachments: chatVM.stagedAttachments,
            onSend: sendMessage,
            onStop: {
                Task { await chatVM.stopGeneration() }
            },
            onRemoveArtifact: { id in
                chatVM.removeStagedArtifact(id: id)
            },
            onRemoveAttachment: { id in
                chatVM.removeStagedAttachment(id: id)
            }
        )
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

#if DEBUG
    #Preview("Composer - Idle") {
        @Previewable @State var left = true
        @Previewable @State var right = false
        @Previewable @State var showSettings = false
        @Previewable @State var input = ""

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: false,
            stagingArtifacts: [],
            stagedAttachments: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in }
        )
        .padding()
        .frame(width: 900)
    }

    #Preview("Composer - Input filled") {
        @Previewable @State var left = true
        @Previewable @State var right = false
        @Previewable @State var showSettings = false
        @Previewable @State var input = "Hello, world!"

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: false,
            stagingArtifacts: [],
            stagedAttachments: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in }
        )
        .padding()
        .frame(width: 900)
    }

    #Preview("Composer - Streaming") {
        @Previewable @State var left = true
        @Previewable @State var right = true
        @Previewable @State var showSettings = false
        @Previewable @State var input = "Stop me"

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: true,
            stagingArtifacts: [],
            stagedAttachments: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in }
        )
        .padding()
        .frame(width: 900)
    }

    #Preview("Composer - Multiline") {
        @Previewable @State var left = true
        @Previewable @State var right = false
        @Previewable @State var showSettings = false
        @Previewable @State var input = "Line 1\nLine 2\nLine 3"

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: false,
            stagingArtifacts: [],
            stagedAttachments: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in }
        )
        .padding()
        .frame(width: 900)
    }
#endif
