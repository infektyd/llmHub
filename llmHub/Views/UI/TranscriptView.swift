//
//  TranscriptCanvasView.swift
//  llmHub
//
//  Central canvas transcript with no bubbles, just role labels + text
//  Uses Textual for rendering transcript content
//

import SwiftUI

// MARK: - Agent Avatar for Multi-Agent Streaming

/// Small avatar used in multi-agent response headers.
struct AgentAvatarView: View {
    let agentId: String
    var knownAgents: [Agent]
    @Environment(\.uiScale) private var uiScale

    private var identity: AgentIdentity {
        AgentIdentityRegistry.lookup(agentId, knownAgents: knownAgents)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(identity.color.opacity(0.18))
                .frame(width: 18 * uiScale, height: 18 * uiScale)
            Text(identity.emoji)
                .font(.system(size: 10 * uiScale))
        }
    }
}

// MARK: - Elapsed Time Label

/// Displays elapsed time since a given start date, updating every second.
/// Used to show streaming duration for multi-agent responses.
struct ElapsedTimeLabel: View {
    let startedAt: Date
    @State private var now: Date = Date()
    @State private var tickTask: Task<Void, Never>?

    var body: some View {
        Text(formattedElapsed)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppColors.textTertiary)
            .onAppear {
                tickTask = Task { @MainActor in
                    while !Task.isCancelled {
                        now = Date()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
            .onDisappear {
                tickTask?.cancel()
                tickTask = nil
            }
    }

    private var formattedElapsed: String {
        let seconds = Int(now.timeIntervalSince(startedAt))
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
    }
}

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
    /// Multi-agent concurrent streaming states (nil when not in group chat)
    let multiAgentResponses: [String: AgentResponseState]?

    var onRegenerate: ((UUID) -> Void)?
    var onEdit: ((String) -> Void)?

    @State private var scrollProxy: ScrollViewProxy?
    /// Tracks whether the user is pinned to the bottom of the transcript.
    /// When false, auto-scroll is disabled and a "Jump to latest" pill appears.
    @State private var isPinnedToBottom: Bool = true
    @Environment(\.composerHeight) private var composerHeight
    @Environment(\.uiCompactMode) private var uiCompactMode

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: uiCompactMode ? 16 : 24
                    ) {
                        ForEach(mergedRows) { rowVM in
                            threadedRow(rowVM)
                                .id(rowVM.id)
                        }

                        // Multi-agent typing indicators appear below the transcript
                        if let responses = multiAgentResponses, !responses.isEmpty {
                            multiAgentIndicators(responses)
                        }

                        // Bottom anchor marker — LazyVStack only materializes this
                        // when it scrolls into view, so onAppear/onDisappear
                        // accurately detect whether the user is at the bottom.
                        Color.clear
                            .frame(height: 1)
                            .id("scroll-bottom-anchor")
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPinnedToBottom = true
                                }
                            }
                            .onDisappear {
                                isPinnedToBottom = false
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
                    if isPinnedToBottom {
                        scrollToBottom()
                    }
                }
                .onChange(of: multiAgentResponses?.count) { _, _ in
                    if isPinnedToBottom {
                        scrollToBottom()
                    }
                }

                // "Jump to latest" floating pill — appears when user scrolls up
                if !isPinnedToBottom {
                    jumpToLatestButton
                        .padding(.trailing, 16)
                        .padding(.bottom, composerHeight + 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    /// Floating pill button to jump back to the latest messages.
    private var jumpToLatestButton: some View {
        Button {
            isPinnedToBottom = true
            scrollToBottom()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("Jump to latest")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(AppColors.accent)
                    .shadow(color: AppColors.shadowSmoke, radius: 8, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
    }

    /// Renders typing indicators and completed streaming rows for concurrent multi-agent chat.
    @ViewBuilder
    private func multiAgentIndicators(_ responses: [String: AgentResponseState]) -> some View {
        VStack(spacing: 12) {
            // Render in @mention order (orderIndex)
            ForEach(responses.values.sorted(by: { $0.orderIndex < $1.orderIndex })) { response in
                multiAgentResponseRow(response)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: responses.count)
        .id("multi-agent-section")
    }

    /// Renders a single agent response row during concurrent streaming.
    @ViewBuilder
    private func multiAgentResponseRow(_ response: AgentResponseState) -> some View {
        let identity = AgentIdentityRegistry.lookup(response.id, knownAgents: [])
        VStack(alignment: .leading, spacing: 6) {
            // Role label row with avatar, name, role description, status
            HStack(spacing: 6) {
                AgentAvatarView(agentId: response.id, knownAgents: [])
                Text(identity.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(identity.color)

                // Role description subtitle
                if !identity.roleDescription.isEmpty {
                    Text("· \(identity.roleDescription)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }

                statusBadge(for: response.status)

                // Elapsed time while streaming
                if case .streaming = response.status, let startedAt = response.startedAt {
                    ElapsedTimeLabel(startedAt: startedAt)
                }

                // Completed timestamp
                if case .complete = response.status, let completedAt = response.completedAt {
                    Text(completedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            // Content or typing indicator
            Group {
                if case .queued = response.status {
                    Text("Waiting...")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 12)
                } else if case .thinking = response.status {
                    AgentTypingIndicator(agentID: response.id, knownAgents: [])
                } else if case .streaming = response.status {
                    if response.content.isEmpty {
                        // Content hasn't arrived yet — show minimal placeholder
                        Text("…")
                            .font(.body)
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: 700, alignment: .leading)
                    } else {
                        TextualMessageView(
                            content: response.content,
                            isStreaming: true,
                            role: .assistant,
                            generationID: nil,
                            messageID: nil,
                            onReply: nil
                        )
                        .frame(maxWidth: 700, alignment: .leading)
                    }
                } else if case .complete = response.status {
                    TextualMessageView(
                        content: response.content,
                        isStreaming: false,
                        role: .assistant,
                        generationID: nil,
                        messageID: nil,
                        onReply: nil
                    )
                    .frame(maxWidth: 700, alignment: .leading)
                } else if case .error(let message) = response.status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: response.status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Status badge for an agent response
    @ViewBuilder
    private func statusBadge(for status: AgentResponseState.Status) -> some View {
        switch status {
        case .thinking, .streaming:
            ProgressView()
                .controlSize(.mini)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))
        case .queued:
            EmptyView()
        }
    }

    private func agentDisplayName(_ agentId: String) -> String {
        AgentIdentityRegistry.lookup(agentId, knownAgents: []).name
    }

    private func agentColor(_ agentId: String) -> Color {
        AgentIdentityRegistry.lookup(agentId, knownAgents: []).color
    }

    /// Renders a row with threading indentation and connector line if it is a reply.
    @ViewBuilder
    private func threadedRow(_ rowVM: TranscriptRowViewModel) -> some View {
        if rowVM.parentMessageID != nil {
            HStack(alignment: .top, spacing: 0) {
                // Connector line
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(AppColors.accent.opacity(0.3))
                    .frame(width: 2)
                    .padding(.horizontal, 12)
                // Indented reply content
                TranscriptRow(
                    viewModel: rowVM,
                    onRegenerate: onRegenerate,
                    onEdit: onEdit
                )
            }
            .padding(.leading, 28)
        } else {
            TranscriptRow(
                viewModel: rowVM,
                onRegenerate: onRegenerate,
                onEdit: onEdit
            )
        }
    }

    private var mergedRows: [TranscriptRowViewModel] {
        // When in group chat mode, don't show the single streaming overlay
        if multiAgentResponses?.isEmpty == false { return rows }
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
    @Environment(\.modelContext) private var modelContext

    private var messages: [ChatMessageEntity] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        TranscriptCanvasView(
            rows: persistedRows,
            streamingRow: streamingOverlayRow,
            multiAgentResponses: multiAgentStreamingResponses,
            onRegenerate: { messageID in
                chatVM.requestRegeneration(
                    messageID: messageID,
                    session: session,
                    modelContext: modelContext
                )
            },
            onEdit: { content in
                chatVM.composerDraft = content
            }
        )
    }

    /// Returns multi-agent responses if we're in a concurrent group chat stream.
    private var multiAgentStreamingResponses: [String: AgentResponseState]? {
        guard !chatVM.multiAgentResponses.isEmpty else { return nil }
        return chatVM.multiAgentResponses
    }

    private var persistedRows: [TranscriptRowViewModel] {
        let toolCallArgumentsByID = buildToolCallArgumentsIndex(messages)
        let replyCountIndex = buildReplyCountIndex(messages)
        return buildTranscriptRows(messages, toolCallArgumentsByID: toolCallArgumentsByID, replyCountIndex: replyCountIndex)
    }

    private func buildReplyCountIndex(_ messages: [ChatMessageEntity]) -> [String: Int] {
        var index: [String: Int] = [:]
        for entity in messages {
            if let parentID = entity.parentMessageID {
                index[parentID.uuidString, default: 0] += 1
            }
        }
        return index
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
        toolCallArgumentsByID: [String: String],
        replyCountIndex: [String: Int]
    ) -> TranscriptRowViewModel {
        mapToViewModel(
            entity.asDomain(),
            isStreaming: false,
            rowID: persistedRowID(entity.id),
            toolCallArgumentsByID: toolCallArgumentsByID,
            replyCountIndex: replyCountIndex
        )
    }

    /// Resolves a display identity for an agent ID from the discovered agents list.
    private func resolveAgent(for agentID: String) -> Agent? {
        return chatVM.discoveredAgents.first { $0.id == agentID }
    }

    // Map a domain ChatMessage into a TranscriptRowViewModel with streaming/rowID context
    private func mapToViewModel(
        _ message: ChatMessage,
        isStreaming: Bool,
        rowID: UUID,
        toolCallArgumentsByID: [String: String],
        replyCountIndex: [String: Int] = [:]
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

        let replyCount = replyCountIndex[message.id.uuidString] ?? 0

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
            toolCallArguments: toolCallArguments,
            parentMessageID: message.parentMessageID,
            replyCount: replyCount,
            senderAgentID: message.senderAgentID
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
            let size = attrs[.size] as? Int {
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
        toolCallArgumentsByID: [String: String],
        replyCountIndex: [String: Int]
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
                let assistantRow = mapToViewModel(
                    entity, toolCallArgumentsByID: toolCallArgumentsByID, replyCountIndex: replyCountIndex)
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

            rows.append(mapToViewModel(entity, toolCallArgumentsByID: toolCallArgumentsByID, replyCountIndex: replyCountIndex))
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
        case .assistant:
            if let senderAgentID = message.senderAgentID {
                let agent = resolveAgent(for: senderAgentID)
                return agent?.name ?? senderAgentID.capitalized
            }
            return "Assistant"
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
