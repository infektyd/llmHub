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

    @State private var animationPhase = 0

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
            typingDots
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

    // MARK: - Typing Dots Animation

    @ViewBuilder
    private var typingDots: some View {
        HStack(spacing: 3) {
            typingDot(delay: 0)
            typingDot(delay: 0.2)
            typingDot(delay: 0.4)
        }
    }

    private func typingDot(delay: Double) -> some View {
        Circle()
            .fill(identity.color)
            .frame(width: 5 * uiScale, height: 5 * uiScale)
            .scaleEffect(dotScale(for: delay))
            .opacity(dotOpacity(for: delay))
    }

    private func dotScale(_ delay: Double) -> Double {
        let t = (Double(animationPhase) * 0.1 + delay).truncatingRemainder(dividingBy: 1.0)
        return 1.0 + 0.4 * sin(t * .pi * 2)
    }

    private func dotOpacity(_ delay: Double) -> Double {
        let t = (Double(animationPhase) * 0.1 + delay).truncatingRemainder(dividingBy: 1.0)
        return 0.4 + 0.6 * sin(t * .pi * 2)
    }

    private func startTypingAnimation() {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: false)) {
            animationPhase = 10
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
#Preview("AgentTypingIndicator — Syntra") {
    AgentTypingIndicator(agentID: "syntra")
        .padding()
}

#Preview("AgentTypingIndicator — Forge") {
    AgentTypingIndicator(agentID: "forge")
        .padding()
}

#Preview("MultiAgentTypingIndicator") {
    MultiAgentTypingIndicator(typingAgentIDs: ["syntra", "forge", "recon"])
        .padding()
}
#endif
