//
//  FloatingSidebarLeft.swift
//  llmHub
//
//  Floating left sidebar for chat threads
//  Appears "on top" of canvas with shadow + border (not glass)
//

import SwiftData
import SwiftUI

/// Floating left sidebar showing conversation list
/// Flat matte surface with shadow (no glass blur)
struct FloatingSidebarLeft: View {
    let sessions: [ChatSessionEntity]
    @Binding var selectedConversationID: UUID?
    let onNewConversation: () -> Void

    @State private var searchText = ""

    private var filteredSessions: [ChatSessionEntity] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return sessions.filter { !$0.isArchived } }
        return sessions.filter {
            !$0.isArchived && $0.displayTitle.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Conversations")
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Search field
            TextField("Search conversations…", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.backgroundPrimary.opacity(0.5))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
                }
                .padding(.horizontal, 16)

            Divider()
                .padding(.horizontal, 16)

            // Conversation list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredSessions) { session in
                        conversationRow(session)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Canvas2Colors.panelBackground)
                .shadow(color: Canvas2Colors.panelShadow, radius: 20, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Canvas2Colors.panelBorder, lineWidth: 1)
        }
    }

    // MARK: - Private Views

    private func conversationRow(_ session: ChatSessionEntity) -> some View {
        Button {
            selectedConversationID = session.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(
                        .system(
                            size: 13,
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        selectedConversationID == session.id
                            ? AppColors.accent.opacity(0.1) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }
}
