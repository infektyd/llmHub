//
//  NeonSidebar.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftData
import SwiftUI

struct NeonSidebar: View {
    @Environment(WorkbenchViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse) private var sessions:
        [ChatSessionEntity]

    var pinnedSessions: [ChatSessionEntity] {
        sessions.filter { $0.isPinned }
    }

    var recentSessions: [ChatSessionEntity] {
        sessions.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with New Chat button
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: { viewModel.createNewConversation(modelContext: modelContext) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.neonElectricBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.neonGray)
                    .font(.system(size: 14))

                TextField("Search conversations...", text: Bindable(viewModel).searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonCharcoal.opacity(0.6))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()
                .background(Color.neonGray.opacity(0.2))

            // Conversation List
            ScrollView {
                VStack(spacing: 0) {
                    // Pinned Section
                    if !pinnedSessions.isEmpty {
                        SectionHeader(title: "Pinned", icon: "pin.fill")

                        ForEach(pinnedSessions) { session in
                            ConversationRow(
                                session: session,
                                isSelected: viewModel.selectedConversationID == session.id
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedConversationID = session.id
                                }
                            }
                        }

                        Divider()
                            .background(Color.neonGray.opacity(0.2))
                            .padding(.vertical, 8)
                    }

                    // Recent Section
                    SectionHeader(title: "Recent", icon: "clock.fill")

                    ForEach(recentSessions) { session in
                        ConversationRow(
                            session: session,
                            isSelected: viewModel.selectedConversationID == session.id
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedConversationID = session.id
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            // Blurred material background with low opacity
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay(Color.neonCharcoal.opacity(0.3))
        )
    }
}
