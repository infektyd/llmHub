//
//  CanvasChatView.swift
//  llmHub
//
//  Chat view rendering a no-bubble transcript on a "canvas" surface.
//

import SwiftData
import SwiftUI

struct CanvasChatView: View {
    @Environment(\.theme) private var theme
    @Environment(WorkbenchViewModel.self) private var workbenchVM
    @Environment(\.modelContext) private var modelContext

    let session: ChatSessionEntity

    @State private var chatVM = ChatViewModel()
    @State private var composerText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            CanvasComposerBar(text: $composerText, onSend: {
                send()
            })
            .frame(maxWidth: 860)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .padding(.top, 10)
        }
        .background(theme.backgroundPrimary)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(orderedMessages) { message in
                        CanvasTranscriptRow(message: message)
                            .id(message.id)
                    }

                    if chatVM.isThinking {
                        CanvasStatusRow(text: "Thinking…")
                            .transition(.opacity)
                    }

                    if let streaming = chatVM.streamingDisplayMessage {
                        CanvasMessageRow(role: .assistant, markdown: streaming.content)
                            .id(streaming.id)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 18)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }
            .onChange(of: chatVM.lastVisibleMessageID) { _, newValue in
                guard let id = newValue else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onAppear {
                if let lastID = orderedMessages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var orderedMessages: [ChatMessageEntity] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""

        chatVM.sendMessage(
            messageText: text,
            attachments: nil,
            session: session,
            modelContext: modelContext,
            selectedProvider: workbenchVM.selectedProvider,
            selectedModel: workbenchVM.selectedModel
        )
    }
}

private struct CanvasTranscriptRow: View {
    @Environment(\.theme) private var theme
    let message: ChatMessageEntity

    var body: some View {
        switch message.asDomain().role {
        case .user, .assistant:
            if let toolCalls = toolCalls(for: message), !toolCalls.isEmpty {
                VStack(spacing: 0) {
                    if !message.content.isEmpty {
                        CanvasMessageRow(role: message.asDomain().role, markdown: message.content)
                    }

                    CanvasToolSectionView(
                        section: CanvasToolSection(
                            title: toolCalls.count == 1 ? "1 step" : "\(toolCalls.count) steps",
                            steps: toolCalls.map { .init(title: $0.name, status: .done) }
                        )
                    )
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                }
            } else {
                CanvasMessageRow(role: message.asDomain().role, markdown: message.content)
            }

        case .tool:
            CanvasToolOutputRow(toolCallID: message.toolCallID, output: message.content)

        case .system:
            CanvasStatusRow(text: message.content)
        }
    }

    private func toolCalls(for message: ChatMessageEntity) -> [ToolCall]? {
        guard let toolCallsData = message.toolCallsData else { return nil }
        return try? JSONDecoder().decode([ToolCall].self, from: toolCallsData)
    }
}

private struct CanvasToolOutputRow: View {
    @Environment(\.theme) private var theme
    let toolCallID: String?
    let output: String

    var body: some View {
        DisclosureGroup {
            ScrollView(.horizontal) {
                Text(output)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            HStack(spacing: 10) {
                Text("Tool Output")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                if let toolCallID {
                    Text(toolCallID)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .disclosureGroupStyle(.automatic)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.surface.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(theme.textPrimary.opacity(0.10), lineWidth: theme.borderWidth)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
    }
}

private struct CanvasStatusRow: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
    }
}

#Preview("Canvas Chat View") {
    CanvasChatView(session: MockData.chatSession())
        .previewEnvironment()
        .environment(\.theme, CanvasDarkTheme())
}
