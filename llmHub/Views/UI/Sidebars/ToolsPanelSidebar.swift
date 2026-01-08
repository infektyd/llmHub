//
//  ToolsPanelSidebar.swift
//  llmHub
//
//  Created by User on 2026-01-02.
//

import SwiftUI

struct ToolsPanelSidebar: View {
    @Environment(ChatViewModel.self) private var viewModel

    @Environment(\.uiScale) private var uiScale

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search/Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                TextField("Search tools...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13 * uiScale))
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.backgroundPrimary.opacity(0.5))
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if filteredTools.isEmpty {
                        Text("No tools found")
                            .font(.system(size: 13 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(filteredTools) { tool in
                            ToolRow(tool: tool, viewModel: viewModel)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var filteredTools: [UIToolToggleItem] {
        let all = viewModel.toolToggles
        if searchText.isEmpty { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct ToolRow: View {
    let tool: UIToolToggleItem
    let viewModel: ChatViewModel

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        HStack {
            Image(systemName: tool.icon)
                .font(.system(size: 12 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Text(tool.description)
                    .font(.system(size: 11 * uiScale))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { tool.isEnabled },
                    set: { newValue in
                        updatePermission(newValue)
                    }
                )
            )
            .labelsHidden()
            .controlSize(.mini)
            .toggleStyle(.switch)
            .disabled(!tool.isAvailable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .help(tool.isAvailable ? "" : (tool.unavailableReason ?? "Unavailable"))
    }

    private func updatePermission(_ allowed: Bool) {
        Task {
            await viewModel.setToolPermission(toolID: tool.id, enabled: allowed)
        }
    }
}
