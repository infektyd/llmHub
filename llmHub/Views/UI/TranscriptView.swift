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

        // Extract attachment info for user messages
        let attachmentChips: [AttachmentChipInfo] = message.attachments.map { attachment in
            AttachmentChipInfo(
                id: attachment.id,
                filename: attachment.filename,
                mimeType: mimeType(for: attachment.type),
                byteSize: fileSize(for: attachment),
                typeIcon: attachment.type.icon
            )
        }

        return TranscriptRowViewModel(
            id: rowID.uuidString,
            role: message.role,
            headerLabel: headerLabel(for: message),
            headerMetaText: headerMetaText(for: message),
            content: message.content,
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: artifacts(for: message),
            attachments: attachmentChips,
            toolCallID: message.toolCallID,
            toolResultMeta: message.toolResultMeta,
            toolCallArguments: toolCallArguments
        )
    }

    private func mimeType(for type: AttachmentType) -> String {
        switch type {
        case .image: return "image/*"
        case .pdf: return "application/pdf"
        case .text: return "text/plain"
        case .code: return "text/x-source"
        case .other: return "application/octet-stream"
        }
    }

    private func fileSize(for attachment: Attachment) -> Int {
        // Best-effort size from file attributes, fallback to preview text length
        if let attrs = try? FileManager.default.attributesOfItem(atPath: attachment.url.path),
            let size = attrs[.size] as? Int
        {
            return size
        }
        return attachment.previewText?.utf8.count ?? 0
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
                !toolCalls.isEmpty
            {
                let toolCallIDs = toolCalls.map { $0.id }.filter { !$0.isEmpty }
                let assistantRow = mapToViewModel(
                    entity, toolCallArgumentsByID: toolCallArgumentsByID)
                rows.append(assistantRow)
                if toolCallIDs.count == toolCalls.count,
                    let bundleResult = buildToolRunBundleRow(
                        parentEntity: entity,
                        startIndex: index + 1,
                        expectedToolCallIDs: toolCallIDs,
                        messages: messages,
                        toolCallArgumentsByID: toolCallArgumentsByID
                    )
                {
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
        
        // Build lookup of tool messages by toolCallID over a bounded window
        // Window extends until: (1) next assistant with toolCalls, or (2) N messages, whichever is first
        let maxWindowSize = 50
        var toolMessagesByID: [String: (entity: ChatMessageEntity, index: Int)] = [:]
        var cursor = startIndex
        var lastToolIndex = startIndex - 1
        
        while cursor < messages.count && cursor < startIndex + maxWindowSize {
            let nextEntity = messages[cursor]
            let nextMessage = nextEntity.asDomain()
            
            // Stop if we hit another assistant message with toolCalls
            if nextMessage.role == .assistant,
               let toolCalls = nextMessage.toolCalls,
               !toolCalls.isEmpty {
                break
            }
            
            // Collect tool messages that match expected IDs
            if nextMessage.role == .tool,
               let toolCallID = nextMessage.toolCallID,
               expectedToolCallIDSet.contains(toolCallID) {
                // Store first occurrence only (in case of duplicates)
                if toolMessagesByID[toolCallID] == nil {
                    toolMessagesByID[toolCallID] = (nextEntity, cursor)
                    lastToolIndex = cursor
                }
            }
            
            cursor += 1
        }
        
        // Assemble bundle rows by matching expected toolCallIDs in order
        var toolRows: [TranscriptRowViewModel] = []
        var matchedIDs = Set<String>()
        
        for toolCallID in expectedToolCallIDs {
            if let (entity, _) = toolMessagesByID[toolCallID] {
                let message = entity.asDomain()
                toolRows.append(
                    mapToViewModel(
                        message,
                        isStreaming: false,
                        rowID: persistedRowID(entity.id),
                        toolCallArgumentsByID: toolCallArgumentsByID
                    )
                )
                matchedIDs.insert(toolCallID)
            }
        }
        
        // DEBUG diagnostics for bundling failures
        if toolRows.isEmpty {
            #if DEBUG
            print("[TranscriptView] DEBUG: Bundling skipped for assistant message \(parentEntity.id) - assistant has \(expectedToolCallIDs.count) toolCalls but 0 matched tool results")
            #endif
            return nil
        }
        
        if matchedIDs.count != expectedToolCallIDSet.count {
            let missingIDs = expectedToolCallIDSet.subtracting(matchedIDs)
            #if DEBUG
            print("[TranscriptView] DEBUG: Bundling partial match for assistant message \(parentEntity.id) - expected \(expectedToolCallIDSet.count) tool results, found \(matchedIDs.count). Missing toolCallIDs: \(missingIDs.sorted())")
            #endif
        }
        
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
        // Return next index as one past the last tool message we consumed
        return ToolRunBundleBuildResult(bundleRow: bundleRow, nextIndex: lastToolIndex + 1)
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
                "size": "\(meta.sizeBytes) B",
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
        return UUID(
            uuid: (
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
