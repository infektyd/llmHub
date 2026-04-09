//
//  AgentTypingIndicator.swift
//  llmHub
//
//  Per-agent typing indicators for multi-agent chat canvas.
//

import SwiftUI

// MARK: - Single Agent Typing Indicator

struct AgentTypingIndicator: View {
    let agentID: String
    var knownAgents: [Agent] = []

    @Environment(\.uiScale) private var uiScale

    private var identity: AgentIdentity {
        AgentIdentityRegistry.lookup(agentID, knownAgents: knownAgents)
    }

    @State private var dotIndex = 0

    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(identity.color.opacity(0.18))
                    .frame(width: 20 * uiScale, height: 20 * uiScale)
                Text(identity.emoji)
                    .font(.system(size: 10 * uiScale))
            }

            // Name + text
            HStack(spacing: 4) {
                Text(identity.name)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(identity.color)
                Text("is thinking")
                    .font(.system(size: 12 * uiScale))
                    .foregroundStyle(AppColors.textTertiary)
            }

            // Three-dot typing animation
            HStack(spacing: 3) {
                Circle()
                    .fill(identity.color)
                    .frame(width: 5 * uiScale, height: 5 * uiScale)
                    .opacity(dotIndex == 0 ? 1 : 0.3)
                Circle()
                    .fill(identity.color)
                    .frame(width: 5 * uiScale, height: 5 * uiScale)
                    .opacity(dotIndex == 1 ? 1 : 0.3)
                Circle()
                    .fill(identity.color)
                    .frame(width: 5 * uiScale, height: 5 * uiScale)
                    .opacity(dotIndex == 2 ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(identity.color.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(identity.color.opacity(0.15), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { startTypingAnimation() }
    }

    private func startTypingAnimation() {
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: false)) {
            dotIndex = 3
        }
    }
}

// MARK: - Multi-Agent Typing Indicator

struct MultiAgentTypingIndicator: View {
    let typingAgentIDs: Set<String>
    var knownAgents: [Agent] = []

    var body: some View {
        if !typingAgentIDs.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(typingAgentIDs.sorted()), id: \.self) { agentID in
                    AgentTypingIndicator(
                        agentID: agentID,
                        knownAgents: knownAgents
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: typingAgentIDs)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AgentTypingIndicator — Single") {
    AgentTypingIndicator(agentID: "agent-alpha")
        .padding()
}

#Preview("AgentTypingIndicator — Alt") {
    AgentTypingIndicator(agentID: "agent-bravo")
        .padding()
}

#Preview("MultiAgentTypingIndicator") {
    MultiAgentTypingIndicator(typingAgentIDs: ["agent-alpha", "agent-bravo", "agent-charlie"])
        .padding()
}
#endif
