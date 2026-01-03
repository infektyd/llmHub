//
//  TranscriptCanvasView.swift
//  llmHub
//
//  Central canvas transcript with no bubbles, just role labels + text
//  Uses Textual for rendering transcript content
//

import SwiftUI

// Note: Textual will be imported once package is added

/// Canvas view for displaying the conversation transcript
/// No message bubbles - flat design with role labels
struct TranscriptCanvasView: View {
    let rows: [TranscriptRowViewModel]
    let streamingRow: TranscriptRowViewModel?

    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(mergedRows) { rowVM in
                        TranscriptRow(viewModel: rowVM)
                            .id(rowVM.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .background(AppColors.backgroundPrimary)
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
            .onChange(of: mergedRows.count) { _, _ in
                scrollToBottom()
            }
        }
    }

    private var mergedRows: [TranscriptRowViewModel] {
        guard let streamingRow else { return rows }
        return rows + [streamingRow]
    }

    private func scrollToBottom() {
        guard let proxy = scrollProxy else { return }
        if let last = mergedRows.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - SwiftData container (production integration)

/// Container view that bridges SwiftData + streaming overlay into a plain `TranscriptCanvasView`.
struct TranscriptCanvasSessionView: View {
    let session: ChatSessionEntity

    @Environment(ChatViewModel.self) private var chatVM

    private var messages: [ChatMessageEntity] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        TranscriptCanvasView(rows: persistedRows, streamingRow: streamingOverlayRow)
            .onChange(of: chatVM.streamingDisplayMessage) { _, _ in
                // The pure view handles scrolling; this container just recomputes rows.
            }
    }

    private var persistedRows: [TranscriptRowViewModel] {
        messages.map { mapToViewModel($0) }
    }

    private var streamingOverlayRow: TranscriptRowViewModel? {
        guard let streaming = chatVM.streamingDisplayMessage else { return nil }

        // Only show overlay when it isn't already persisted (join via generationID).
        if let generationID = streaming.generationID {
            let lastPersistedAssistantGenerationID: UUID? =
                messages.reversed().first(where: { $0.role == "assistant" || $0.role == "model" })?
                .generationID
            if lastPersistedAssistantGenerationID == generationID {
                return nil
            }
            return mapToViewModel(
                streaming,
                isStreaming: true,
                rowID: streamingRowID(sessionID: session.id, generationID: generationID)
            )
        }

        // Defensive fallback: still show a streaming row even if generationID is missing.
        return mapToViewModel(streaming, isStreaming: true, rowID: persistedRowID(streaming.id))
    }

    private func mapToViewModel(_ entity: ChatMessageEntity) -> TranscriptRowViewModel {
        mapToViewModel(entity.asDomain(), isStreaming: false, rowID: persistedRowID(entity.id))
    }

    private func mapToViewModel(_ message: ChatMessage, isStreaming: Bool, rowID: String)
        -> TranscriptRowViewModel
    {
        // Runtime artifact detection
        let detection = ArtifactService.detect(from: message.content, messageID: message.id)
        let cleanContent = detection.cleanContent

        // Merge detected artifacts with persisted metadata artifacts
        var mergedArtifacts = detection.artifacts

        let persistedArtifacts = message.artifactMetadatas.map { meta in
            ArtifactPayload(
                id: Canvas2StableIDs.artifactID(messageID: message.id, metadata: meta),
                title: meta.filename,
                kind: mapArtifactKind(meta.language),
                status: .success,
                previewText: meta.content,
                actions: [.copy, .open],
                metadata: meta
            )
        }

        mergedArtifacts.append(contentsOf: persistedArtifacts)

        let isUser = message.role == .user
        let label = isUser ? "You" : providerLabel()

        return TranscriptRowViewModel(
            id: rowID,
            role: message.role,
            headerLabel: label,
            content: cleanContent,  // Use cleaned content
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: mergedArtifacts
        )
    }

    private func providerLabel() -> String {
        if !session.model.isEmpty { return session.model }
        return "Assistant"
    }

    // Kept for metadata mapping usage
    private func mapArtifactKind(_ lang: CodeLanguage) -> ArtifactKind {
        switch lang {
        case .json, .swift, .python, .javascript: return .code
        case .markdown, .text: return .text
        }
    }

    private func persistedRowID(_ id: UUID) -> String {
        "message:\(id.uuidString)"
    }

    private func streamingRowID(sessionID: UUID, generationID: UUID) -> String {
        "streaming:\(sessionID.uuidString):\(generationID.uuidString)"
    }
}

#if DEBUG
    #Preview("TranscriptCanvas • 20 messages + artifacts") {
        TranscriptCanvasView(
            rows: Canvas2PreviewFixtures.longTranscriptRows(messageCount: 20),
            streamingRow: nil
        )
        .frame(width: 900, height: 800)
    }

    #Preview("TranscriptCanvas • Long markdown + code") {
        let rows = [
            TranscriptRowViewModel(
                id: "message:\(Canvas2PreviewFixtures.IDs.assistant1.uuidString)",
                role: .assistant,
                headerLabel: "Assistant",
                content: Canvas2PreviewFixtures.markdownLongWithCode,
                isStreaming: false,
                generationID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
                artifacts: [Canvas2PreviewFixtures.codeFileArtifact()]
            )
        ]
        return TranscriptCanvasView(rows: rows, streamingRow: nil)
            .frame(width: 900, height: 800)
    }

    #Preview("TranscriptCanvas • Streaming overlay") {
        @Previewable @State var isStreaming = true
        let rows = Canvas2PreviewFixtures.shortTranscriptRows()
        let streaming = isStreaming ? Canvas2PreviewFixtures.streamingRow() : nil
        return TranscriptCanvasView(rows: rows, streamingRow: streaming)
            .frame(width: 900, height: 800)
    }
#endif
