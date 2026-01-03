//
//  SidebarComponents.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

// MARK: - Sidebar Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Collapsible Section Header

struct CollapsibleSectionHeader: View {
    let title: String
    let icon: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)

                Text(verbatim: "(\(count))")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary.opacity(0.7))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.textSecondary.opacity(0.5))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(.easeInOut(duration: 0.2), value: isCollapsed)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let session: ChatSessionEntity
    let isSelected: Bool
    var isMultiSelected: Bool = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Multi-select checkbox (shown when multi-selecting)
            if isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.accent)
            } else {
                // Emoji indicator or default circle
                if let emoji = session.afmEmoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 14))
                } else {
                    Circle()
                        .fill(isSelected ? AppColors.accentSecondary : AppColors.accent.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                        .lineLimit(1)

                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.accent)
                    }

                    // Cleanup flag indicator
                    if session.flaggedForCleanupAt != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }

                    // Archived indicator
                    if session.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    }

                    Spacer()

                    Text(timeAgo(from: session.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary.opacity(0.7))
                }

                // Category badge (if available) and Tags
                HStack(spacing: 4) {
                    if let category = session.afmCategory, !category.isEmpty {
                        CategoryBadge(category: category)
                    }

                    ForEach(session.tags) { tag in
                        TagPill(tag: tag)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(rowBackground)
        .padding(.horizontal, 12)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Subviews

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isMultiSelected
                    ? AppColors.accent.opacity(0.16)
                    : (isSelected
                        ? AppColors.accent.opacity(0.10)
                        : (isHovered ? AppColors.textPrimary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isMultiSelected
                            ? AppColors.accent.opacity(0.35)
                            : (isSelected ? AppColors.accent.opacity(0.22) : Color.clear),
                        lineWidth: 1
                    )
            )
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: String

    private var categoryColor: Color {
        switch category.lowercased() {
        case "coding": return .blue
        case "research": return .green
        case "creative": return .purple
        case "planning": return .orange
        case "support": return .cyan
        default: return .gray
        }
    }

    var body: some View {
        Text(category.capitalized)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(categoryColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(categoryColor.opacity(0.15))
            )
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: ChatTagEntity

    var tagColor: Color {
        Color(hex: tag.color)
    }

    var body: some View {
        Text(tag.name)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(tagColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tagColor.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(tagColor.opacity(0.5), lineWidth: 0.5)
                    )
            )
    }
}
// MARK: - Previews

#Preview("Sidebar Components") {
    VStack(alignment: .leading, spacing: 20) {
        SectionHeader(title: "Models", icon: "cpu")

        CollapsibleSectionHeader(
            title: "Pinned",
            icon: "pin.fill",
            count: 3,
            isCollapsed: false,
            onToggle: {}
        )

        ConversationRow(
            session: MockData.chatSession(title: "Coding Help"),
            isSelected: true
        )

        ConversationRow(
            session: MockData.chatSession(title: "Research Topic"),
            isSelected: false
        )

        HStack {
            CategoryBadge(category: "Coding")
            CategoryBadge(category: "Research")
            CategoryBadge(category: "Creative")
        }
        .padding(.horizontal)
    }
    .frame(width: 300)
    .padding(.vertical)
    .previewEnvironment()
}
