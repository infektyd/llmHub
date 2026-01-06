//
//  ModernSidebarLeft.swift
//  llmHub
//
//  Grok/Claude-inspired floating sidebar with hierarchical organization.
//

import SwiftData
import SwiftUI

private enum SidebarMode: String, CaseIterable {
    case chat
    case code
    case imagine
    case voice
    case projects

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .code: return "Code"
        case .imagine: return "Imagine"
        case .voice: return "Voice"
        case .projects: return "Projects"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .imagine: return "sparkles"
        case .voice: return "waveform"
        case .projects: return "folder"
        }
    }
}

@MainActor
@Observable
private final class ModernSidebarState {
    var mode: SidebarMode = .chat
    var searchText: String = ""
}

struct ModernSidebarLeft: View {
    @Binding var isVisible: Bool
    @Binding var rightSidebarVisible: Bool
    let sessions: [ChatSessionEntity]
    let folders: [ChatFolderEntity]
    @Binding var selectedConversationID: UUID?
    let onNewConversation: () -> Void

    @Environment(\.modelContext) private var modelContext

    @AppStorage("sidebar.modern.mode") private var storedMode: String = SidebarMode.chat.rawValue
    @AppStorage("sidebar.modern.section.pinned.expanded") private var pinnedExpanded: Bool = true
    @AppStorage("sidebar.modern.section.projects.expanded") private var projectsExpanded: Bool = true
    @AppStorage("sidebar.modern.section.artifacts.expanded") private var artifactsExpanded: Bool = true
    @AppStorage("sidebar.modern.section.recent.expanded") private var recentExpanded: Bool = true
    @AppStorage("sidebar.modern.section.archive.expanded") private var archiveExpanded: Bool = false

    @State private var state = ModernSidebarState()
    @State private var debouncedSearchText: String = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var didLoadExpandedProjects = false

    @FocusState private var searchFocused: Bool

    private let lifecycleService = ConversationLifecycleService()

    var body: some View {
        VStack(spacing: 10) {
            header

            modeTabs

            searchBar

            Divider()
                .padding(.horizontal, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    pinnedSection
                    projectsSection
                    artifactsSection
                    recentSection
                    archiveSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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
        .onAppear {
            state.mode = SidebarMode(rawValue: storedMode) ?? .chat
            if !didLoadExpandedProjects {
                expandedProjectIDs = loadExpandedProjectIDs()
                didLoadExpandedProjects = true
            }
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

    private var header: some View {
        HStack(spacing: 10) {
            Text("llmHub")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button {
                onNewConversation()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private var modeTabs: some View {
        HStack(spacing: 6) {
            ForEach(SidebarMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        state.mode = mode
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state.mode == mode ? AppColors.textPrimary : AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(state.mode == mode ? AppColors.surface.opacity(0.9) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .help(mode.title)
            }
        }
        .padding(.horizontal, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)

            TextField("Search", text: $state.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: 8)

            Text("⌘K")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)

            Button("Focus Search") {
                searchFocused = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.backgroundPrimary.opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 14)
    }

    private var pinnedSection: some View {
        sidebarSection(
            title: "Pinned",
            systemImage: "pin.fill",
            count: pinnedSessions.count,
            isExpanded: $pinnedExpanded
        ) {
            if pinnedSessions.isEmpty {
                emptyRow("No pinned chats")
            } else {
                ForEach(pinnedSessions.prefix(50)) { session in
                    conversationRow(session, leadingSymbol: session.pinnedSymbol ?? "💎")
                }
            }
        }
    }

    private var projectsSection: some View {
        sidebarSection(
            title: "Projects",
            systemImage: "folder.fill",
            count: folders.count,
            isExpanded: $projectsExpanded,
            trailing: {
                Button {
                    createProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
        ) {
            let inbox = inboxSessions
            if !inbox.isEmpty {
                projectGroup(
                    title: "Inbox",
                    systemImage: "tray",
                    projectID: nil,
                    sessions: inbox
                )
            }

            if folders.isEmpty {
                emptyRow("No projects yet")
            } else {
                ForEach(folders) { folder in
                    projectGroup(
                        title: folder.name,
                        systemImage: folder.icon,
                        projectID: folder.id,
                        sessions: sessionsForProject(folder.id)
                    )
                }
            }
        }
    }

    private var artifactsSection: some View {
        sidebarSection(
            title: "Artifacts",
            systemImage: "square.stack.3d.up.fill",
            count: artifactSummaries.count,
            isExpanded: $artifactsExpanded
        ) {
            if artifactSummaries.isEmpty {
                emptyRow("No artifacts found")
            } else {
                let grouped = Dictionary(grouping: artifactSummaries) { $0.kind }
                ForEach(ArtifactKind.allCases, id: \.rawValue) { kind in
                    if let items = grouped[kind], !items.isEmpty {
                        kindGroup(kind: kind, artifacts: items)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        sidebarSection(
            title: "Recent",
            systemImage: "clock",
            count: recentSessions.count,
            isExpanded: $recentExpanded
        ) {
            if recentSessions.isEmpty {
                emptyRow("No recent chats")
            } else {
                let grouped = Dictionary(grouping: recentSessions) { categoryKey(for: $0) }
                ForEach(
                    grouped.keys.sorted(by: { categorySortKey($0) < categorySortKey($1) }),
                    id: \.self
                ) { key in
                    if let items = grouped[key] {
                        categoryGroup(title: key, sessions: items)
                    }
                }
            }
        }
    }

    private var archiveSection: some View {
        sidebarSection(
            title: "Archive",
            systemImage: "archivebox.fill",
            count: archivedSessions.count,
            isExpanded: $archiveExpanded
        ) {
            if archivedSessions.isEmpty {
                emptyRow("No archived chats")
            } else {
                ForEach(archivedSessions.prefix(50)) { session in
                    conversationRow(session)
                }
            }
        }
    }

    // MARK: - Data

    private var effectiveSearchQuery: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var modeFilteredSessions: [ChatSessionEntity] {
        switch state.mode {
        case .chat, .projects:
            return sessions
        case .code:
            return sessions.filter { ($0.afmCategory ?? "").lowercased() == "coding" }
        case .imagine:
            return sessions.filter { ($0.afmCategory ?? "").lowercased() == "creative" }
        case .voice:
            return sessions.filter { ($0.afmCategory ?? "").lowercased() == "support" }
        }
    }

    private func matchesSearch(_ session: ChatSessionEntity) -> Bool {
        let q = effectiveSearchQuery
        guard !q.isEmpty else { return true }

        if session.displayTitle.lowercased().contains(q) { return true }
        if (session.afmCategory ?? "").lowercased().contains(q) { return true }
        if (session.afmIntent ?? session.lifecycleIntent ?? "").lowercased().contains(q) { return true }
        if session.afmTopicsArray.contains(where: { $0.lowercased().contains(q) }) { return true }
        if let folderName = session.folder?.name.lowercased(), folderName.contains(q) { return true }
        return false
    }

    private var pinnedSessions: [ChatSessionEntity] {
        modeFilteredSessions
            .filter { !$0.isArchived && $0.isPinned }
            .filter(matchesSearch)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var inboxSessions: [ChatSessionEntity] {
        modeFilteredSessions
            .filter { !$0.isArchived && !$0.isPinned && $0.folder == nil }
            .filter(matchesSearch)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func sessionsForProject(_ id: UUID) -> [ChatSessionEntity] {
        modeFilteredSessions
            .filter { !$0.isArchived && !$0.isPinned && $0.folder?.id == id }
            .filter(matchesSearch)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var recentSessions: [ChatSessionEntity] {
        modeFilteredSessions
            .filter { !$0.isArchived && !$0.isPinned }
            .filter(matchesSearch)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(80)
            .map { $0 }
    }

    private var archivedSessions: [ChatSessionEntity] {
        modeFilteredSessions
            .filter { $0.isArchived }
            .filter(matchesSearch)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private struct SidebarArtifactSummary: Identifiable, Hashable {
        let id: UUID
        let title: String
        let kind: ArtifactKind
        let sessionID: UUID
        let createdAt: Date
    }

    private var artifactSummaries: [SidebarArtifactSummary] {
        let candidateSessions = modeFilteredSessions
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(30)

        var results: [SidebarArtifactSummary] = []
        results.reserveCapacity(40)

        for session in candidateSessions {
            guard matchesSearch(session) else { continue }
            let messages = session.messages.sorted { $0.createdAt > $1.createdAt }.prefix(10)
            for entity in messages {
                let message = entity.asDomain()
                for meta in message.artifactMetadatas {
                    let id = Canvas2StableIDs.artifactID(messageID: message.id, metadata: meta)
                    results.append(
                        SidebarArtifactSummary(
                            id: id,
                            title: meta.filename,
                            kind: mapArtifactKind(meta.language),
                            sessionID: session.id,
                            createdAt: message.createdAt
                        )
                    )
                    if results.count >= 80 { return results }
                }
            }
        }

        return results
    }

    private func mapArtifactKind(_ lang: CodeLanguage) -> ArtifactKind {
        switch lang {
        case .json, .swift, .python, .javascript: return .code
        case .markdown, .text: return .text
        }
    }

    // MARK: - Section Building

    private func sidebarSection<Content: View, Trailing: View>(
        title: String,
        systemImage: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)

                Spacer()

                trailing()

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
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
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
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
            .font(.system(size: 12))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private func conversationRow(_ session: ChatSessionEntity, leadingSymbol: String? = nil) -> some View {
        Button {
            selectedConversationID = session.id
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if let leadingSymbol {
                    Text(leadingSymbol)
                        .font(.system(size: 14))
                } else if let emoji = session.afmEmoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(
                            .system(
                                size: 12,
                                weight: selectedConversationID == session.id ? .semibold : .regular)
                        )
                        .foregroundStyle(
                            selectedConversationID == session.id
                                ? AppColors.textPrimary : AppColors.textSecondary
                        )
                        .lineLimit(1)

                    Text(session.updatedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedConversationID == session.id ? AppColors.accent.opacity(0.12) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            sessionContextMenu(session)
        }
    }

    private func sessionContextMenu(_ session: ChatSessionEntity) -> some View {
        Group {
            Button(session.isPinned ? "Unpin" : "Pin") {
                togglePin(session)
            }

            if session.isPinned {
                Menu("Pin Symbol") {
                    ForEach(["💎", "⭐️", "🔖", "📌", "🎯", "🏆", "⚡️"], id: \.self) { symbol in
                        Button(symbol) {
                            session.pinnedSymbol = symbol
                            try? modelContext.save()
                        }
                    }
                }
            }

            Menu("Move to Project") {
                Button("Inbox") {
                    session.folder = nil
                    session.parentProjectID = nil
                    try? modelContext.save()
                }
                Divider()
                ForEach(folders) { folder in
                    Button(folder.name) {
                        session.folder = folder
                        session.parentProjectID = folder.id
                        try? modelContext.save()
                    }
                }
            }

            Button("Re-classify") {
                Task { @MainActor in
                    await reclassify(session)
                }
            }

            Divider()

            if session.isArchived {
                Button("Unarchive") {
                    lifecycleService.unarchive(session: session, modelContext: modelContext)
                }
            } else {
                Button("Archive") {
                    lifecycleService.archive(session: session, modelContext: modelContext)
                }
            }

            Button("Delete", role: .destructive) {
                lifecycleService.delete(session: session, modelContext: modelContext)
            }
        }
    }

    private func togglePin(_ session: ChatSessionEntity) {
        session.isPinned.toggle()
        if session.isPinned, session.pinnedSymbol == nil {
            session.pinnedSymbol = "💎"
        }
        if !session.isPinned {
            session.pinnedSymbol = nil
        }
        try? modelContext.save()
    }

    private func createProject() {
        let name = "New Project"
        let nextOrder = (folders.map(\.orderIndex).max() ?? 0) + 1
        let folder = ChatFolder(
            id: UUID(),
            name: name,
            icon: "folder.fill",
            color: "#7C3AED",
            orderIndex: nextOrder,
            createdAt: Date(),
            updatedAt: Date()
        )
        modelContext.insert(ChatFolderEntity(folder: folder))
        try? modelContext.save()
    }

    private func projectGroup(
        title: String,
        systemImage: String,
        projectID: UUID?,
        sessions: [ChatSessionEntity]
    ) -> some View {
        let isExpanded = Binding(
            get: {
                guard let projectID else { return true }
                return expandedProjectIDs.contains(projectID)
            },
            set: { newValue in
                guard let projectID else { return }
                setProjectExpanded(projectID, expanded: newValue)
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)

                    Text("\(min(sessions.count, 999))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(isExpanded.wrappedValue ? .degrees(0) : .degrees(-90))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded.wrappedValue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.surface.opacity(0.18))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.textPrimary.opacity(0.05), lineWidth: 1)
            }

            if isExpanded.wrappedValue {
                if sessions.isEmpty {
                    emptyRow("No chats")
                        .padding(.leading, 8)
                } else {
                    ForEach(sessions.prefix(50)) { session in
                        conversationRow(session)
                            .padding(.leading, 6)
                    }
                }
            }
        }
    }

    private func kindGroup(kind: ArtifactKind, artifacts: [SidebarArtifactSummary]) -> some View {
        let sorted = artifacts.sorted { $0.createdAt > $1.createdAt }.prefix(20)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Text(kind.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Text("\(sorted.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ForEach(sorted) { artifact in
                Button {
                    selectedConversationID = artifact.sessionID
                    rightSidebarVisible = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                        Text(artifact.title)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(artifact.createdAt, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoryKey(for session: ChatSessionEntity) -> String {
        let raw = (session.afmCategory ?? "general").lowercased()
        switch raw {
        case "coding": return "💻 Coding"
        case "research": return "🔬 Research"
        case "creative": return "📝 Creative"
        case "planning": return "📋 Planning"
        case "support": return "💡 Support"
        default: return "💬 General"
        }
    }

    private func categorySortKey(_ key: String) -> Int {
        switch key {
        case "💻 Coding": return 0
        case "🔬 Research": return 1
        case "📝 Creative": return 2
        case "📋 Planning": return 3
        case "💡 Support": return 4
        default: return 5
        }
    }

    private func categoryGroup(title: String, sessions: [ChatSessionEntity]) -> some View {
        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(20)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            ForEach(sorted) { session in
                conversationRow(session)
                    .padding(.leading, 6)
            }
        }
    }

    private func setProjectExpanded(_ id: UUID, expanded: Bool) {
        if expanded {
            expandedProjectIDs.insert(id)
        } else {
            expandedProjectIDs.remove(id)
        }
        saveExpandedProjectIDs(expandedProjectIDs)
    }

    private func loadExpandedProjectIDs() -> Set<UUID> {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "sidebar.modern.projects.expanded.v1") else {
            return []
        }
        let ids = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        return Set(ids)
    }

    private func saveExpandedProjectIDs(_ ids: Set<UUID>) {
        let defaults = UserDefaults.standard
        let data = try? JSONEncoder().encode(Array(ids))
        defaults.set(data, forKey: "sidebar.modern.projects.expanded.v1")
    }

    private func reclassify(_ session: ChatSessionEntity) async {
        let service = ConversationClassificationService()
        let messages = session.messages.sorted { $0.createdAt < $1.createdAt }.map { $0.asDomain() }
        guard let metadata = try? await service.classify(messages: messages) else { return }

        session.afmTitle = metadata.title
        session.afmEmoji = metadata.emoji
        session.afmCategory = metadata.category.rawValue
        session.afmIntent = metadata.intent.rawValue
        session.afmTopics = metadata.topics
        session.afmClassifiedAt = Date()
        session.lifecycleIntent = metadata.intent.rawValue
        session.lifecycleRetention = metadata.suggestedRetention.rawValue
        session.isComplete = metadata.isComplete
        session.hasArtifacts = metadata.hasArtifacts

        try? modelContext.save()
    }
}

#if DEBUG
    #Preview("ModernSidebarLeft") {
        @Previewable @State var visible = true
        @Previewable @State var right = false
        @Previewable @State var selected: UUID? = nil

        let container = PreviewContainer.shared
        Canvas2PreviewFixtures.ensureSeeded(into: container.context)

        let folders = (try? container.context.fetch(
            FetchDescriptor<ChatFolderEntity>(sortBy: [SortDescriptor(\.orderIndex)]))) ?? []
        let sessions = (try? container.context.fetch(
            FetchDescriptor<ChatSessionEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []

        return ModernSidebarLeft(
            isVisible: $visible,
            rightSidebarVisible: $right,
            sessions: sessions,
            folders: folders,
            selectedConversationID: $selected,
            onNewConversation: {}
        )
        .modelContainer(container.container)
        .frame(width: 320, height: 760)
        .padding()
    }
#endif
