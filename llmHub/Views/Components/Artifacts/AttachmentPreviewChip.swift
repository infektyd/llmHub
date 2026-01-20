//
//  AttachmentPreviewChip.swift
//  llmHub
//
//  Created by Assistant on 2026-01-02.
//

import Foundation
import SwiftUI

struct AttachmentPreviewChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    private var formattedSize: String? {
        let values = try? attachment.url.resourceValues(forKeys: [URLResourceKey.fileSizeKey])
        guard let byteSize = values?.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image(systemName: attachment.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if let formattedSize {
                        Text(formattedSize)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .frame(width: 160, height: 56, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppColors.surface)
                .shadow(color: AppColors.shadowSmoke, radius: 2, x: 0, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
    }
}
