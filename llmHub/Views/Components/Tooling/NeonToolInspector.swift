//
//  NeonToolInspector.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonToolInspector: View {
    @Binding var isVisible: Bool
    @Binding var toolExecution: ToolExecution?
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                Divider()
                    .background(theme.textPrimary.opacity(0.08))

                if let execution = toolExecution {
                    toolInfoSection(for: execution)
                        .padding(16)

                    outputSection(for: execution)
                        .padding(16)
                } else {
                    emptyStateSection
                        .padding(24)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            Color.clear.glassEffect(.regular, in: Rectangle())
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.accent)

                Text("Tool Inspector")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .glassEffect(
                        GlassEffect.regular.tint(theme.accent.opacity(0.15)).interactive(),
                        in: .circle
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassEffect(GlassEffect.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toolInfoSection(for execution: ToolExecution) -> some View {
        HStack(spacing: 12) {
            Image(systemName: execution.icon)
                .font(.system(size: 20))
                .foregroundColor(theme.accent)
                .frame(width: 40, height: 40)
                .glassEffect(
                    GlassEffect.regular.tint(theme.accent.opacity(0.15)),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(execution.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(execution.status.color)
                        .frame(width: 6, height: 6)

                    Text(statusText(execution.status))
                        .font(.system(size: 11))
                        .foregroundColor(theme.textSecondary)
                }
            }

            Spacer()
        }
        .glassEffect(
            GlassEffect.regular,
            in: .rect(cornerRadius: 10)
        )
    }

    private func outputSection(for execution: ToolExecution) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            Text(execution.output)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    GlassEffect.regular.tint(theme.accent.opacity(0.12)),
                    in: .rect(cornerRadius: 8)
                )
        }
    }

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.textTertiary.opacity(0.5))

            Text("No Active Tool")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textSecondary)

            Text("Tool execution results will appear here")
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusText(_ status: ToolExecution.ExecutionStatus) -> String {
        switch status {
        case .running: return "Running..."
        case .completed: return "Completed"
        case .failed: return "Error"
        }
    }
}
