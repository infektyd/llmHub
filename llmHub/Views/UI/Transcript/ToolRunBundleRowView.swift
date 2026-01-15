//
//  ToolRunBundleRowView.swift
//  llmHub
//
//  Grouped tool run bundle row for transcript rendering.
//

import SwiftUI

struct ToolRunBundleRowView: View {
    let bundle: ToolRunBundleViewModel

    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 10 : 12) {
            header

            VStack(alignment: .leading, spacing: uiCompactMode ? 10 : 12) {
                ForEach(bundle.toolRows) { row in
                    ToolResultCardView(viewModel: row)
                }
            }
            .padding(.leading, uiCompactMode ? 6 : 8)
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.system(size: 13 * uiScale, weight: .semibold))
                .foregroundStyle(statusTint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Run Bundle")
                    .font(.system(size: 13 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 6) {
                    statusBadge

                    Text("\(bundle.toolCount) tool\(bundle.toolCount == 1 ? "" : "s")")
                        .font(.system(size: 11 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(size: 11 * uiScale, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(statusTint.opacity(0.18))
            }
            .foregroundStyle(statusTint)
    }

    private var statusLabel: String {
        switch bundle.status {
        case .running: return "Running"
        case .success: return "Succeeded"
        case .partialFailure: return "Partial"
        case .failure: return "Failed"
        }
    }

    private var statusTint: Color {
        switch bundle.status {
        case .running: return AppColors.accentSecondary
        case .success: return AppColors.success
        case .partialFailure: return .orange
        case .failure: return .red
        }
    }
}
