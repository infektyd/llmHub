//
//  AgentAutocompleteView.swift
//  llmHub
//

import SwiftUI

/// Dropdown overlay that appears when the user types @ in the composer.
/// Suggests matching agents for @mention completion.
struct AgentAutocompleteView: View {
    let agents: [Agent]
    let onSelect: (Agent) -> Void
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        guard !agents.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 1) {
                ForEach(agents) { agent in
                    AgentAutocompleteRow(agent: agent) {
                        onSelect(agent)
                    }
                }
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 2)
            }
        )
    }
}

private struct AgentAutocompleteRow: View {
    let agent: Agent
    let onSelect: () -> Void
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(agent.emoji)
                    .font(.system(size: 14 * uiScale))
                Text(agent.name)
                    .font(.system(size: 13 * uiScale, weight: .medium))
                Spacer()
                Text("@\(agent.id)")
                    .font(.system(size: 11 * uiScale))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .opacity(1) // always visible as hover state
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Agent Autocomplete") {
    @Previewable @State var text = ""
    @Previewable @State var vm = ChatViewModel.preview()
    vm.discoveredAgents = [
        Agent(id: "syntra", name: "Syntra", emoji: "🔵", status: .online),
        Agent(id: "forge", name: "Forge", emoji: "⚒️", status: .online),
    ]

    VStack {
        Text("Type @ below to see autocomplete")
        AgentAutocompleteView(agents: vm.allKnownAgents) { agent in
            print("Selected \(agent.name)")
        }
    }
    .environment(vm)
    .frame(width: 250, height: 120)
}
#endif
