//
//  ArtifactCardView.swift
//  llmHub
//
//  Flat artifact card embedded in transcript
//  No glass effects - simple bordered card
//

import SwiftUI

/// Flat artifact card view for embedding in transcript
/// Flat artifact card view for embedding in transcript
struct ArtifactCardView: View {
    let payload: ArtifactPayload

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: iconForKind)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accent)

                Text(payload.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Content (if expanded)
            if isExpanded {
                if payload.kind == .code {
                    codeContent
                } else {
                    textContent
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
        }
        .frame(maxWidth: 700)
    }

    // MARK: - Private Views

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(payload.previewText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.backgroundPrimary.opacity(0.5))
                }
        }
    }

    private var textContent: some View {
        Text(payload.previewText)
            .font(.system(size: 14))
            .foregroundStyle(AppColors.textPrimary)
            .textSelection(.enabled)
    }

    private var iconForKind: String {
        switch payload.kind {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .image: return "photo"
        case .toolResult: return "gearshape.2"
        case .other: return "doc"
        }
    }
}
