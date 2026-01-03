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

    var body: some View {
        VStack(alignment: roleAlignment, spacing: 8) {
            // Role label
            roleLabel

            // Content body
            if !viewModel.content.isEmpty {
                TextualMessageView(
                    content: viewModel.content,
                    isStreaming: viewModel.isStreaming,
                    role: viewModel.role,
                    generationID: viewModel.generationID
                )
                .frame(maxWidth: 700, alignment: frameAlignment)
            }

            // Artifacts
            if !viewModel.artifacts.isEmpty {
                ForEach(viewModel.artifacts) { artifact in
                    ArtifactCardView(payload: artifact)
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
                Text(viewModel.headerLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text(viewModel.headerLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                // Optional: visual indicator for streaming
                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
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
