import SwiftUI

struct ArtifactDetailView: View {
    let artifact: ArtifactPayload
    let onComment: (String) -> Void

    @State private var commentText: String = ""
    @State private var comments: [ArtifactComment] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.5)

            contentArea

            Divider().opacity(0.5)

            commentsArea

            Divider().opacity(0.5)

            commentInputBar
        }
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: uiCompactMode ? 10 : 12) {
            Image(systemName: artifact.kind.icon)
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.accent)

            Text(artifact.title)
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(uiCompactMode ? 7 : 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.backgroundSecondary)
                    }
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, uiCompactMode ? 14 : 16)
        .padding(.vertical, uiCompactMode ? 12 : 14)
    }

    private var contentArea: some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: uiCompactMode ? 10 : 12) {
                lineNumbers

                Divider()
                    .opacity(0.35)

                Text(artifact.previewText)
                    .font(.system(size: 13 * uiScale, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(uiCompactMode ? 14 : 16)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.surface)
        }
        .padding(uiCompactMode ? 12 : 14)
    }

    private var lineNumbers: some View {
        let count = max(1, artifactLines.count)
        return VStack(alignment: .trailing, spacing: 2) {
            ForEach(1...count, id: \.self) { index in
                Text("\(index)")
                    .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.top, 1)
    }

    private var commentsArea: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 10 : 12) {
            HStack {
                Text("Comments")
                    .font(.system(size: 13 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if !comments.isEmpty {
                    Text("\(comments.count)")
                        .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(AppColors.backgroundSecondary)
                        }
                }
            }

            if comments.isEmpty {
                Text("No comments yet")
                    .font(.system(size: 12 * uiScale))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: uiCompactMode ? 8 : 10) {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.text)
                                    .font(.system(size: 13 * uiScale))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .textSelection(.enabled)

                                Text(comment.createdAt, style: .time)
                                    .font(.system(size: 11 * uiScale, design: .monospaced))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .padding(uiCompactMode ? 10 : 12)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppColors.backgroundSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: uiCompactMode ? 160 : 220)
            }
        }
        .padding(.horizontal, uiCompactMode ? 14 : 16)
        .padding(.vertical, uiCompactMode ? 12 : 14)
    }

    private var commentInputBar: some View {
        HStack(spacing: uiCompactMode ? 10 : 12) {
            TextField("Comment on this artifact…", text: $commentText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .font(.system(size: 13 * uiScale))
                .padding(uiCompactMode ? 10 : 12)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.backgroundSecondary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.06), lineWidth: 1)
                }

            Button {
                submitComment()
            } label: {
                Text("Send")
                    .font(.system(size: 13 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, uiCompactMode ? 12 : 14)
                    .padding(.vertical, uiCompactMode ? 10 : 12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColors.accent.opacity(canSubmit ? 0.25 : 0.12))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, uiCompactMode ? 14 : 16)
        .padding(.vertical, uiCompactMode ? 12 : 14)
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var artifactLines: [String] {
        // Preserve empty lines for stable line numbering.
        artifact.previewText
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map(String.init)
    }

    private func submitComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let comment = ArtifactComment(text: trimmed)
        comments.append(comment)
        commentText = ""

        onComment(trimmed)
    }
}

#if DEBUG
#Preview("ArtifactDetailView") {
    ArtifactDetailView(
        artifact: ArtifactPayload(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            title: "Code Snippet (swift)",
            kind: .code,
            status: .success,
            previewText: Canvas2PreviewFixtures.markdownLongWithCode,
            actions: [.copy, .open],
            metadata: ["language": "swift"]
        ),
        onComment: { _ in }
    )
    .frame(width: 900, height: 700)
    .padding()
}
#endif
