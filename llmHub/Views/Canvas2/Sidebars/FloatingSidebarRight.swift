//
//  FloatingSidebarRight.swift
//  llmHub
//
//  Floating right sidebar for inspector (context/tools/artifacts/tokens/logs)
//  Appears "on top" of canvas with shadow + border (not glass)
//

import SwiftUI

/// Floating right sidebar for inspection/debugging
/// Shows tool execution, tokens, context, logs
struct FloatingSidebarRight: View {
    @Binding var isVisible: Bool
    @Binding var toolExecution: ToolExecution?

    @State private var selectedTab: InspectorTab = .tools

    enum InspectorTab: String, CaseIterable {
        case tools = "Tools"
        case context = "Context"
        case tokens = "Tokens"
        case logs = "Logs"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs
            header

            Divider()

            // Content
            ScrollView {
                switch selectedTab {
                case .tools:
                    toolsContent
                case .context:
                    contextContent
                case .tokens:
                    tokensContent
                case .logs:
                    logsContent
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Canvas2Colors.panelBackground)
                .shadow(color: Canvas2Colors.panelShadow, radius: 20, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Canvas2Colors.panelBorder, lineWidth: 1)
        }
    }

    // MARK: - Private Views

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Inspector")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Tab picker
            Picker("Inspector Tab", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
    }

    private var toolsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let execution = toolExecution {
                VStack(alignment: .leading, spacing: 8) {
                    Text(execution.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Status: \(execution.status.rawValue)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)

                    if !execution.output.isEmpty {
                        Text("Output:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(execution.output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.backgroundPrimary.opacity(0.5))
                }
            } else {
                Text("No active tool execution")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(12)
            }
        }
        .padding(16)
    }

    private var contextContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context window info will appear here")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(16)
    }

    private var tokensContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token usage stats will appear here")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(16)
    }

    private var logsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug logs will appear here")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(16)
    }
}
