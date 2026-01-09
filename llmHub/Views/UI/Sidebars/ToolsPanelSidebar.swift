//
//  ToolsPanelSidebar.swift
//  llmHub
//
//  Created by User on 2026-01-02.
//

import SwiftUI
import UniformTypeIdentifiers

/// Right sidebar panel showing either Tools or Artifact Library
struct ToolsPanelSidebar: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.uiScale) private var uiScale

    @State private var searchText = ""
    @State private var selectedTab: SidebarTab = .tools

    private enum SidebarTab: String, CaseIterable {
        case tools = "Tools"
        case artifacts = "Library"

        var icon: String {
            switch self {
            case .tools: return "wrench.and.screwdriver"
            case .artifacts: return "tray.full"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabSelector

            Divider()
                .padding(.horizontal, 16)

            // Content based on selected tab
            switch selectedTab {
            case .tools:
                toolsContent
            case .artifacts:
                ArtifactLibrarySidebarContent()
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(SidebarTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11 * uiScale))
                        Text(tab.rawValue)
                            .font(.system(size: 12 * uiScale, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppColors.accent.opacity(0.15))
                        }
                    }
                    .foregroundStyle(
                        selectedTab == tab ? AppColors.accent : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Tools Content

    private var toolsContent: some View {
        VStack(spacing: 0) {
            // Workspace path display
            Text("Sandbox: \(viewModel.workspaceRootDisplayPath)")
                .font(.system(size: 10 * uiScale, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

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

// MARK: - Tool Row

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

// MARK: - Artifact Library Sidebar Content

/// Compact artifact library view for sidebar integration
struct ArtifactLibrarySidebarContent: View {
    @State private var artifacts: [SandboxedArtifact] = []
    @State private var isLoading = true
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var isDropTargeted = false

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats and import button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(artifacts.count) files")
                        .font(.system(size: 13 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(formattedTotalSize)
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Menu {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import Files...", systemImage: "doc.badge.plus")
                    }

                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Import Folder...", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18 * uiScale))
                        .foregroundStyle(AppColors.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 16)

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if artifacts.isEmpty {
                emptyState
            } else {
                artifactList
            }
        }
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.accent, lineWidth: 2)
                    .padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleFileImport(result) }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFolderImport(result) }
        }
        .onAppear {
            Task { await loadArtifacts() }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textTertiary)

            Text("No Files Shared")
                .font(.system(size: 13 * uiScale, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Text("Drag files here or use + to share with AI")
                .font(.system(size: 11 * uiScale))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    private var artifactList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(artifacts) { artifact in
                    ArtifactSidebarRow(artifact: artifact) {
                        Task { await deleteArtifact(artifact) }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Computed

    private var formattedTotalSize: String {
        let total = artifacts.reduce(0) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    // MARK: - Actions

    private func loadArtifacts() async {
        isLoading = true
        artifacts = await ArtifactSandboxService.shared.listArtifacts()
        isLoading = false
    }

    private func deleteArtifact(_ artifact: SandboxedArtifact) async {
        try? await ArtifactSandboxService.shared.deleteArtifact(id: artifact.id)
        await loadArtifacts()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task {
                            _ = try? await ArtifactSandboxService.shared.importFile(from: url)
                            await loadArtifacts()
                        }
                    }
                }
            }
        }
        return true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            _ = try? await ArtifactSandboxService.shared.importFile(from: url)
        }
        await loadArtifacts()
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        _ = try? await ArtifactSandboxService.shared.importFolder(from: url)
        await loadArtifacts()
    }
}

// MARK: - Artifact Sidebar Row

private struct ArtifactSidebarRow: View {
    let artifact: SandboxedArtifact
    let onDelete: () -> Void

    @Environment(\.uiScale) private var uiScale
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: artifact.iconName)
                .font(.system(size: 14 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.filename)
                    .font(.system(size: 12 * uiScale))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(artifact.formattedSize)
                    .font(.system(size: 10 * uiScale))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppColors.backgroundSecondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
