//
//  FloatingSidebarRight.swift
//  llmHub
//
//  Floating right sidebar for inspector (context/tools/artifacts/tokens/logs)
//  Appears "on top" of canvas with shadow + border (not glass)
//

import SwiftUI

struct CanvasInspectorState: Equatable {
    static func == (lhs: CanvasInspectorState, rhs: CanvasInspectorState) -> Bool {
        lhs.toolExecution.isEqualTo(rhs.toolExecution)
            && lhs.artifacts == rhs.artifacts
            && lhs.tokenStats == rhs.tokenStats
            && lhs.logs == rhs.logs
            && lhs.contextSummary == rhs.contextSummary
    }

    struct TokenStats: Equatable {
        var tokens: Int
        var costUSD: Decimal
        var percentOfContext: Double
    }

    var toolExecution: ToolExecution?
    var artifacts: [ArtifactPayload]
    var tokenStats: TokenStats?
    var logs: [String]
    var contextSummary: [String]

    static func empty() -> CanvasInspectorState {
        CanvasInspectorState(
            toolExecution: nil,
            artifacts: [],
            tokenStats: nil,
            logs: [],
            contextSummary: []
        )
    }
}

private extension Optional where Wrapped == ToolExecution {
    func isEqualTo(_ other: ToolExecution?) -> Bool {
        switch (self, other) {
        case (nil, nil):
            return true
        case (nil, .some), (.some, nil):
            return false
        case (.some(let a), .some(let b)):
            return a.id == b.id
                && a.toolID == b.toolID
                && a.name == b.name
                && a.icon == b.icon
                && a.status.rawValue == b.status.rawValue
                && a.output == b.output
                && a.timestamp == b.timestamp
        }
    }
}

/// Floating right sidebar for inspection/debugging
/// Shows tool execution, tokens, context, logs
struct FloatingSidebarRight: View {
    @Binding var isVisible: Bool
    let state: CanvasInspectorState

    @State private var selectedTab: InspectorTab = .tools

    enum InspectorTab: String, CaseIterable {
        case tools = "Tools"
        case artifacts = "Artifacts"
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
                case .artifacts:
                    artifactsContent
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
            if let execution = state.toolExecution {
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
            if state.contextSummary.isEmpty {
                Text("No context information")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(state.contextSummary, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
    }

    private var tokensContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats = state.tokenStats {
                Text("Tokens: \(stats.tokens)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Cost: $\(stats.costUSD)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)

                Text(String(format: "Context used: %.1f%%", stats.percentOfContext))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("No token stats available")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(16)
    }

    private var logsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.logs.isEmpty {
                Text("No logs")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(state.logs, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
    }

    private var artifactsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.artifacts.isEmpty {
                Text("No artifacts")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(state.artifacts) { artifact in
                    ArtifactCardView(payload: artifact)
                }
            }
        }
        .padding(16)
    }
}

#if DEBUG
#Preview("SidebarRight - Populated") {
    @Previewable @State var visible = true

    let execution = ToolExecution(
        id: "exec-preview",
        toolID: "http_request",
        name: "http_request",
        icon: "network",
        status: .running,
        output: "GET /v1/models …",
        timestamp: Canvas2PreviewFixtures.baseDate
    )

    let state = CanvasInspectorState(
        toolExecution: execution,
        artifacts: [Canvas2PreviewFixtures.toolResultArtifact(), Canvas2PreviewFixtures.codeFileArtifact()],
        tokenStats: .init(tokens: 1234, costUSD: 0.0123, percentOfContext: 1.5),
        logs: [
            "isGenerating=true",
            "executingTools=http_request",
            "streamingTokenEstimate=42",
            "mergeOverlay=shown",
        ],
        contextSummary: [
            "providerID=openai",
            "model=gpt-4o",
            "messages=12",
        ]
    )

    return FloatingSidebarRight(isVisible: $visible, state: state)
        .frame(width: 360, height: 720)
        .padding()
}

#Preview("SidebarRight - Empty") {
    @Previewable @State var visible = true
    return FloatingSidebarRight(isVisible: $visible, state: .empty())
        .frame(width: 360, height: 720)
        .padding()
}
#endif
