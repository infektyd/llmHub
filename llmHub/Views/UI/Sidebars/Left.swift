//
//  FloatingSidebarLeft.swift
//  llmHub
//
//  Floating left sidebar for chat threads
//  Appears "on top" of canvas with shadow + border (not glass)
//

import SwiftUI

/// Floating left sidebar showing conversation list
/// Flat matte surface with shadow (no glass blur)
struct FloatingSidebarLeft: View {
    @Binding var isVisible: Bool
    let sessions: [CanvasConversationSummary]
    @Binding var selectedConversationID: UUID?
    let onNewConversation: () -> Void

    @State private var searchText = ""

    private var filteredSessions: [CanvasConversationSummary] {
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
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Search field
            TextField("Search conversations…", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(AppColors.backgroundPrimary.opacity(0.5))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
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
            RoundedRectangle(cornerRadius: 04, style: .continuous)
                .fill(AppColors.backgroundSecondary)
                .shadow(color: AppColors.shadowSmoke, radius: 10, x: 0, y: 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 04, style: .continuous)
                .stroke(AppColors.accentSecondary, lineWidth: 1)
        }
    }

    // MARK: - Private Views

    private func conversationRow(_ session: CanvasConversationSummary) -> some View {
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

#if DEBUG
    #Preview("SidebarLeft - Populated") {
        @Previewable @State var selected: UUID? = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111")
        @Previewable @State var visible = true
        let sessions: [CanvasConversationSummary] = [
            CanvasConversationSummary(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                displayTitle: "💬 Preview Session A",
                updatedAt: Canvas2PreviewFixtures.baseDate,
                isArchived: false
            ),
            CanvasConversationSummary(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                displayTitle: "🔧 Debugging Tools",
                updatedAt: Canvas2PreviewFixtures.baseDate.addingTimeInterval(-3600),
                isArchived: false
            ),
        ]
        FloatingSidebarLeft(
            isVisible: $visible,
            sessions: sessions,
            selectedConversationID: $selected,
            onNewConversation: {}
        )
        .frame(width: 280, height: 600)
        .padding()
    }

    #Preview("SidebarLeft - Empty") {
        @Previewable @State var selected: UUID? = nil
        @Previewable @State var visible = true
        FloatingSidebarLeft(
            isVisible: $visible,
            sessions: [],
            selectedConversationID: $selected,
            onNewConversation: {}
        )
        .frame(width: 280, height: 600)
        .padding()
    }

    #Preview("SidebarLeft - Narrow") {
        @Previewable @State var selected: UUID? = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111")
        @Previewable @State var visible = true
        let sessions: [CanvasConversationSummary] = [
            CanvasConversationSummary(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                displayTitle: "Preview Session With A Very Long Title That Should Truncate",
                updatedAt: Canvas2PreviewFixtures.baseDate,
                isArchived: false
            )
        ]
        FloatingSidebarLeft(
            isVisible: $visible,
            sessions: sessions,
            selectedConversationID: $selected,
            onNewConversation: {}
        )
        .frame(width: 200, height: 600)
        .padding()
    }
#endif
