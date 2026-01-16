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
        let toolCallArgumentsByID = buildToolCallArgumentsIndex(messages)
        return buildTranscriptRows(messages, toolCallArgumentsByID: toolCallArgumentsByID)
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
                rowID: streamingRowID(sessionID: session.id, generationID: generationID),
                toolCallArgumentsByID: [:]
            )
        }

        return mapToViewModel(
            streaming,
            isStreaming: true,
            rowID: persistedRowID(streaming.id),
            toolCallArgumentsByID: [:]
        )
    }

    private func mapToViewModel(
        _ entity: ChatMessageEntity,
        toolCallArgumentsByID: [String: String]
    ) -> TranscriptRowViewModel {
        mapToViewModel(
            entity.asDomain(),
            isStreaming: false,
            rowID: persistedRowID(entity.id),
            toolCallArgumentsByID: toolCallArgumentsByID
        )
    }

    // Map a domain ChatMessage into a TranscriptRowViewModel with streaming/rowID context
    private func mapToViewModel(
        _ message: ChatMessage,
        isStreaming: Bool,
        rowID: UUID,
        toolCallArgumentsByID: [String: String]
    ) -> TranscriptRowViewModel {
        let toolCallArguments = message.toolCallID.flatMap { toolCallArgumentsByID[$0] }
        return TranscriptRowViewModel(
            id: rowID.uuidString,
            role: message.role,
            headerLabel: headerLabel(for: message),
            headerMetaText: headerMetaText(for: message),
            content: message.content,
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: artifacts(for: message),
            toolCallID: message.toolCallID,
            toolResultMeta: message.toolResultMeta,
            toolCallArguments: toolCallArguments
        )
    }

    private func buildToolCallArgumentsIndex(_ messages: [ChatMessageEntity]) -> [String: String] {
        messages.reduce(into: [:]) { partialResult, entity in
            let message = entity.asDomain()
            guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else { return }
            for call in toolCalls {
                partialResult[call.id] = call.input
            }
        }
    }

    private struct ToolRunBundleBuildResult {
        let bundleRow: TranscriptRowViewModel
        let nextIndex: Int
    }

    private func buildTranscriptRows(
        _ messages: [ChatMessageEntity],
        toolCallArgumentsByID: [String: String]
    ) -> [TranscriptRowViewModel] {
        var rows: [TranscriptRowViewModel] = []
        var index = 0
        while index < messages.count {
            let entity = messages[index]
            let message = entity.asDomain()
            if message.role == .assistant,
               let toolCalls = message.toolCalls,
               !toolCalls.isEmpty {
                let toolCallIDs = toolCalls.map { $0.id }.filter { !$0.isEmpty }
                let assistantRow = mapToViewModel(entity, toolCallArgumentsByID: toolCallArgumentsByID)
                rows.append(assistantRow)
                if toolCallIDs.count == toolCalls.count,
                   let bundleResult = buildToolRunBundleRow(
                    parentEntity: entity,
                    startIndex: index + 1,
                    expectedToolCallIDs: toolCallIDs,
                    messages: messages,
                    toolCallArgumentsByID: toolCallArgumentsByID
                   ) {
                    rows.append(bundleResult.bundleRow)
                    index = bundleResult.nextIndex
                    continue
                }
                index += 1
                continue
            }

            rows.append(mapToViewModel(entity, toolCallArgumentsByID: toolCallArgumentsByID))
            index += 1
        }
        return rows
    }

    private func buildToolRunBundleRow(
        parentEntity: ChatMessageEntity,
        startIndex: Int,
        expectedToolCallIDs: [String],
        messages: [ChatMessageEntity],
        toolCallArgumentsByID: [String: String]
    ) -> ToolRunBundleBuildResult? {
        let expectedToolCallIDSet = Set(expectedToolCallIDs)
        var toolRows: [TranscriptRowViewModel] = []
        var matchedIDs = Set<String>()
        var cursor = startIndex

        while cursor < messages.count {
            let nextEntity = messages[cursor]
            let nextMessage = nextEntity.asDomain()
            guard nextMessage.role == .tool else { break }
            guard let toolCallID = nextMessage.toolCallID else { return nil }
            guard expectedToolCallIDSet.contains(toolCallID) else { break }
            toolRows.append(
                mapToViewModel(
                    nextMessage,
                    isStreaming: false,
                    rowID: persistedRowID(nextEntity.id),
                    toolCallArgumentsByID: toolCallArgumentsByID
                )
            )
            matchedIDs.insert(toolCallID)
            cursor += 1
            if matchedIDs.count == expectedToolCallIDSet.count { break }
        }

        guard !toolRows.isEmpty else { return nil }

        let status = toolRunBundleStatus(
            expectedCount: expectedToolCallIDSet.count,
            toolRows: toolRows
        )
        let bundleID = "tool-bundle:\(parentEntity.id.uuidString)"
        let bundle = ToolRunBundleViewModel(
            id: bundleID,
            parentAssistantMessageID: parentEntity.id,
            title: "Run Bundle",
            label: parentEntity.toolRunLabel,
            toolRows: toolRows,
            expectedToolCount: expectedToolCallIDSet.count,
            status: status
        )
        let bundleRow = TranscriptRowViewModel(
            id: bundleID,
            kind: .toolRunBundle(bundle),
            role: .tool,
            headerLabel: "Tool Run",
            headerMetaText: nil,
            content: "",
            isStreaming: false,
            generationID: parentEntity.generationID,
            artifacts: []
        )
        return ToolRunBundleBuildResult(bundleRow: bundleRow, nextIndex: cursor)
    }

    private func toolRunBundleStatus(
        expectedCount: Int,
        toolRows: [TranscriptRowViewModel]
    ) -> ToolRunBundleStatus {
        guard toolRows.count >= expectedCount else { return .running }
        let successValues = toolRows.compactMap { $0.toolResultMeta?.success }
        guard successValues.count == toolRows.count else { return .running }
        if successValues.allSatisfy({ $0 }) { return .success }
        if successValues.allSatisfy({ !$0 }) { return .failure }
        return .partialFailure
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
