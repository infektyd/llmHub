//
//  CleanupReviewSheet.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import SwiftData
import SwiftUI

/// Sheet for reviewing and batch-managing flagged conversations.
struct CleanupReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme

    @Bindable var sidebarViewModel: SidebarViewModel

    @State private var flaggedSessions: [ChatSessionEntity] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var showIncompleteMemoryDeleteWarning: Bool = false
    @State private var pendingDeleteSessions: [ChatSessionEntity] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .foregroundColor(theme.textSecondary.opacity(0.2))

            // Stats
            statsView

            // Session List
            if flaggedSessions.isEmpty {
                emptyStateView
            } else {
                sessionListView
            }

            Divider()
                .foregroundColor(theme.textSecondary.opacity(0.2))

            // Bulk Actions
            bulkActionsView
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(sheetBackground)
        .onAppear {
            loadFlaggedSessions()
        }
        .alert(
            "Incomplete Distillation",
            isPresented: $showIncompleteMemoryDeleteWarning
        ) {
            Button("Delete", role: .destructive) {
                let sessionsToDelete = pendingDeleteSessions
                guard !sessionsToDelete.isEmpty else {
                    showIncompleteMemoryDeleteWarning = false
                    return
                }

                sidebarViewModel.deleteSessions(sessionsToDelete, modelContext: modelContext)
                let ids = Set(sessionsToDelete.map { $0.id })
                flaggedSessions.removeAll { ids.contains($0.id) }
                pendingDeleteSessions.removeAll()
                showIncompleteMemoryDeleteWarning = false
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSessions.removeAll()
                showIncompleteMemoryDeleteWarning = false
            }
        } message: {
            Text(
                "This conversation has partial memories from an incomplete distillation. Review them before deleting—they may contain complete/useful facts, preferences, or artifacts."
            )
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cleanup Review")
                    .font(.headline)
                    .foregroundColor(theme.textPrimary)

                Text(
                    "\(flaggedSessions.count) conversation\(flaggedSessions.count == 1 ? "" : "s") ready for cleanup"
                )
                .font(.caption)
                .foregroundColor(theme.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Stats

    private var statsView: some View {
        HStack(spacing: 16) {
            StatPill(
                icon: "clock",
                label: "Quick Questions",
                count: flaggedSessions.filter {
                    $0.lifecycleIntent == ConversationIntent.quickQuestion.rawValue
                }.count,
                color: .orange
            )

            StatPill(
                icon: "doc.text",
                label: "No Artifacts",
                count: flaggedSessions.filter { !$0.hasArtifacts }.count,
                color: .blue
            )

            StatPill(
                icon: "archivebox",
                label: "Archived",
                count: flaggedSessions.filter { $0.isArchived }.count,
                color: .purple
            )
        }
        .padding()
    }

    // MARK: - Session List

    private var sessionListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(flaggedSessions) { session in
                    CleanupSessionRow(
                        session: session,
                        isSelected: selectedIDs.contains(session.id),
                        onToggle: { toggleSelection(session) },
                        onArchive: { archiveSession(session) },
                        onDelete: { deleteSession(session) },
                        onKeep: { keepSession(session) }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("All Clean!")
                .font(.headline)
                .foregroundColor(theme.textPrimary)

            Text("No conversations need cleanup review.")
                .font(.subheadline)
                .foregroundColor(theme.textSecondary)

            Spacer()
        }
    }

    // MARK: - Bulk Actions

    private var bulkActionsView: some View {
        HStack(spacing: 12) {
            Button(action: keepAll) {
                Label("Keep All", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .disabled(flaggedSessions.isEmpty)

            Button(action: archiveAll) {
                Label("Archive All", systemImage: "archivebox")
            }
            .buttonStyle(.bordered)
            .disabled(flaggedSessions.isEmpty)

            Spacer()

            Button(role: .destructive, action: deleteAll) {
                Label("Delete All", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(flaggedSessions.isEmpty)
        }
        .padding()
    }

    // MARK: - Background

    @ViewBuilder
    private var sheetBackground: some View {
        if theme.usesGlassEffect {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            theme.backgroundPrimary
        }
    }

    // MARK: - Actions

    private func loadFlaggedSessions() {
        flaggedSessions = sidebarViewModel.flaggedSessions(modelContext: modelContext)
    }

    private func toggleSelection(_ session: ChatSessionEntity) {
        if selectedIDs.contains(session.id) {
            selectedIDs.remove(session.id)
        } else {
            selectedIDs.insert(session.id)
        }
    }

    private func archiveSession(_ session: ChatSessionEntity) {
        sidebarViewModel.archiveSessions([session], modelContext: modelContext)
        flaggedSessions.removeAll { $0.id == session.id }
    }

    private func deleteSession(_ session: ChatSessionEntity) {
        requestDeleteSessions([session])
    }

    private func keepSession(_ session: ChatSessionEntity) {
        sidebarViewModel.keepSessions([session], modelContext: modelContext)
        flaggedSessions.removeAll { $0.id == session.id }
    }

    private func keepAll() {
        sidebarViewModel.keepSessions(flaggedSessions, modelContext: modelContext)
        flaggedSessions.removeAll()
    }

    private func archiveAll() {
        sidebarViewModel.archiveSessions(flaggedSessions, modelContext: modelContext)
        flaggedSessions.removeAll()
    }

    private func deleteAll() {
        requestDeleteSessions(flaggedSessions)
    }

    private func requestDeleteSessions(_ sessions: [ChatSessionEntity]) {
        guard !sessions.isEmpty else { return }

        let ids = sessions.map { $0.id }
        let hasAnyIncomplete = ids.contains { id in
            hasIncompleteMemories(for: id)
        }

        if hasAnyIncomplete {
            pendingDeleteSessions = sessions
            showIncompleteMemoryDeleteWarning = true
            return
        }

        sidebarViewModel.deleteSessions(sessions, modelContext: modelContext)
        let idSet = Set(ids)
        flaggedSessions.removeAll { idSet.contains($0.id) }
    }

    private func hasIncompleteMemories(for sessionID: UUID) -> Bool {
        do {
            let count = try modelContext.fetchCount(
                FetchDescriptor<MemoryEntity>(
                    predicate: #Predicate { $0.sourceSessionID == sessionID && !$0.isComplete }
                )
            )
            return count > 0
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)

            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

private struct CleanupSessionRow: View {
    let session: ChatSessionEntity
    let isSelected: Bool
    let onToggle: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onKeep: () -> Void

    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? theme.accent : theme.textSecondary)
            }
            .buttonStyle(.plain)

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let intent = session.lifecycleIntent {
                        Text(intent)
                            .font(.system(size: 10))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.textSecondary.opacity(0.1))
                            )
                    }

                    Text(timeAgo(from: session.lastActivityAt ?? session.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(theme.textSecondary.opacity(0.7))
                }
            }

            Spacer()

            // Quick actions on hover
            if isHovered {
                HStack(spacing: 8) {
                    IconButton(icon: "checkmark", color: .green, action: onKeep)
                    IconButton(icon: "archivebox", color: .orange, action: onArchive)
                    IconButton(icon: "trash", color: .red, action: onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovered ? theme.textPrimary.opacity(0.04) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)

        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

private struct IconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(color.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}
