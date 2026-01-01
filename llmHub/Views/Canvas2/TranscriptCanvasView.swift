//
//  TranscriptCanvasView.swift
//  llmHub
//
//  Central canvas transcript with no bubbles, just role labels + text
//  Uses Textual for rendering transcript content
//

import SwiftData
import SwiftUI

// Note: Textual will be imported once package is added

/// Canvas view for displaying the conversation transcript
/// No message bubbles - flat design with role labels
struct TranscriptCanvasView: View {
    let session: ChatSessionEntity

    @Environment(WorkbenchViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(ChatViewModel.self) private var chatVM

    @State private var scrollProxy: ScrollViewProxy?

    private var messages: [ChatMessageEntity] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(transcriptRows) { rowVM in
                        TranscriptRow(viewModel: rowVM)
                            .id(rowVM.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .background(AppColors.backgroundPrimary)
            .onAppear {
                print("DEBUG: TranscriptCanvasView chatVM ID: \(ObjectIdentifier(chatVM))")
                scrollProxy = proxy
                scrollToBottom()
            }
            .onChange(of: transcriptRows.count) { _, count in
                print("DEBUG: Transcript count: \(count)")
                scrollToBottom()
            }
            .onChange(of: chatVM.streamingDisplayMessage) { _, _ in
                scrollToBottom()
            }
        }
    }

    private var transcriptRows: [TranscriptRowViewModel] {
        var rows = messages.map { mapToViewModel($0) }

        guard let streaming = chatVM.streamingDisplayMessage else { return rows }

        // Deduplication Logic:
        // If the last persisted message is an assistant message created AFTER the current stream started,
        // we assume persistence has caught up and the stream is finished.
        // This prevents showing both the streaming overlay AND the persisted message simultaneously,
        // avoiding "jumps" or duplicates.
        if let last = messages.last,
            last.role == "assistant" || last.role == "model",
            last.createdAt >= streaming.createdAt
        {
            return rows
        }

        rows.append(mapToViewModel(streaming, isStreaming: true))
        return rows
    }

    private func mapToViewModel(_ entity: ChatMessageEntity) -> TranscriptRowViewModel {
        mapToViewModel(entity.asDomain(), isStreaming: false)
    }

    private func mapToViewModel(_ message: ChatMessage, isStreaming: Bool) -> TranscriptRowViewModel
    {
        let isUser = message.role == .user
        let label = isUser ? "You" : providerLabel(for: message)

        // Map artifacts
        let artifacts = message.artifactMetadatas.map { meta in
            ArtifactPayload(
                id: UUID(),  // Stable ID ideally, but UUID for now
                title: meta.filename,
                kind: mapArtifactKind(meta.language),
                status: .success,  // Assume success for past messages
                previewText: meta.content,
                actions: [.copy, .open],
                metadata: meta
            )
        }

        return TranscriptRowViewModel(
            id: message.id,
            role: message.role,
            headerLabel: label,
            content: message.content,
            isStreaming: isStreaming,
            artifacts: artifacts
        )
    }

    private func providerLabel(for message: ChatMessage) -> String {
        // Here we could try to look up provider/model form session,
        // but for individual messages we might default to "Assistant"
        // or parse from metadata if stored.
        // For now, let's use a generic "Assistant" or try to pull from session if possible.
        // Actually, the previous implementation used `message.providerID` which doesn't exist on ChatMessage
        // but DOES exist on ChatMessageEntity via relationship potentially?
        // The original TranscriptRow used `msg.providerID` but `ChatMessageEntity` doesn't have providerID field directly,
        // it's on the session.

        if let currentModel = session.model as String?, !currentModel.isEmpty {
            return currentModel  // simplistic, improving later
        }
        return "Assistant"
    }

    private func mapArtifactKind(_ lang: CodeLanguage) -> ArtifactKind {
        switch lang {
        case .json, .swift, .python, .javascript: return .code
        case .markdown, .text: return .text
        }
    }

    private func scrollToBottom() {
        guard let proxy = scrollProxy else { return }

        if let streaming = chatVM.streamingDisplayMessage {
            withAnimation {
                proxy.scrollTo(streaming.id, anchor: .bottom)
            }
        } else if let lastMessage = messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}
