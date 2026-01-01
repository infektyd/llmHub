//
//  NeonSidebar.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftData
import SwiftUI
import os

private let sidebarLogger = Logger(subsystem: "com.llmhub", category: "Sidebar")

struct NeonSidebar: View {
    @Environment(WorkbenchViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse) private var sessions:
        [ChatSessionEntity]

    @State private var sidebarVM = SidebarViewModel()
    @State private var distillationService = ConversationDistillationService()

    var body: some View {
        VStack(spacing: 0) {
            // Header with New Chat button
            headerView

            // Grouping Mode Picker
            groupingPicker

            // Cleanup Banner (if needed)
            if sidebarVM.cleanupCount(modelContext: modelContext) > 0 {
                CleanupBannerView(
                    flaggedCount: sidebarVM.cleanupCount(modelContext: modelContext)
                ) {
                    sidebarVM.showCleanupSheet = true
                }
            }

            // Search Bar
            searchBar

            // Conversation List
            ScrollView {
                VStack(spacing: 0) {
                    let sectionList = sidebarVM.sections(from: sessions)

                    ForEach(sectionList) { section in
                        sectionView(section)
                    }

                    // Archived Section (at bottom)
                    if let archivedSection = sidebarVM.archivedSection(from: sessions) {
                        Divider()
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)

                        CollapsibleSectionHeader(
                            title: archivedSection.title,
                            icon: archivedSection.icon,
                            count: archivedSection.totalCount,
                            isCollapsed: sidebarVM.isCollapsed(archivedSection.title)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                sidebarVM.toggleCollapsed(archivedSection.title)
                            }
                        }

                        if !sidebarVM.isCollapsed(archivedSection.title) {
                            ForEach(archivedSection.sessions) { session in
                                conversationRowView(for: session)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(sidebarBackground)
        .focusable()
        .onKeyPress(.delete) {
            handleDeleteKeyPress()
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.clearSelection()
            return .handled
        }
        .sheet(isPresented: $sidebarVM.showCleanupSheet) {
            CleanupReviewSheet(sidebarViewModel: sidebarVM)
        }
        .alert(
            "Incomplete Distillation",
            isPresented: Bindable(viewModel).showIncompleteMemoryDeleteWarning
        ) {
            Button("Delete", role: .destructive) {
                viewModel.performPendingDeletion(modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteConversationIDs = []
                viewModel.showIncompleteMemoryDeleteWarning = false
            }
        } message: {
            Text(
                "This conversation has partial memories from an incomplete distillation. Review them before deleting—they may contain complete/useful facts, preferences, or artifacts."
            )
        }
        .onAppear {
            // Run cleanup check on appear
            sidebarVM.runCleanupCheck(modelContext: modelContext)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text("Conversations")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // Show selection count if multi-selecting
            if !viewModel.selectedConversationIDs.isEmpty {
                Text("\(viewModel.selectedConversationIDs.count) selected")
                    .font(.caption)
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppColors.accent.opacity(0.2))
                    )
            }

            Button(action: { viewModel.createNewConversation(modelContext: modelContext) }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Grouping Picker

    private var groupingPicker: some View {
        Picker("Group by", selection: $sidebarVM.groupingMode) {
            ForEach(SidebarViewModel.GroupingMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)
                .font(.system(size: 14))

            TextField("Search conversations...", text: $sidebarVM.searchQuery)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(10)
        .background(searchBarBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Section View

    @ViewBuilder
    private func sectionView(_ section: SidebarSection) -> some View {
        CollapsibleSectionHeader(
            title: section.title,
            icon: section.icon,
            count: section.totalCount,
            isCollapsed: sidebarVM.isCollapsed(section.title)
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarVM.toggleCollapsed(section.title)
            }
        }

        if !sidebarVM.isCollapsed(section.title) {
            ForEach(section.sessions) { session in
                conversationRowView(for: session)
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func conversationRowView(for session: ChatSessionEntity) -> some View {
        ConversationRow(
            session: session,
            isSelected: viewModel.selectedConversationID == session.id,
            isMultiSelected: viewModel.isMultiSelected(id: session.id)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    handleTapWithModifiers(session: session)
                }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.requestDeleteConversation(id: session.id, modelContext: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                archiveSession(session)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                togglePin(session)
            } label: {
                Label(
                    session.isPinned ? "Unpin" : "Pin",
                    systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            .tint(.blue)
        }
        .contextMenu {
            conversationContextMenu(for: session)
        }
    }

    @ViewBuilder
    private func conversationContextMenu(for session: ChatSessionEntity) -> some View {
        if !viewModel.selectedConversationIDs.isEmpty {
            Button(
                role: .destructive,
                action: {
                    viewModel.requestDeleteSelectedConversations(modelContext: modelContext)
                }
            ) {
                Label(
                    "Delete Selected (\(viewModel.selectedConversationIDs.count))",
                    systemImage: "trash")
            }

            Divider()

            Button(action: {
                viewModel.clearSelection()
            }) {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
        } else {
            // Pin/Unpin
            Button(action: { togglePin(session) }) {
                Label(
                    session.isPinned ? "Unpin" : "Pin",
                    systemImage: session.isPinned ? "pin.slash" : "pin.fill")
            }

            // Archive/Unarchive
            Button(action: { archiveSession(session) }) {
                Label(session.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }

            // Mark Complete
            Button(action: { markComplete(session) }) {
                Label(
                    session.isComplete ? "Mark Incomplete" : "Mark Complete",
                    systemImage: session.isComplete ? "circle" : "checkmark.circle")
            }

            Divider()

            Button(action: {
                viewModel.toggleSelection(id: session.id)
            }) {
                Label("Select", systemImage: "checkmark.circle")
            }

            Button(
                role: .destructive,
                action: {
                    viewModel.requestDeleteConversation(id: session.id, modelContext: modelContext)
                }
            ) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func togglePin(_ session: ChatSessionEntity) {
        session.isPinned.toggle()
        session.updatedAt = Date()
        try? modelContext.save()
    }

    private func archiveSession(_ session: ChatSessionEntity) {
        // Phase 2 Memory: distill on archive/unarchive toggle.
        session.triggerDistillation(
            distillationService: distillationService,
            modelContext: modelContext
        )

        session.isArchived.toggle()
        session.flaggedForCleanupAt = nil
        session.updatedAt = Date()
        try? modelContext.save()
    }

    private func markComplete(_ session: ChatSessionEntity) {
        session.isComplete.toggle()
        session.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Event Handlers

    private func handleTapWithModifiers(session: ChatSessionEntity) {
        #if os(macOS)
            let event = NSApp.currentEvent
            let flags = event?.modifierFlags ?? []

            if flags.contains(.command) {
                viewModel.toggleSelection(id: session.id)
            } else if flags.contains(.shift) {
                let allSessions = sessions.filter { !$0.isArchived }
                viewModel.selectRange(to: session.id, in: allSessions)
            } else {
                if !viewModel.selectedConversationIDs.isEmpty {
                    viewModel.clearSelection()
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectedConversationID = session.id
                }
            }
        #else
            if !viewModel.selectedConversationIDs.isEmpty {
                viewModel.clearSelection()
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedConversationID = session.id
            }
        #endif
    }

    private func handleDeleteKeyPress() {
        if !viewModel.selectedConversationIDs.isEmpty {
            viewModel.requestDeleteSelectedConversations(modelContext: modelContext)
        } else if let selectedID = viewModel.selectedConversationID {
            viewModel.requestDeleteConversation(id: selectedID, modelContext: modelContext)
        }
    }

    // MARK: - Backgrounds

    private var sidebarBackground: some View {
        Color.clear.glassEffect(.regular, in: Rectangle())
    }

    @ViewBuilder
    private var searchBarBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .glassEffect(GlassEffect.regular.interactive(), in: .rect(cornerRadius: 8))
    }
}
// MARK: - Previews

#Preview("Neon Sidebar") {
    NeonSidebar()
        .frame(width: 260)
        .previewEnvironment()
}
