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

    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: roleAlignment, spacing: uiCompactMode ? 6 : 8) {
            // Role label
            roleLabel

            // Content body
            if viewModel.role == .tool {
                ToolResultCardView(viewModel: viewModel)
            } else if !viewModel.content.isEmpty {
                if isUser {
                    TextualMessageView(
                        content: viewModel.content,
                        isStreaming: viewModel.isStreaming,
                        role: viewModel.role,
                        generationID: viewModel.generationID
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
                        generationID: viewModel.generationID
                    )
                    .frame(maxWidth: 700, alignment: frameAlignment)
                }
            }

            // Artifacts
            if !viewModel.artifacts.isEmpty {
                ForEach(viewModel.artifacts) { artifact in
                    // Tool results start collapsed, other artifacts start expanded
                    ArtifactCardView(payload: artifact, startExpanded: artifact.kind != .toolResult)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - Private Computed Properties

    private var isUser: Bool {
        viewModel.role == .user
    }

    private var roleAlignment: HorizontalAlignment {
        isUser ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        isUser ? .trailing : .leading
    }

    private var roleLabel: some View {
        HStack(spacing: 6) {
            if isUser {
                Text(settingsManager.settings.userEmote)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(viewModel.headerLabel)
                    .font(
                        .system(
                            size: 12 * uiScale,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text(viewModel.headerLabel)
                    .font(
                        .system(
                            size: 12 * uiScale,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(AppColors.textSecondary)

                // Optional: visual indicator for streaming
                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
            }

            if settingsManager.settings.showTokenCounts,
                let meta = viewModel.headerMetaText,
                !meta.isEmpty {
                Text(meta)
                    .font(
                        .system(
                            size: 11 * uiScale,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(AppColors.textTertiary)
            }
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
        .padding()
        .frame(width: 900)
    }
#endif
