//
//  SidebarViewModel.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.llmhub", category: "SidebarVM")

// MARK: - Sidebar Section Types

/// Represents a section in the sidebar with grouped sessions.
struct SidebarSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var sessions: [ChatSessionEntity]
    var subsections: [SidebarSubsection] = []
    var isCollapsed: Bool = false

    var isEmpty: Bool {
        sessions.isEmpty && subsections.allSatisfy { $0.sessions.isEmpty }
    }

    var totalCount: Int {
        if subsections.isEmpty {
            return sessions.count
        }
        return subsections.reduce(0) { $0 + $1.sessions.count }
    }
}

/// Represents a time-based subsection within a section.
struct SidebarSubsection: Identifiable {
    let id = UUID()
    let title: String
    let sessions: [ChatSessionEntity]
}

// MARK: - Sidebar ViewModel

/// ViewModel managing sidebar state including grouping, filtering, and cleanup.
@Observable
@MainActor
final class SidebarViewModel {

    // MARK: - Grouping Mode

    /// The available grouping modes for the sidebar.
    enum GroupingMode: String, CaseIterable, Identifiable {
        case byModel = "Model"
        case byTime = "Time"
        case byCategory = "Category"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .byModel: return "cpu"
            case .byTime: return "clock"
            case .byCategory: return "folder"
            }
        }
    }

    // MARK: - State

    /// Current grouping mode for the sidebar.
    var groupingMode: GroupingMode = .byModel

    /// Search query for filtering sessions.
    var searchQuery: String = ""

    /// Whether to show archived sessions.
    var showArchived: Bool = false

    /// Whether to show the cleanup review sheet.
    var showCleanupSheet: Bool = false

    /// Collapsed state for each section (keyed by section title).
    var collapsedSections: Set<String> = ["📦 Archived"]

    // MARK: - Services

    private let lifecycleService = ConversationLifecycleService()

    // MARK: - Computed Sections

    /// Generates sidebar sections based on current grouping mode and filters.
    func sections(from sessions: [ChatSessionEntity]) -> [SidebarSection] {
        let filtered = filterSessions(sessions)

        switch groupingMode {
        case .byModel:
            return groupByModel(filtered)
        case .byTime:
            return groupByTime(filtered)
        case .byCategory:
            return groupByCategory(filtered)
        }
    }

    /// Returns archived sessions as a separate section.
    func archivedSection(from sessions: [ChatSessionEntity]) -> SidebarSection? {
        let archived = sessions.filter { $0.isArchived }
        guard !archived.isEmpty else { return nil }

        return SidebarSection(
            title: "📦 Archived",
            icon: "archivebox",
            sessions: archived.sorted { $0.updatedAt > $1.updatedAt },
            isCollapsed: collapsedSections.contains("📦 Archived")
        )
    }

    // MARK: - Filtering

    private func filterSessions(_ sessions: [ChatSessionEntity]) -> [ChatSessionEntity] {
        var result = sessions

        // Exclude archived from main view
        result = result.filter { !$0.isArchived }

        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { session in
                session.displayTitle.lowercased().contains(query)
                    || session.afmTopicsArray.contains { $0.lowercased().contains(query) }
                    || (session.afmCategory?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    // MARK: - Grouping by Model

    private func groupByModel(_ sessions: [ChatSessionEntity]) -> [SidebarSection] {
        var sections: [SidebarSection] = []

        // Pinned Section
        let pinned = sessions.filter { $0.isPinned }
        if !pinned.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Pinned",
                    icon: "pin.fill",
                    sessions: pinned.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        // Group remaining by model
        let unpinned = sessions.filter { !$0.isPinned }
        let byModel = Dictionary(grouping: unpinned) { $0.model.isEmpty ? "Unknown" : $0.model }
        let sortedModels = byModel.keys.sorted()

        for model in sortedModels {
            guard let modelSessions = byModel[model] else { continue }

            // Time-based subsections within each model
            let subsections = createTimeSubsections(for: modelSessions)

            sections.append(
                SidebarSection(
                    title: modelDisplayName(model),
                    icon: providerIcon(for: model),
                    sessions: modelSessions.sorted { $0.updatedAt > $1.updatedAt },
                    subsections: subsections
                ))
        }

        return sections
    }

    // MARK: - Grouping by Time

    private func groupByTime(_ sessions: [ChatSessionEntity]) -> [SidebarSection] {
        var sections: [SidebarSection] = []

        // Pinned Section
        let pinned = sessions.filter { $0.isPinned }
        if !pinned.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Pinned",
                    icon: "pin.fill",
                    sessions: pinned.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        let unpinned = sessions.filter { !$0.isPinned }
        let calendar = Calendar.current
        let now = Date()

        // Today
        let today = unpinned.filter { calendar.isDateInToday($0.updatedAt) }
        if !today.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Today",
                    icon: "sun.max",
                    sessions: today.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        // Yesterday
        let yesterday = unpinned.filter { calendar.isDateInYesterday($0.updatedAt) }
        if !yesterday.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Yesterday",
                    icon: "clock.arrow.circlepath",
                    sessions: yesterday.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        // This Week (not today or yesterday)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let thisWeek = unpinned.filter { session in
            !calendar.isDateInToday(session.updatedAt)
                && !calendar.isDateInYesterday(session.updatedAt) && session.updatedAt > weekAgo
        }
        if !thisWeek.isEmpty {
            sections.append(
                SidebarSection(
                    title: "This Week",
                    icon: "calendar",
                    sessions: thisWeek.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        // This Month
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        let thisMonth = unpinned.filter { session in
            session.updatedAt <= weekAgo && session.updatedAt > monthAgo
        }
        if !thisMonth.isEmpty {
            sections.append(
                SidebarSection(
                    title: "This Month",
                    icon: "calendar.badge.clock",
                    sessions: thisMonth.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        // Older
        let older = unpinned.filter { $0.updatedAt <= monthAgo }
        if !older.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Older",
                    icon: "clock.badge",
                    sessions: older.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        return sections
    }

    // MARK: - Grouping by Category

    private func groupByCategory(_ sessions: [ChatSessionEntity]) -> [SidebarSection] {
        var sections: [SidebarSection] = []

        // Pinned Section
        let pinned = sessions.filter { $0.isPinned }
        if !pinned.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Pinned",
                    icon: "pin.fill",
                    sessions: pinned.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        let unpinned = sessions.filter { !$0.isPinned }

        // Group by category
        for category in ConversationCategory.allCases {
            let categorySessions = unpinned.filter { session in
                session.afmCategory == category.rawValue
            }

            if !categorySessions.isEmpty {
                sections.append(
                    SidebarSection(
                        title: category.rawValue.capitalized,
                        icon: category.icon,
                        sessions: categorySessions.sorted { $0.updatedAt > $1.updatedAt }
                    ))
            }
        }

        // Uncategorized
        let uncategorized = unpinned.filter {
            $0.afmCategory == nil || $0.afmCategory?.isEmpty == true
        }
        if !uncategorized.isEmpty {
            sections.append(
                SidebarSection(
                    title: "Uncategorized",
                    icon: "questionmark.folder",
                    sessions: uncategorized.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        return sections
    }

    // MARK: - Time Subsections

    private func createTimeSubsections(for sessions: [ChatSessionEntity]) -> [SidebarSubsection] {
        let calendar = Calendar.current

        let today = sessions.filter { calendar.isDateInToday($0.updatedAt) }
        let yesterday = sessions.filter { calendar.isDateInYesterday($0.updatedAt) }
        let older = sessions.filter {
            !calendar.isDateInToday($0.updatedAt) && !calendar.isDateInYesterday($0.updatedAt)
        }

        var subsections: [SidebarSubsection] = []

        if !today.isEmpty {
            subsections.append(
                SidebarSubsection(
                    title: "Today",
                    sessions: today.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        if !yesterday.isEmpty {
            subsections.append(
                SidebarSubsection(
                    title: "Yesterday",
                    sessions: yesterday.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        if !older.isEmpty {
            subsections.append(
                SidebarSubsection(
                    title: "Older",
                    sessions: older.sorted { $0.updatedAt > $1.updatedAt }
                ))
        }

        return subsections
    }

    // MARK: - Display Helpers

    private func modelDisplayName(_ modelID: String) -> String {
        if modelID.hasPrefix("claude-") {
            let parts = modelID.components(separatedBy: "-")
            if parts.count >= 2 {
                return "Claude \(parts[1].capitalized)"
            }
        } else if modelID.hasPrefix("gpt-") {
            return modelID.replacingOccurrences(of: "gpt-", with: "GPT-")
                .replacingOccurrences(of: "-", with: " ")
        } else if modelID.hasPrefix("gemini-") {
            return modelID.replacingOccurrences(of: "gemini-", with: "Gemini ")
        } else if modelID.hasPrefix("grok-") {
            return modelID.replacingOccurrences(of: "grok-", with: "Grok ")
        }
        return modelID
    }

    private func providerIcon(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("gpt") { return "sparkles" }
        if lower.contains("claude") { return "brain.head.profile" }
        if lower.contains("gemini") { return "cloud.fill" }
        if lower.contains("grok") { return "x.circle.fill" }
        if lower.contains("mistral") { return "wind" }
        return "cpu"
    }

    // MARK: - Collapse State

    func isCollapsed(_ sectionTitle: String) -> Bool {
        collapsedSections.contains(sectionTitle)
    }

    func toggleCollapsed(_ sectionTitle: String) {
        if collapsedSections.contains(sectionTitle) {
            collapsedSections.remove(sectionTitle)
        } else {
            collapsedSections.insert(sectionTitle)
        }
    }

    // MARK: - Cleanup Interface

    /// Returns the count of sessions needing cleanup review.
    func cleanupCount(modelContext: ModelContext) -> Int {
        lifecycleService.flaggedCount(modelContext: modelContext)
    }

    /// Runs staleness check and flags conversations.
    @discardableResult
    func runCleanupCheck(modelContext: ModelContext) -> Int {
        lifecycleService.flagStaleConversations(modelContext: modelContext)
    }

    /// Returns flagged sessions for the cleanup sheet.
    func flaggedSessions(modelContext: ModelContext) -> [ChatSessionEntity] {
        lifecycleService.flaggedSessions(modelContext: modelContext)
    }

    /// Archives sessions.
    func archiveSessions(_ sessions: [ChatSessionEntity], modelContext: ModelContext) {
        lifecycleService.archiveAll(sessions, modelContext: modelContext)
    }

    /// Deletes sessions.
    func deleteSessions(_ sessions: [ChatSessionEntity], modelContext: ModelContext) {
        lifecycleService.deleteAll(sessions, modelContext: modelContext)
    }

    /// Keeps sessions (removes from cleanup queue).
    func keepSessions(_ sessions: [ChatSessionEntity], modelContext: ModelContext) {
        lifecycleService.keepAll(sessions, modelContext: modelContext)
    }
}
