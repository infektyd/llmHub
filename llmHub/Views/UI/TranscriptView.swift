//
//  TranscriptCanvasView.swift
//  llmHub
//
//  Central canvas transcript with no bubbles, just role labels + text
//  Uses Textual for rendering transcript content
//

import SwiftUI

// MARK: - Composer Height Environment

private struct ComposerHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 100
}

extension EnvironmentValues {
    var composerHeight: CGFloat {
        get { self[ComposerHeightKey.self] }
        set { self[ComposerHeightKey.self] = newValue }
    }
}

struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Transcript Canvas

struct TranscriptCanvasView: View {
    let rows: [TranscriptRowViewModel]
    let streamingRow: TranscriptRowViewModel?

    @State private var scrollProxy: ScrollViewProxy?
    @Environment(\.composerHeight) private var composerHeight
    @Environment(\.uiCompactMode) private var uiCompactMode

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: uiCompactMode ? 16 : 24
                ) {
                    ForEach(mergedRows) { rowVM in
                        TranscriptRow(viewModel: rowVM)
                            .id(rowVM.id)
                    }
                }
                // 🔧 CRITICAL FIX — expand transcript width
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, uiCompactMode ? 16 : 24)
                .padding(.vertical, uiCompactMode ? 16 : 24)
            }
            // 🔧 CRITICAL FIX — expand scroll container width
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: composerHeight)
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

// MARK: - SwiftData Container

struct TranscriptCanvasSessionView: View {
    let session: ChatSessionEntity

    @Environment(ChatViewModel.self) private var chatVM

    private var messages: [ChatMessageEntity] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        TranscriptCanvasView(rows: persistedRows, streamingRow: streamingOverlayRow)
    }

    private var persistedRows: [TranscriptRowViewModel] {
        messages.map { mapToViewModel($0) }
    }

    private var streamingOverlayRow: TranscriptRowViewModel? {
        guard let streaming = chatVM.streamingDisplayMessage else { return nil }

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

        return mapToViewModel(streaming, isStreaming: true, rowID: persistedRowID(streaming.id))
    }

    private func mapToViewModel(_ entity: ChatMessageEntity) -> TranscriptRowViewModel {
        mapToViewModel(entity.asDomain(), isStreaming: false, rowID: persistedRowID(entity.id))
    }

    // Map a domain ChatMessage into a TranscriptRowViewModel with streaming/rowID context
    private func mapToViewModel(_ message: ChatMessage, isStreaming: Bool, rowID: UUID) -> TranscriptRowViewModel {
        TranscriptRowViewModel(
            id: rowID.uuidString,
            role: message.role,
            headerLabel: headerLabel(for: message),
            headerMetaText: headerMetaText(for: message),
            content: message.content,
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: artifacts(for: message)
        )
    }

    private func headerLabel(for message: ChatMessage) -> String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }

    private func headerMetaText(for message: ChatMessage) -> String? {
        // Approximate token count; UI decides whether to show it via settings
        let approxTokens = message.estimatedTokens
        return "≈\(approxTokens)t"
    }

    private func artifacts(for message: ChatMessage) -> [ArtifactPayload] {
        let metadatas = message.artifactMetadatas
        return metadatas.map { meta in
            let id = Canvas2StableIDs.artifactID(messageID: message.id, metadata: meta)
            let kind: ArtifactKind = {
                switch meta.language {
                case .text: return .text
                case .markdown: return .text
                default: return .code
                }
            }()
            var actions: [ArtifactAction] = [.copy]
            if meta.fileURL != nil { actions.append(.open) }
            let info: [String: String] = [
                "language": meta.language.displayName,
                "size": "\(meta.sizeBytes) B"
            ]
            return ArtifactPayload(
                id: id,
                title: meta.filename,
                kind: kind,
                status: .success,
                previewText: meta.content,
                actions: actions,
                metadata: info
            )
        }
    }

    // Generate stable IDs for persisted and streaming rows
    private func persistedRowID(_ id: UUID) -> UUID { id }

    private func streamingRowID(sessionID: UUID, generationID: UUID) -> UUID {
        // Derive a deterministic UUID by namespacing the session and generation IDs into a UUID v5-like hash.
        // Since we don't have a UUID v5 helper here, combine and hash into a UUID deterministically.
        let combined = sessionID.uuidString + ":" + generationID.uuidString
        var hasher = Hasher()
        hasher.combine(combined)
        let hash = hasher.finalize()
        // Expand the hash into a UUID by repeating/bit-casting deterministically
        let upper = UInt64(bitPattern: Int64(hash))
        let lower = UInt64(bitPattern: Int64(~hash))
        return UUID(uuid: (
            UInt8((upper >> 56) & 0xFF),
            UInt8((upper >> 48) & 0xFF),
            UInt8((upper >> 40) & 0xFF),
            UInt8((upper >> 32) & 0xFF),
            UInt8((upper >> 24) & 0xFF),
            UInt8((upper >> 16) & 0xFF),
            UInt8((upper >> 8) & 0xFF),
            UInt8(upper & 0xFF),
            UInt8((lower >> 56) & 0xFF),
            UInt8((lower >> 48) & 0xFF),
            UInt8((lower >> 40) & 0xFF),
            UInt8((lower >> 32) & 0xFF),
            UInt8((lower >> 24) & 0xFF),
            UInt8((lower >> 16) & 0xFF),
            UInt8((lower >> 8) & 0xFF),
            UInt8(lower & 0xFF)
        ))
    }
}
