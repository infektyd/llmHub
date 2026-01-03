//
//  ToolsPanelSidebar.swift
//  llmHub
//
//  Created by User on 2026-01-02.
//

import SwiftUI

struct ToolsPanelSidebar: View {
    @EnvironmentObject private var toolRegistry: ToolRegistry
    // Assuming ToolAuthorizationService is a singleton or environment object.
    // Based on usage in other files, checking if it's separate.
    // Ideally we inject it.

    // For now, let's assume we can access available tools from registry.

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search/Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                TextField("Search tools...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
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
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(filteredTools) { tool in
                            ToolRow(tool: tool)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var filteredTools: [ToolDefinition] {
        let all = toolRegistry.availableTools
        if searchText.isEmpty { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct ToolRow: View {
    let tool: ToolDefinition
    @State private var isEnabled: Bool = true  // This should bind to auth service

    var body: some View {
        HStack {
            Image(systemName: "hammer.fill")  // Placeholder icon
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Text(tool.description)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .controlSize(.mini)
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { _, newValue in
                    updatePermission(newValue)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onAppear {
            let status = ToolAuthorizationService.shared.checkAccess(for: tool.id)
            isEnabled = (status == .authorized)
        }
    }

    private func updatePermission(_ allowed: Bool) {
        if allowed {
            ToolAuthorizationService.shared.grantAccess(for: tool.id)
        } else {
            ToolAuthorizationService.shared.revokeAccess(for: tool.id)
        }
    }
}
