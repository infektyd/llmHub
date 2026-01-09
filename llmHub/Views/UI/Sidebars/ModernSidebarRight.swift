//
//  ModernSidebarRight.swift
//  llmHub
//
//  Modern floating right sidebar with collapsible sections
//  Combines inspector, tools, and artifact library functionality
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Inspector State

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

extension Optional where Wrapped == ToolExecution {
    fileprivate func isEqualTo(_ other: ToolExecution?) -> Bool {
        switch (self, other) {
        case (nil, nil):
            return true
        case (nil, .some), (.some, nil):
            return false
        case (.some(let left), .some(let right)):
            return left.id == right.id
                && left.toolID == right.toolID
                && left.name == right.name
                && left.icon == right.icon
                && left.status.rawValue == right.status.rawValue
                && left.output == right.output
                && left.timestamp == right.timestamp
        }
    }
}

// MARK: - Inspector Mode

private enum InspectorMode: String, CaseIterable {
    case focus
    case debug

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .debug: return "Debug"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "eye"
        case .debug: return "ant"
        }
    }
}

// MARK: - Observable State

@MainActor
@Observable
private final class ModernSidebarRightState {
    var mode: InspectorMode = .focus
    var searchText: String = ""
}

// MARK: - Modern Sidebar Right

// swiftlint:disable:next type_body_length
struct ModernSidebarRight: View {
    @Binding var isVisible: Bool
    let inspectorState: CanvasInspectorState

    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    // Persistent state
    @AppStorage("sidebar.right.mode") private var storedMode: String = InspectorMode.focus.rawValue
    @AppStorage("sidebar.right.section.tools.expanded") private var toolsExpanded: Bool = true
    @AppStorage("sidebar.right.section.files.expanded") private var filesExpanded: Bool = true
    @AppStorage("sidebar.right.section.context.expanded") private var contextExpanded: Bool = false
    @AppStorage("sidebar.right.section.tokens.expanded") private var tokensExpanded: Bool = false
    @AppStorage("sidebar.right.section.logs.expanded") private var logsExpanded: Bool = false

    @State private var state = ModernSidebarRightState()
    @State private var debouncedSearchText: String = ""
    @State private var debounceTask: Task<Void, Never>?

    // Artifact library state
    @State private var sandboxedArtifacts: [SandboxedArtifact] = []
    @State private var isLoadingArtifacts = true
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var isDropTargeted = false

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: uiCompactMode ? 8 : 10) {
            header

            modeTabs

            searchBar

            Divider()
                .padding(.horizontal, uiCompactMode ? 12 : 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: uiCompactMode ? 8 : 10) {
                    // Always visible sections
                    toolsSection
                    filesSection

                    // Debug-only sections
                    if state.mode == .debug {
                        contextSection
                        tokensSection
                        logsSection
                    }
                }
                .padding(.horizontal, uiCompactMode ? 10 : 12)
                .padding(.vertical, uiCompactMode ? 8 : 10)
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.backgroundSecondary)
                .shadow(color: AppColors.shadowSmoke, radius: 10, x: 0, y: 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.accent, lineWidth: 2)
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
            state.mode = InspectorMode(rawValue: storedMode) ?? .focus
            Task { await loadSandboxedArtifacts() }
        }
        .onChange(of: state.searchText) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearchText = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        .onChange(of: state.mode) { _, newValue in
            storedMode = newValue.rawValue
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: uiCompactMode ? 8 : 10) {
            Text("Inspector")
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button {
                withAnimation {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, uiCompactMode ? 12 : 14)
        .padding(.top, uiCompactMode ? 12 : 14)
    }

    // MARK: - Mode Tabs

    private var modeTabs: some View {
        HStack(spacing: 6) {
            ForEach(InspectorMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        state.mode = mode
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 14 * uiScale, weight: .semibold))
                        .foregroundStyle(
                            state.mode == mode ? AppColors.textPrimary : AppColors.textSecondary
                        )
                        .padding(.horizontal, uiCompactMode ? 9 : 10)
                        .padding(.vertical, uiCompactMode ? 5 : 6)
                        .frame(minWidth: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    state.mode == mode
                                        ? AppColors.surface.opacity(0.9) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .help(mode.title)
            }
        }
        .padding(.horizontal, uiCompactMode ? 10 : 12)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: uiCompactMode ? 7 : 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)

            TextField("Search", text: $state.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: 8)

            Text("⌘/")
                .font(.system(size: 11 * uiScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)

            Button("Focus Search") {
                searchFocused = true
            }
            .keyboardShortcut("/", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .padding(.horizontal, uiCompactMode ? 10 : 12)
        .padding(.vertical, uiCompactMode ? 8 : 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.backgroundPrimary.opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, uiCompactMode ? 12 : 14)
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        let enabledCount = filteredTools.filter { $0.isEnabled }.count
        let totalCount = filteredTools.count

        return sidebarSection(
            title: "Tools",
            systemImage: "wrench.and.screwdriver",
            countText: "\(enabledCount)/\(totalCount)",
            isExpanded: $toolsExpanded
        ) {
            // Active execution indicator
            if let execution = inspectorState.toolExecution {
                activeExecutionRow(execution)
            }

            // Workspace path
            Text("Sandbox: \(viewModel.workspaceRootDisplayPath)")
                .font(.system(size: 10 * uiScale, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)

            // Tool toggles
            if filteredTools.isEmpty {
                emptyRow("No tools found")
            } else {
                ForEach(filteredTools) { tool in
                    InspectorToolRow(tool: tool, viewModel: viewModel, uiScale: uiScale)
                }
            }
        }
    }

    private func activeExecutionRow(_ execution: ToolExecution) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: execution.icon)
                    .font(.system(size: 12 * uiScale))
                    .foregroundStyle(AppColors.accent)

                Text(execution.name)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text(execution.status.rawValue)
                    .font(.system(size: 10 * uiScale, weight: .medium))
                    .foregroundStyle(statusColor(for: execution.status))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(statusColor(for: execution.status).opacity(0.15))
                    }
            }

            if !execution.output.isEmpty {
                Text(execution.output)
                    .font(.system(size: 10 * uiScale, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(uiCompactMode ? 8 : 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.accent.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
        }
    }

    private func statusColor(for status: ToolExecution.ExecutionStatus) -> Color {
        switch status {
        case .running: return AppColors.accent
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var filteredTools: [UIToolToggleItem] {
        let all = viewModel.toolToggles
        let query = debouncedSearchText.lowercased()
        if query.isEmpty { return all }
        return all.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Files Section

    private var filesSection: some View {
        sidebarSection(
            title: "Files",
            systemImage: "doc.on.doc",
            countText: "\(sandboxedArtifacts.count) · \(formattedTotalSize)",
            isExpanded: $filesExpanded,
            trailing: {
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
                    Image(systemName: "plus")
                        .font(.system(size: 12 * uiScale, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        ) {
            if isLoadingArtifacts {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if sandboxedArtifacts.isEmpty {
                emptyStateFiles
            } else {
                // Group by file type
                let grouped = Dictionary(grouping: filteredArtifacts) { fileTypeGroup(for: $0) }
                ForEach(FileTypeGroup.allCases, id: \.self) { group in
                    if let items = grouped[group], !items.isEmpty {
                        fileGroupSection(group: group, artifacts: items)
                    }
                }
            }
        }
    }

    private var emptyStateFiles: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textTertiary)

            Text("No files shared")
                .font(.system(size: 12 * uiScale))
                .foregroundStyle(AppColors.textSecondary)

            Text("Drag files here or use +")
                .font(.system(size: 10 * uiScale))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func fileGroupSection(group: FileTypeGroup, artifacts: [SandboxedArtifact]) -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(.system(size: 10 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 4)
                .padding(.top, 4)

            ForEach(artifacts) { artifact in
                ArtifactFileRow(artifact: artifact, uiScale: uiScale) {
                    Task { await deleteArtifact(artifact) }
                }
            }
        }
    }

    private var filteredArtifacts: [SandboxedArtifact] {
        let query = debouncedSearchText.lowercased()
        if query.isEmpty { return sandboxedArtifacts }
        return sandboxedArtifacts.filter { $0.filename.lowercased().contains(query) }
    }

    private var formattedTotalSize: String {
        let total = sandboxedArtifacts.reduce(0) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    // MARK: - Context Section

    private var contextSection: some View {
        sidebarSection(
            title: "Context",
            systemImage: "info.circle",
            countText: "\(inspectorState.contextSummary.count)",
            isExpanded: $contextExpanded
        ) {
            if inspectorState.contextSummary.isEmpty {
                emptyRow("No context info")
            } else {
                ForEach(inspectorState.contextSummary, id: \.self) { line in
                    ContextInfoRow(line: line, uiScale: uiScale)
                }
            }
        }
    }

    // MARK: - Tokens Section

    private var tokensSection: some View {
        let percentText =
            inspectorState.tokenStats.map { String(format: "%.1f%%", $0.percentOfContext) } ?? "—"

        return sidebarSection(
            title: "Tokens",
            systemImage: "chart.bar",
            countText: percentText,
            isExpanded: $tokensExpanded
        ) {
            if let stats = inspectorState.tokenStats {
                TokenStatRow(stats: stats, uiScale: uiScale)
            } else {
                emptyRow("No token stats")
            }
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        sidebarSection(
            title: "Logs",
            systemImage: "terminal",
            countText: "\(inspectorState.logs.count)",
            isExpanded: $logsExpanded
        ) {
            if inspectorState.logs.isEmpty {
                emptyRow("No logs")
            } else {
                ForEach(inspectorState.logs, id: \.self) { line in
                    LogEntryRow(line: line, uiScale: uiScale)
                }
            }
        }
    }

    // MARK: - Section Builder

    private func sidebarSection<Content: View, Trailing: View>(
        title: String,
        systemImage: String,
        countText: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 5 : 6) {
            HStack(spacing: uiCompactMode ? 7 : 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(title)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(countText)
                    .font(.system(size: 11 * uiScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)

                Spacer()

                trailing()

                Image(systemName: "chevron.down")
                    .font(.system(size: 11 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .rotationEffect(isExpanded.wrappedValue ? .degrees(0) : .degrees(-90))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded.wrappedValue)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            }
            .padding(.horizontal, uiCompactMode ? 5 : 6)
            .padding(.vertical, uiCompactMode ? 5 : 6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.surface.opacity(0.35))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.textPrimary.opacity(0.06), lineWidth: 1)
            }

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 4) {
                    content()
                }
                .padding(.leading, 2)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12 * uiScale))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, uiCompactMode ? 9 : 10)
            .padding(.vertical, uiCompactMode ? 7 : 8)
    }

    // MARK: - File Type Grouping

    private enum FileTypeGroup: String, CaseIterable {
        case code
        case documents
        case images
        case other

        var title: String {
            switch self {
            case .code: return "Code"
            case .documents: return "Documents"
            case .images: return "Images"
            case .other: return "Other"
            }
        }
    }

    private func fileTypeGroup(for artifact: SandboxedArtifact) -> FileTypeGroup {
        let ext = (artifact.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "json", "html", "css", "yaml", "yml", "sh", "bash", "zsh":
            return .code
        case "md", "txt", "pdf", "doc", "docx", "rtf":
            return .documents
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic":
            return .images
        default:
            return .other
        }
    }

    // MARK: - Artifact Actions

    private func loadSandboxedArtifacts() async {
        isLoadingArtifacts = true
        sandboxedArtifacts = await ArtifactSandboxService.shared.listArtifacts()
        isLoadingArtifacts = false
    }

    private func deleteArtifact(_ artifact: SandboxedArtifact) async {
        try? await ArtifactSandboxService.shared.deleteArtifact(id: artifact.id)
        await loadSandboxedArtifacts()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task {
                            _ = try? await ArtifactSandboxService.shared.importFile(from: url)
                            await loadSandboxedArtifacts()
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
        await loadSandboxedArtifacts()
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        _ = try? await ArtifactSandboxService.shared.importFolder(from: url)
        await loadSandboxedArtifacts()
    }
}

// MARK: - Row Components

private struct InspectorToolRow: View {
    let tool: UIToolToggleItem
    let viewModel: ChatViewModel
    let uiScale: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.icon)
                .font(.system(size: 12 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 12 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Text(tool.description)
                    .font(.system(size: 10 * uiScale))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { tool.isEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.setToolPermission(toolID: tool.id, enabled: newValue)
                        }
                    }
                )
            )
            .labelsHidden()
            .controlSize(.mini)
            .toggleStyle(.switch)
            .disabled(!tool.isAvailable)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help(tool.isAvailable ? "" : (tool.unavailableReason ?? "Unavailable"))
    }
}

private struct ArtifactFileRow: View {
    let artifact: SandboxedArtifact
    let uiScale: CGFloat
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: artifact.iconName)
                .font(.system(size: 12 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.filename)
                    .font(.system(size: 11 * uiScale))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(artifact.formattedSize)
                    .font(.system(size: 9 * uiScale))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10 * uiScale))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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

private struct ContextInfoRow: View {
    let line: String
    let uiScale: CGFloat

    var body: some View {
        let parts = line.split(separator: "=", maxSplits: 1)
        let key = parts.first.map(String.init) ?? line
        let value = parts.count > 1 ? String(parts[1]) : ""

        return HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11 * uiScale, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 11 * uiScale, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct TokenStatRow: View {
    let stats: CanvasInspectorState.TokenStats
    let uiScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.backgroundPrimary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * min(stats.percentOfContext / 100, 1.0))
                }
            }
            .frame(height: 6)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tokens")
                        .font(.system(size: 10 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("\(stats.tokens, format: .number)")
                        .font(.system(size: 13 * uiScale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Cost")
                        .font(.system(size: 10 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("$\(stats.costUSD, format: .number.precision(.fractionLength(4)))")
                        .font(.system(size: 13 * uiScale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            Text(String(format: "%.1f%% of context", stats.percentOfContext))
                .font(.system(size: 10 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.backgroundPrimary.opacity(0.5))
        }
    }

    private var progressColor: Color {
        if stats.percentOfContext > 80 {
            return .red
        } else if stats.percentOfContext > 60 {
            return .orange
        } else {
            return AppColors.accent
        }
    }
}

private struct LogEntryRow: View {
    let line: String
    let uiScale: CGFloat

    var body: some View {
        Text(line)
            .font(.system(size: 10 * uiScale, design: .monospaced))
            .foregroundStyle(AppColors.textSecondary)
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("ModernSidebarRight - Focus") {
        @Previewable @State var visible = true

        let state = CanvasInspectorState(
            toolExecution: ToolExecution(
                id: "exec-1",
                toolID: "read_file",
                name: "read_file",
                icon: "doc.text",
                status: .running,
                output: "Reading /src/main.swift...",
                timestamp: Date()
            ),
            artifacts: [],
            tokenStats: .init(tokens: 4523, costUSD: 0.0234, percentOfContext: 12.5),
            logs: ["isGenerating=true", "streamingTokens=42"],
            contextSummary: ["providerID=openai", "model=gpt-4o", "messages=8"]
        )

        ModernSidebarRight(isVisible: $visible, inspectorState: state)
            .environment(ChatViewModel())
            .frame(width: 320, height: 700)
            .padding()
    }

    #Preview("ModernSidebarRight - Debug Mode") {
        @Previewable @State var visible = true

        ModernSidebarRight(isVisible: $visible, inspectorState: .empty())
            .environment(ChatViewModel())
            .frame(width: 320, height: 700)
            .padding()
    }
#endif
