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

/// A single transcript row with role label and content
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
                    isStreaming: viewModel.isStreaming
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
