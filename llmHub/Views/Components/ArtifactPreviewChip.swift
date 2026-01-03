//
//  ArtifactPreviewChip.swift
//  llmHub
//
//  Created by User on 2026-01-02.
//

import SwiftUI

struct ArtifactPreviewChip: View {
    let artifact: Artifact
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)

            Text(artifact.title)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)  // Capsular
                .fill(AppColors.surface)
                .shadow(color: AppColors.shadowSmoke, radius: 2, x: 0, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
    }

    private var iconName: String {
        switch artifact.kind {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .image: return "photo"
        default: return "doc"
        }
    }
}
