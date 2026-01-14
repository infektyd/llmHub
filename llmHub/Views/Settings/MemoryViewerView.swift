//
//  MemoryViewerView.swift
//  llmHub
//
//  Created by Agent on 01/14/26.
//

import SwiftUI
import SwiftData

struct MemoryViewerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale
    
    @State private var viewModel = MemoryViewerViewModel()
    @State private var selectedMemory: Memory?
    @State private var showDeleteAllConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 16 : 20) {
            SettingsSectionHeader(
                "Memory",
                subtitle: "View and manage what llmHub remembers about you"
            )
            
            // Statistics card
            if let stats = viewModel.statistics {
                statisticsCard(stats)
            }
            
            // Toolbar
            toolbar
            
            // Memory list
            SettingsCard {
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.filteredMemories.isEmpty {
                    emptyState
                } else {
                    memoryList
                }
            }
        }
        .task {
            await viewModel.load(modelContext: modelContext)
        }
        .sheet(item: $selectedMemory) { memory in
            MemoryDetailSheet(memory: memory) {
                Task { await viewModel.delete(memory, modelContext: modelContext) }
            }
        }
        .confirmationDialog(
            "Delete All Memories?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await viewModel.deleteAll(modelContext: modelContext) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(viewModel.memories.count) memories. This cannot be undone.")
        }
    }
    
    // MARK: - Statistics Card
    
    private func statisticsCard(_ stats: MemoryStatistics) -> some View {
        SettingsCard {
            HStack(spacing: uiCompactMode ? 16 : 24) {
                statItem(value: "\(stats.totalCount)", label: "Total", icon: "brain")
                Divider().frame(height: 40)
                statItem(value: "\(stats.globalCount)", label: "Global", icon: "globe")
                Divider().frame(height: 40)
                statItem(value: "\(stats.providerCount)", label: "Provider", icon: "server.rack")
                Divider().frame(height: 40)
                statItem(value: "\(stats.totalAccesses)", label: "Accesses", icon: "arrow.up.arrow.down")
            }
            .padding(uiCompactMode ? 12 : 16)
        }
    }
    
    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16 * uiScale))
                .foregroundStyle(AppColors.accent)
            
            Text(value)
                .font(.system(size: 20 * uiScale, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
            
            Text(label)
                .font(.system(size: 11 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textTertiary)
                
                TextField("Search memories...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.backgroundSecondary)
            }
            
            // Scope filter
            Picker("Scope", selection: $viewModel.selectedScope) {
                Text("All").tag(nil as MemoryScope?)
                Text("Global").tag(MemoryScope.global as MemoryScope?)
                Text("Provider").tag(MemoryScope.provider as MemoryScope?)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            // Sort
            Menu {
                ForEach(MemoryViewerViewModel.SortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            
            Spacer()
            
            // Actions
            Button {
                Task { await viewModel.runCleanup(modelContext: modelContext) }
            } label: {
                Label("Cleanup", systemImage: "trash.slash")
            }
            .help("Remove unused memories")
            
            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label("Delete All", systemImage: "trash")
            }
            .disabled(viewModel.memories.isEmpty)
        }
    }
    
    // MARK: - Memory List
    
    private var memoryList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredMemories) { memory in
                MemoryRowView(memory: memory)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMemory = memory
                    }
                
                if memory.id != viewModel.filteredMemories.last?.id {
                    Divider()
                        .padding(.horizontal, uiCompactMode ? 12 : 16)
                }
            }
        }
    }
    
    // MARK: - States
    
    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(40)
            Spacer()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.textTertiary)
            
            Text("No memories yet")
                .font(.system(size: 16 * uiScale, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            
            Text("Memories are created automatically from your conversations")
                .font(.system(size: 13 * uiScale))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Memory Row

private struct MemoryRowView: View {
    let memory: Memory
    
    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Scope indicator
            Image(systemName: memory.providerID == nil ? "globe" : "server.rack")
                .font(.system(size: 14 * uiScale))
                .foregroundStyle(memory.providerID == nil ? .green : .blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 6) {
                // Summary
                Text(memory.summary)
                    .font(.system(size: 13 * uiScale))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                
                // Keywords
                if !memory.keywords.isEmpty {
                    Text(memory.keywords.prefix(5).joined(separator: " · "))
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
                
                // Metadata
                HStack(spacing: 12) {
                    Label("\(memory.accessCount)", systemImage: "eye")
                    
                    if let providerID = memory.providerID {
                        Label(providerID, systemImage: "server.rack")
                    }
                    
                    Text(memory.createdAt, style: .relative)
                }
                .font(.system(size: 10 * uiScale))
                .foregroundStyle(AppColors.textTertiary)
            }
            
            Spacer()
            
            // Confidence indicator
            ConfidenceBadge(confidence: memory.confidence, isComplete: memory.isComplete)
        }
        .padding(.horizontal, uiCompactMode ? 12 : 16)
        .padding(.vertical, uiCompactMode ? 10 : 12)
        .background {
            Color.clear
        }
    }
}

// MARK: - Confidence Badge

private struct ConfidenceBadge: View {
    let confidence: Double
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            if !isComplete {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(confidenceColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(confidenceColor.opacity(0.15))
        }
    }
    
    private var confidenceColor: Color {
        if !isComplete { return .orange }
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .yellow }
        return .red
    }
}

// MARK: - Memory Detail Sheet

private struct MemoryDetailSheet: View {
    let memory: Memory
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: memory.providerID == nil ? "globe" : "server.rack")
                                .foregroundStyle(memory.providerID == nil ? .green : .blue)
                            
                            Text(memory.providerID ?? "Global Memory")
                                .font(.headline)
                            
                            Spacer()
                            
                            ConfidenceBadge(confidence: memory.confidence, isComplete: memory.isComplete)
                        }
                        
                        Text(memory.summary)
                            .font(.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.backgroundSecondary)
                    }
                    
                    // Facts
                    if !memory.userFacts.isEmpty {
                        detailSection(title: "Facts", icon: "person.fill") {
                            ForEach(memory.userFacts, id: \.statement) { fact in
                                HStack(alignment: .top) {
                                    Text("•")
                                    VStack(alignment: .leading) {
                                        Text(fact.statement)
                                        Text(fact.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Preferences
                    if !memory.preferences.isEmpty {
                        detailSection(title: "Preferences", icon: "slider.horizontal.3") {
                            ForEach(memory.preferences, id: \.topic) { pref in
                                HStack {
                                    Text(pref.topic)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(pref.value)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Decisions
                    if !memory.decisions.isEmpty {
                        detailSection(title: "Decisions", icon: "checkmark.circle") {
                            ForEach(memory.decisions, id: \.decision) { decision in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(decision.decision)
                                    if !decision.context.isEmpty {
                                        Text(decision.context)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Keywords
                    if !memory.keywords.isEmpty {
                        detailSection(title: "Keywords", icon: "tag") {
                            FlowLayout(spacing: 6) {
                                ForEach(memory.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background {
                                            Capsule()
                                                .fill(AppColors.accent.opacity(0.15))
                                        }
                                }
                            }
                        }
                    }
                    
                    // Metadata
                    detailSection(title: "Metadata", icon: "info.circle") {
                        LabeledContent("ID", value: memory.id.uuidString.prefix(8) + "...")
                        LabeledContent("Created", value: memory.createdAt.formatted())
                        LabeledContent("Last Accessed", value: memory.lastAccessedAt.formatted())
                        LabeledContent("Access Count", value: "\(memory.accessCount)")
                        if let sessionID = memory.sourceSessionID {
                            LabeledContent("Source Session", value: sessionID.uuidString.prefix(8) + "...")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Memory Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    
    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.backgroundSecondary)
            }
        }
    }
}

// MARK: - Flow Layout (for keywords)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}
