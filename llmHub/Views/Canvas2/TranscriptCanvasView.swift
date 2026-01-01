//
//  TranscriptCanvasView.swift
//  llmHub
//
//  Central canvas transcript with no bubbles, just role labels + text
//  Uses Textual for rendering transcript content
//

import SwiftData
import SwiftUI
import CryptoKit

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
        guard let generationID = streaming.generationID else {
            // Defensive fallback: if we ever lack a generationID, still show the overlay to avoid hiding content.
            rows.append(mapToViewModel(streaming, isStreaming: true, rowID: persistedRowID(streaming.id)))
            return rows
        }

        let lastPersistedAssistantGenerationID: UUID? =
            messages.reversed().first(where: { $0.role == "assistant" || $0.role == "model" })?
            .generationID

        let shouldShowOverlay = lastPersistedAssistantGenerationID != generationID
#if DEBUG
        print(
            "DEBUG: Transcript merge overlay \(shouldShowOverlay ? "shown" : "hidden") (session: \(session.id), gen: \(generationID), lastPersistedGen: \(String(describing: lastPersistedAssistantGenerationID)))"
        )
#endif

        if shouldShowOverlay {
            rows.append(
                mapToViewModel(
                    streaming,
                    isStreaming: true,
                    rowID: streamingRowID(sessionID: session.id, generationID: generationID)
                )
            )
        }

        return rows
    }

    private func mapToViewModel(_ entity: ChatMessageEntity) -> TranscriptRowViewModel {
        mapToViewModel(entity.asDomain(), isStreaming: false, rowID: persistedRowID(entity.id))
    }

    private func mapToViewModel(_ message: ChatMessage, isStreaming: Bool, rowID: String)
        -> TranscriptRowViewModel
    {
        let isUser = message.role == .user
        let label = isUser ? "You" : providerLabel(for: message)

        // Map artifacts
        let artifacts = message.artifactMetadatas.map { meta in
            ArtifactPayload(
                id: stableArtifactID(messageID: message.id, metadata: meta),
                title: meta.filename,
                kind: mapArtifactKind(meta.language),
                status: .success,  // Assume success for past messages
                previewText: meta.content,
                actions: [.copy, .open],
                metadata: meta
            )
        }

        return TranscriptRowViewModel(
            id: rowID,
            role: message.role,
            headerLabel: label,
            content: message.content,
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: artifacts
        )
    }

    private func stableArtifactID(messageID: UUID, metadata: ArtifactMetadata) -> UUID {
        // Stable across recomputes so streaming updates don't invalidate past rows.
        // Hash: messageID + filename + language
        var hasher = SHA256()
        hasher.update(data: Data(messageID.uuidString.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(metadata.filename.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(metadata.language.rawValue.utf8))
        let digest = hasher.finalize()
        let bytes = Array(digest)
        let uuidBytes = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
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
                if let generationID = streaming.generationID {
                    proxy.scrollTo(
                        streamingRowID(sessionID: session.id, generationID: generationID),
                        anchor: .bottom
                    )
                } else {
                    proxy.scrollTo(persistedRowID(streaming.id), anchor: .bottom)
                }
            }
        } else if let lastMessage = messages.last {
            withAnimation {
                proxy.scrollTo(persistedRowID(lastMessage.id), anchor: .bottom)
            }
        }
    }

    private func persistedRowID(_ id: UUID) -> String {
        "message:\(id.uuidString)"
    }

    private func streamingRowID(sessionID: UUID, generationID: UUID) -> String {
        "streaming:\(sessionID.uuidString):\(generationID.uuidString)"
    }
}
