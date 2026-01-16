//
//  ToolRunBundleCardView.swift
//  llmHub
//
//  Collapsible bundle card for grouped tool runs in the transcript.
//

import SwiftUI

struct ToolRunBundleCardView: View {
    let bundle: ToolRunBundleViewModel

    @State private var isExpanded: Bool

    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    init(bundle: ToolRunBundleViewModel) {
        self.bundle = bundle
        let hasFailure = bundle.toolRows.contains { $0.toolResultMeta?.success == false }
        _isExpanded = State(initialValue: hasFailure)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 10 : 12) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: uiCompactMode ? 10 : 12) {
                    ForEach(bundle.toolRows) { row in
                        ToolResultCardView(viewModel: row)
                    }
                }
                .padding(.leading, uiCompactMode ? 6 : 8)
            }
        }
        .padding(uiCompactMode ? 12 : 16)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppColors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.displayTitle)
                    .font(.system(size: 13 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 6) {
                    Text(toolCountText)
                        .font(.system(size: 11 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)

                    statusIndicator
                }

                Text(bundle.displayRationale)
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
    }

    private var toolCountText: String {
        "\(bundle.toolCount) tool\(bundle.toolCount == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch bundle.status {
        case .running:
            if let runningText = runningStatusText {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(runningText)
                        .font(.system(size: 11 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.success)
                Text("Succeeded")
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Succeeded")
        case .partialFailure:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Partial failure")
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Partial failure")
        case .failure:
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(.red)
                Text("Failed")
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Failed")
        }
    }

    private var runningStatusText: String? {
        guard bundle.status == .running else { return nil }
        guard bundle.expectedToolCount > 0 else { return nil }
        let total = max(bundle.expectedToolCount, bundle.toolCount)
        return "\(bundle.toolCount)/\(total) running…"
    }

    private var borderTint: Color {
        if bundleHasAllFailures { return Color.red.opacity(0.35) }
        if bundleHasFailure { return Color.orange.opacity(0.35) }
        return AppColors.textPrimary.opacity(0.1)
    }

    private var bundleHasFailure: Bool {
        bundle.toolRows.contains { $0.toolResultMeta?.success == false }
    }

    private var bundleHasAllFailures: Bool {
        guard !bundle.toolRows.isEmpty else { return false }
        let successValues = bundle.toolRows.compactMap { $0.toolResultMeta?.success }
        return !successValues.isEmpty && successValues.allSatisfy { !$0 }
    }
}
