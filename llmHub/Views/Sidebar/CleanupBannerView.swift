//
//  CleanupBannerView.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import SwiftUI

/// A banner that appears when conversations are flagged for cleanup review.
struct CleanupBannerView: View {
    let flaggedCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.accent)

                Text(
                    "\(flaggedCount) conversation\(flaggedCount == 1 ? "" : "s") ready for cleanup"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bannerBackground)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppColors.accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
            )
            .glassEffect(
                GlassEffect.regular.tint(AppColors.accent.opacity(0.1)),
                in: .rect(cornerRadius: 10)
            )
    }
}

/// A small badge showing the cleanup count.
struct CleanupBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(AppColors.accent)
                )
        }
    }
}

// MARK: - Previews

#Preview("Cleanup Banner") {
    VStack(spacing: 20) {
        CleanupBannerView(flaggedCount: 5) {
            print("Tapped")
        }

        CleanupBannerView(flaggedCount: 1) {
            print("Tapped")
        }

        HStack {
            Text("Cleanup")
            CleanupBadge(count: 3)
        }
    }
    .padding()
    .frame(width: 300)
    .previewEnvironment()
}
