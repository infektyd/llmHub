//
//  TranscriptAttachmentChip.swift
//  llmHub
//
//  Displays a compact attachment chip in transcript rows for persisted attachments.
//

import SwiftUI

/// A compact chip showing an attachment's filename and size in transcript rows.
struct TranscriptAttachmentChip: View {
    let chip: AttachmentChipInfo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: chip.typeIcon)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)

            Text(chip.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Text(chip.formattedSize)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.surface.opacity(0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
        }
    }
}

#if DEBUG
    #Preview("TranscriptAttachmentChip") {
        VStack(spacing: 12) {
            TranscriptAttachmentChip(
                chip: AttachmentChipInfo(
                    id: UUID(),
                    filename: "screenshot.png",
                    mimeType: "image/png",
                    byteSize: 45_234,
                    typeIcon: "photo"
                ))

            TranscriptAttachmentChip(
                chip: AttachmentChipInfo(
                    id: UUID(),
                    filename: "document.pdf",
                    mimeType: "application/pdf",
                    byteSize: 1_234_567,
                    typeIcon: "doc.richtext"
                ))

            TranscriptAttachmentChip(
                chip: AttachmentChipInfo(
                    id: UUID(),
                    filename: "code.swift",
                    mimeType: "text/x-swift",
                    byteSize: 2048,
                    typeIcon: "curlybraces"
                ))
        }
        .padding()
        .background(AppColors.backgroundPrimary)
    }
#endif
