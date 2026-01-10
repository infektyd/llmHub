//
//  TranscriptCanvasView.swift
//  llmHub
//
//  Central canvas transcript with no bubbles, just role labels + text
//  Uses Textual for rendering transcript content
//

import SwiftUI

// Note: Textual will be imported once package is added

// MARK: - Composer Height Environment

/// Environment key for injecting composer height to enable bottom safe area inset
private struct ComposerHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 100  // Reasonable fallback
}

extension EnvironmentValues {
    var composerHeight: CGFloat {
        get { self[ComposerHeightKey.self] }
        set { self[ComposerHeightKey.self] = newValue }
    }
}

/// PreferenceKey for measuring composer height from RootView
struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Canvas view for displaying the conversation transcript
/// No message bubbles - flat design with role labels
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
                .padding(.horizontal, uiCompactMode ? 16 : 24)
                .padding(.vertical, uiCompactMode ? 16 : 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserve space for the overlaid composer bar
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

// MARK: - SwiftData container (production integration)

/// Container view that bridges SwiftData + streaming overlay into a plain `TranscriptCanvasView`.
struct TranscriptCanvasSessionView: View {
    let session: ChatSessionEntity

    @Environment(ChatViewModel.self) private var chatVM
    @EnvironmentObject private var modelRegistry: ModelRegistry

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

    // swiftlint:disable:next function_body_length
    private func mapToViewModel(_ message: ChatMessage, isStreaming: Bool, rowID: String)
        -> TranscriptRowViewModel {
        let headerMetaText = tokenMetaText(for: message)

        // Handle tool result messages as compact artifact cards
        if message.role == .tool {
            let meta = message.toolResultMeta
            let toolName = meta?.toolName ?? inferredToolName(from: message.content) ?? "Tool"
            let statusEmoji = (meta?.success ?? true) ? "🔧" : "❌"
            let status: ArtifactStatus = (meta?.success ?? true) ? .success : .failure

            // Truncate preview for compact display
            let previewLines = message.content.components(separatedBy: "\n")
            let maxPreviewLines = 50
            let truncatedPreview = previewLines.prefix(maxPreviewLines).joined(separator: "\n")
            let wasTruncated = previewLines.count > maxPreviewLines || (meta?.truncated ?? false)
            let truncationNote = wasTruncated ? "\n... (\(previewLines.count) lines total)" : ""

            let toolArtifact = ArtifactPayload(
                id: message.id,
                title: "\(statusEmoji) \(toolName)",
                kind: .toolResult,
                status: status,
                previewText: truncatedPreview + truncationNote,
                actions: [.copy],
                metadata: meta?.metadata
            )

            return TranscriptRowViewModel(
                id: rowID,
                role: message.role,
                headerLabel: "\(statusEmoji) \(toolName)",
                headerMetaText: headerMetaText,
                content: "",  // Empty content - card renders the result
                isStreaming: isStreaming,
                generationID: message.generationID,
                artifacts: [toolArtifact]
            )
        }

        // Runtime artifact detection for non-tool messages
        let detection = ArtifactService.detect(from: message.content, messageID: message.id)
        let cleanContent = detection.cleanContent

        // Merge detected artifacts with persisted metadata artifacts
        var mergedArtifacts = detection.artifacts

        let persistedArtifacts = message.artifactMetadatas.map { meta in
            ArtifactPayload(
                id: meta.id,
                title: meta.filename,
                kind: mapArtifactKind(meta.language),
                status: .success,
                previewText: meta.content,
                actions: [.copy, .open],
                metadata: nil
            )
        }

        mergedArtifacts.append(contentsOf: persistedArtifacts)

        let isUser = message.role == .user
        let label: String
        if isUser {
            label = "You"
        } else {
            let emoji = (session.afmEmoji ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedEmoji = emoji.isEmpty ? "🤖" : emoji
            label = "\(resolvedEmoji) \(providerLabel())"
        }

        return TranscriptRowViewModel(
            id: rowID,
            role: message.role,
            headerLabel: label,
            headerMetaText: headerMetaText,
            content: cleanContent,  // Use cleaned content
            isStreaming: isStreaming,
            generationID: message.generationID,
            artifacts: mergedArtifacts
        )
    }

    private func tokenMetaText(for message: ChatMessage) -> String? {
        // Prefer real token usage when available; otherwise fall back to an estimate.
        if let usage = message.tokenUsage {
            let total = usage.inputTokens + usage.outputTokens + usage.cachedTokens
            return "\(total)t"
        }
        // If the message is empty, avoid showing a noisy estimate.
        guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "≈\(message.estimatedTokens)t"
    }

    private func inferredToolName(from content: String) -> String? {
        guard let data = content.data(using: .utf8) else { return nil }
        guard let any = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = any as? [String: Any] else { return nil }

        if let toolName = dict["toolName"] as? String, !toolName.isEmpty { return toolName }
        if let toolName = dict["tool_name"] as? String, !toolName.isEmpty { return toolName }
        if let toolName = dict["name"] as? String, !toolName.isEmpty { return toolName }
        return nil
    }

    private func providerLabel() -> String {
        let models = modelRegistry.models(for: session.providerID)
        if let displayName = models.first(where: { $0.id == session.model })?.displayName,
            !displayName.isEmpty {
            return cleanModelName(displayName)
        }

        if !session.model.isEmpty { return cleanModelName(session.model) }
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
                headerMetaText: "123t",
                content: Canvas2PreviewFixtures.markdownLongWithCode,
                isStreaming: false,
                generationID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
                artifacts: [Canvas2PreviewFixtures.codeFileArtifact()]
            )
        ]
        TranscriptCanvasView(rows: rows, streamingRow: nil)
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
