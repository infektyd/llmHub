//
//  TranscriptRow.swift
//  llmHub
//
//  Single row in the transcript canvas
//  Role label (left for assistant, right for user) + body text
//  Uses Textual for rendering attributed/markdown content
//

import SwiftUI

// Note: Textual will be imported once package is added

/// A single transcript row with role label and content.
/// No bubble design - flat canvas style
struct TranscriptRow: View {
    let viewModel: TranscriptRowViewModel
    var onRegenerate: ((UUID) -> Void)?
    var onEdit: ((String) -> Void)?

    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: roleAlignment, spacing: uiCompactMode ? 6 : 8) {
            // Role label
            roleLabel

            // Content body
            if case .toolRunBundle(let bundle) = viewModel.kind {
                ToolRunBundleRowView(bundle: bundle)
            } else if viewModel.role == .tool {
                ToolResultCardView(viewModel: viewModel)
            } else if !viewModel.content.isEmpty {
                if isUser {
                    TextualMessageView(
                        content: viewModel.content,
                        isStreaming: viewModel.isStreaming,
                        role: viewModel.role,
                        generationID: viewModel.generationID,
                        messageID: messageID,
                        onReply: { chatVM.replyToMessageID = messageID },
                        onRegenerate: nil,
                        onEdit: {
                            onEdit?(viewModel.content)
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.userBubble)
                    }
                    .frame(maxWidth: 520, alignment: .trailing)
                } else {
                    TextualMessageView(
                        content: viewModel.content,
                        isStreaming: viewModel.isStreaming,
                        role: viewModel.role,
                        generationID: viewModel.generationID,
                        messageID: messageID,
                        onReply: { chatVM.replyToMessageID = messageID },
                        onRegenerate: {
                            if let messageID {
                                onRegenerate?(messageID)
                            }
                        }
                    )
                    .frame(maxWidth: 700, alignment: frameAlignment)
                }
            }

            // Attachment chips for user messages
            if isUser && !viewModel.attachments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(viewModel.attachments) { chip in
                        TranscriptAttachmentChip(chip: chip)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Artifacts
            if !viewModel.artifacts.isEmpty {
                ForEach(viewModel.artifacts) { artifact in
                    // Tool results start collapsed, other artifacts start expanded
                    ArtifactCardView(payload: artifact, startExpanded: artifact.kind != .toolResult)
                }
            }

            // Reply count badge
            if viewModel.replyCount > 0 {
                replyCountBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay(alignment: isUser ? .topTrailing : .topLeading) {
            if isHovered && !viewModel.isStreaming {
                hoverActionBar
                    .padding(.top, -4)
            }
        }
    }

    // MARK: - Private Computed Properties

    private var isUser: Bool {
        viewModel.role == .user
    }

    private var messageID: UUID? {
        UUID(uuidString: viewModel.id)
    }

    private var roleAlignment: HorizontalAlignment {
        isUser ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        isUser ? .trailing : .leading
    }

    /// Resolved agent identity, if this message came from a known agent.
    private var agentIdentity: AgentIdentity? {
        guard let senderID = viewModel.senderAgentID,
              viewModel.role == .assistant else { return nil }
        return AgentIdentityRegistry.lookup(senderID, knownAgents: chatVM.discoveredAgents)
    }

    // MARK: - Hover Action Bar

    /// Floating action bar that appears on hover over a message row.
    private var hoverActionBar: some View {
        HStack(spacing: 4) {
            if isUser {
                Button {
                    onEdit?(viewModel.content)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Edit message")
            } else {
                Button {
                    if let uuid = messageUUIDFromID() {
                        onRegenerate?(uuid)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Regenerate response")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppColors.surface)
                .shadow(color: AppColors.shadowSmoke, radius: 4, x: 0, y: 2)
        }
    }

    /// Extracts a UUID from the view model's `id` field.
    /// Supports "message:{UUID}" format as well as bare UUID strings.
    private func messageUUIDFromID() -> UUID? {
        let id = viewModel.id
        if id.hasPrefix("message:") {
            let uuidStr = String(id.dropFirst("message:".count))
            return UUID(uuidString: uuidStr)
        }
        return UUID(uuidString: id)
    }

    private var roleLabel: some View {
        HStack(spacing: 6) {
            if isUser {
                Text(settingsManager.settings.userEmote)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(viewModel.headerLabel)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            } else if let identity = agentIdentity {
                // Agent avatar: emoji in colored circle
                ZStack {
                    Circle()
                        .fill(identity.color.opacity(0.18))
                        .frame(width: 18 * uiScale, height: 18 * uiScale)
                    Text(identity.emoji)
                        .font(.system(size: 10 * uiScale))
                }

                Text(identity.name)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(identity.color)

                // Role description
                if !identity.roleDescription.isEmpty {
                    Text("· \(identity.roleDescription)")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)
                }

                // Optional: streaming indicator
                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
            } else {
                Text(viewModel.headerLabel)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
            }

            // Reply indicator: show if this message is a reply
            if viewModel.parentMessageID != nil {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 10 * uiScale))
                    .foregroundStyle(AppColors.textTertiary)
            }

            if settingsManager.settings.showTokenCounts,
                let meta = viewModel.headerMetaText,
                !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Reply Count Badge

    private var replyCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 10 * uiScale))
            Text("\(viewModel.replyCount) \(viewModel.replyCount == 1 ? "reply" : "replies")")
                .font(.system(size: 11 * uiScale, weight: .medium))
        }
        .foregroundStyle(AppColors.accent.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(AppColors.accent.opacity(0.1))
        }
    }
}

#if DEBUG
    #Preview("TranscriptRow - Assistant") {
        TranscriptRow(
            viewModel: TranscriptRowViewModel(
                id: "row-assistant",
                role: .assistant,
                headerLabel: "Assistant",
                headerMetaText: "123t",
                content: Canvas2PreviewFixtures.markdownShort,
                isStreaming: false,
                generationID: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
                artifacts: []
            )
        )
        .environment(ChatViewModel.preview())
        .padding()
        .frame(width: 900)
    }

    #Preview("TranscriptRow - User") {
        TranscriptRow(
            viewModel: TranscriptRowViewModel(
                id: "row-user",
                role: .user,
                headerLabel: "You",
                headerMetaText: "≈42t",
                content: "Short user message aligned to the trailing edge.",
                isStreaming: false,
                generationID: nil,
                artifacts: []
            )
        )
        .environment(ChatViewModel.preview())
        .padding()
        .frame(width: 900)
    }

    #Preview("TranscriptRow - Code block") {
        TranscriptRow(
            viewModel: TranscriptRowViewModel(
                id: "row-code",
                role: .assistant,
                headerLabel: "Assistant",
                headerMetaText: nil,
                content: Canvas2PreviewFixtures.markdownLongWithCode,
                isStreaming: false,
                generationID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
                artifacts: []
            )
        )
        .environment(ChatViewModel.preview())
        .padding()
        .frame(width: 900)
    }

    #Preview("TranscriptRow - Ultra long wrapping") {
        TranscriptRow(
            viewModel: TranscriptRowViewModel(
                id: "row-long",
                role: .assistant,
                headerLabel: "Assistant",
                headerMetaText: nil,
                content: Canvas2PreviewFixtures.markdownVeryLong,
                isStreaming: false,
                generationID: UUID(uuidString: "99999999-8888-7777-6666-555555555555"),
                artifacts: []
            )
        )
        .environment(ChatViewModel.preview())
        .padding()
        .frame(width: 900)
    }
#endif
