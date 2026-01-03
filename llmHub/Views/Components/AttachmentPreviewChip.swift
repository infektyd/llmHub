//
//  AttachmentPreviewChip.swift
//  llmHub
//
//  Created by Assistant on 2026-01-02.
//

import SwiftUI

struct AttachmentPreviewChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.type.icon)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)

            Text(attachment.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.surface)
                .shadow(color: AppColors.shadowSmoke, radius: 2, x: 0, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
    }
}
