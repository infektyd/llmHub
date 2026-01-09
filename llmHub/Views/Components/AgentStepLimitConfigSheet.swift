//
//  AgentStepLimitConfigSheet.swift
//  llmHub
//

import SwiftUI

struct AgentStepLimitConfigSheet: View {
    let mode: ChatViewModel.StepLimitConfigMode
    @Binding var additionalSteps: Int
    @Binding var defaultMaxIterations: Int
    let stopReason: AgentStopReason?

    let onCancel: () -> Void
    let onApplyContinue: () -> Void
    let onApplyDefault: () -> Void

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            if let stopReason {
                Text(description(for: stopReason))
                    .font(.system(size: 12 * uiScale))
                    .foregroundStyle(AppColors.textSecondary)
            }

            switch mode {
            case .continueRun:
                Stepper(value: $additionalSteps, in: AgentSettings.minMaxIterations...AgentSettings.maxMaxIterations) {
                    Text("Additional steps: \(additionalSteps)")
                        .font(.system(size: 12 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                }

            case .changeDefault:
                Stepper(value: $defaultMaxIterations, in: AgentSettings.minMaxIterations...AgentSettings.maxMaxIterations) {
                    Text("Default max iterations: \(defaultMaxIterations)")
                        .font(.system(size: 12 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Button("Apply") {
                    switch mode {
                    case .continueRun:
                        onApplyContinue()
                    case .changeDefault:
                        onApplyDefault()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var title: String {
        switch mode {
        case .continueRun: return "Continue run"
        case .changeDefault: return "Change default limit"
        }
    }

    private func description(for reason: AgentStopReason) -> String {
        switch reason {
        case .iterationLimitReached(let limit, let used):
            return "This run hit the limit of \(limit) tool steps (used \(used))."
        }
    }
}
