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
    @Environment(\.theme) private var theme
    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse) private var sessions:
        [ChatSessionEntity]
    @AppStorage("glassOpacity_sidebar") private var glassOpacity: Double = 0.8

    var pinnedSessions: [ChatSessionEntity] {
        sessions.filter { $0.isPinned }
    }

    var recentSessions: [ChatSessionEntity] {
        sessions.filter { !$0.isPinned }
    }

    var body: some View {
        let _ = print("🔄 [NeonSidebar] body evaluated")
        VStack(spacing: 0) {
            // Header with New Chat button
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                // Show selection count if multi-selecting
                if !viewModel.selectedConversationIDs.isEmpty {
                    Text("\(viewModel.selectedConversationIDs.count) selected")
                        .font(.caption)
                        .foregroundColor(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(theme.accent.opacity(0.2))
                        )
                }

                Button(action: { viewModel.createNewConversation(modelContext: modelContext) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.textSecondary)
                    .font(.system(size: 14))

                TextField("Search conversations...", text: Bindable(viewModel).searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(theme.textPrimary)
            }
            .padding(10)
            .background(searchBarBackground)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Conversation List
            ScrollView {
                VStack(spacing: 0) {
                    // Pinned Section
                    if !pinnedSessions.isEmpty {
                        SectionHeader(title: "Pinned", icon: "pin.fill")

                        ForEach(pinnedSessions) { session in
                            conversationRowView(for: session)
                        }
                        Rectangle()
                            .fill(theme.textPrimary.opacity(0.06))
                            .frame(height: 1)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                    }

                    // Recent Section
                    SectionHeader(title: "Recent", icon: "clock.fill")

                    ForEach(recentSessions) { session in
                        conversationRowView(for: session)
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
                    viewModel.deleteSelectedConversations(modelContext: modelContext)
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
            Button(action: {
                viewModel.toggleSelection(id: session.id)
            }) {
                Label("Select", systemImage: "checkmark.circle")
            }

            Button(
                role: .destructive,
                action: {
                    viewModel.deleteConversation(id: session.id, modelContext: modelContext)
                }
            ) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Event Handlers

    private func handleTapWithModifiers(session: ChatSessionEntity) {
        print("🔵 TAP: handleTapWithModifiers called for session: \(session.id)")
        print(
            "🔵 TAP: Current selectedConversationID: \(String(describing: viewModel.selectedConversationID))"
        )

        #if os(macOS)
            // Check modifier keys synchronously from current NSEvent
            let event = NSApp.currentEvent
            let flags = event?.modifierFlags ?? []

            if flags.contains(.command) {
                // Cmd+click: Toggle multi-selection
                print("🔵 TAP: [macOS] Cmd+click detected - toggling multi-selection")
                viewModel.toggleSelection(id: session.id)
            } else if flags.contains(.shift) {
                // Shift+click: Range selection
                print("🔵 TAP: [macOS] Shift+click detected - range selection")
                let allSessions = pinnedSessions + recentSessions
                viewModel.selectRange(to: session.id, in: allSessions)
            } else {
                // Regular click: Clear multi-selection and select single
                print("🔵 TAP: [macOS] Regular click - setting single selection")
                if !viewModel.selectedConversationIDs.isEmpty {
                    viewModel.clearSelection()
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectedConversationID = session.id
                }
                print(
                    "🔵 TAP: Selection after: \(String(describing: viewModel.selectedConversationID))"
                )
            }
        #else
            // iOS/iPadOS: Treat as regular tap
            // Note: For multi-selection on iOS, we would typically use EditMode,
            // but for now we'll just handle single selection.
            print("🔵 TAP: [iOS] Regular tap - setting single selection")
            if !viewModel.selectedConversationIDs.isEmpty {
                viewModel.clearSelection()
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedConversationID = session.id
            }
            print("🔵 TAP: Selection after: \(String(describing: viewModel.selectedConversationID))")
        #endif
    }

    private func handleDeleteKeyPress() {
        if !viewModel.selectedConversationIDs.isEmpty {
            // Delete multi-selected conversations
            print("🗑️ Delete key: Deleting \(viewModel.selectedConversationIDs.count) conversations")
            viewModel.deleteSelectedConversations(modelContext: modelContext)
        } else if let selectedID = viewModel.selectedConversationID {
            // Delete currently selected conversation
            print("🗑️ Delete key: Deleting single conversation")
            viewModel.deleteConversation(id: selectedID, modelContext: modelContext)
        }
    }

    // MARK: - Subviews

    private var sidebarBackground: some View {
        AdaptiveGlassBackground(target: .sidebar)
    }

    private var searchBarBackground: some View {
        Group {
            if theme.usesGlassEffect {
                RoundedRectangle(cornerRadius: 8)
                    .glassEffect(GlassEffect.regular.interactive(), in: .rect(cornerRadius: 8))
                    .opacity(glassOpacity)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.textSecondary.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }
}
