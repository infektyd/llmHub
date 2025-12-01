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
                .foregroundColor(.neonGray)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.neonGray)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let session: ChatSessionEntity
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Conversation icon/indicator
            Circle()
                .fill(isSelected ? Color.neonFuchsia : Color.neonElectricBlue.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .neonGray)
                        .lineLimit(1)

                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.neonElectricBlue)
                    }

                    Spacer()

                    Text(timeAgo(from: session.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(.neonGray.opacity(0.7))
                }

                // Tags
                if !session.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(session.tags) { tag in
                            TagPill(tag: tag)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.neonCharcoal.opacity(0.8) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.neonFuchsia.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
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

// MARK: - Tag Pill

struct TagPill: View {
    let tag: ChatTagEntity

    var tagColor: Color {
        Color(neonHex: tag.color) ?? .neonElectricBlue
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
