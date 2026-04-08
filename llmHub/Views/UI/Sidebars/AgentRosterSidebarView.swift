//
//  AgentRosterSidebarView.swift
//  llmHub
//

import SwiftUI

/// Sidebar displaying discovered OpenClaw gateway agents with status indicators.
struct AgentRosterSidebarView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Agents")
                    .font(.system(size: 13 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if chatVM.isLoadingAgents {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button {
                        Task { await chatVM.discoverAgents() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(chatVM.allKnownAgents) { agent in
                        AgentRow(
                            agent: agent,
                            costSnapshot: chatVM.agentCostSnapshots[agent.id]
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Spacer()

            // Total cost summary
            let total = chatVM.totalAgentCost
            if total.totalCostUSD > 0 || total.inputTokens + total.outputTokens > 0 {
                Divider()
                HStack(spacing: 6) {
                    Text("Total")
                        .font(.system(size: 11 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text(formatCostSummary(total))
                        .font(.system(size: 10 * uiScale, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if let error = chatVM.agentDiscoveryError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10 * uiScale))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 10 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
                .padding(8)
            }
        }
        .padding(8)
        .frame(minWidth: 220)
    }

    private func formatCostSummary(_ snapshot: AgentCostSnapshot) -> String {
        let tokens = snapshot.inputTokens + snapshot.outputTokens
        let tokenStr = formatTokens(tokens)
        return "\(tokenStr) · $\(String(format: "%.2f", snapshot.totalCostUSD))"
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}

private struct AgentRow: View {
    let agent: Agent
    let costSnapshot: AgentCostSnapshot?
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8 * uiScale, height: 8 * uiScale)
            Text(agent.emoji)
                .font(.system(size: 16 * uiScale))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.system(size: 13 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                HStack(spacing: 4) {
                    Text("@\(agent.id)")
                        .font(.system(size: 10 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)
                    if let cost = costSnapshot, cost.totalCostUSD > 0 {
                        Text("·")
                            .font(.system(size: 10 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("$\(String(format: "%.2f", cost.totalCostUSD))")
                            .font(.system(size: 10 * uiScale, design: .monospaced))
                            .foregroundStyle(AppColors.accent.opacity(0.8))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppColors.backgroundSecondary.opacity(0.5))
        }
    }

    private var statusColor: Color {
        switch agent.status {
        case .online: return .green
        case .offline: return .gray
        case .busy: return .orange
        }
    }
}

#if DEBUG
#Preview("Agent Roster") {
    @Previewable @State var vm = ChatViewModel.preview()
    vm.discoveredAgents = [
        Agent(id: "syntra", name: "Syntra", emoji: "🔵", status: .online),
        Agent(id: "forge", name: "Forge", emoji: "⚒️", status: .online),
        Agent(id: "recon", name: "Recon", emoji: "🔍", status: .busy),
        Agent(id: "pulse", name: "Pulse", emoji: "💓", status: .online),
        Agent(id: "council", name: "Council", emoji: "🏛️", status: .offline)
    ]
    vm.agentCostSnapshots = [
        "forge": AgentCostSnapshot(inputTokens: 450_000, outputTokens: 120_000, cachedTokens: 50_000, totalCostUSD: 0.42),
        "syntra": AgentCostSnapshot(inputTokens: 200_000, outputTokens: 80_000, cachedTokens: 20_000, totalCostUSD: 0.18)
    ]
    return AgentRosterSidebarView()
        .environment(vm)
        .frame(width: 240, height: 400)
}
#endif
