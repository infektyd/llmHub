//
//  MemoryViewerViewModel.swift
//  llmHub
//
//  Created by Agent on 01/14/26.
//

import Foundation
import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.llmhub", category: "MemoryViewer")

/// ViewModel for the Memory Viewer settings panel.
@MainActor
@Observable
final class MemoryViewerViewModel {
    
    // MARK: - State
    
    var memories: [Memory] = []
    var statistics: MemoryStatistics?
    var isLoading: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""
    var selectedScope: MemoryScope? = nil
    var sortOrder: SortOrder = .recentlyAccessed
    
    enum SortOrder: String, CaseIterable {
        case recentlyAccessed = "Recently Accessed"
        case recentlyCreated = "Recently Created"
        case mostUsed = "Most Used"
        case confidence = "Confidence"
    }
    
    // MARK: - Computed
    
    var filteredMemories: [Memory] {
        var result = memories
        
        // Scope filter
        if let scope = selectedScope {
            switch scope {
            case .global:
                result = result.filter { $0.providerID == nil }
            case .provider:
                result = result.filter { $0.providerID != nil }
            }
        }
        
        // Search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { memory in
                memory.summary.lowercased().contains(query) ||
                memory.keywords.contains { $0.lowercased().contains(query) } ||
                memory.userFacts.contains { $0.statement.lowercased().contains(query) } ||
                memory.preferences.contains { 
                    $0.topic.lowercased().contains(query) || 
                    $0.value.lowercased().contains(query) 
                }
            }
        }
        
        // Sort
        switch sortOrder {
        case .recentlyAccessed:
            result.sort { $0.lastAccessedAt > $1.lastAccessedAt }
        case .recentlyCreated:
            result.sort { $0.createdAt > $1.createdAt }
        case .mostUsed:
            result.sort { $0.accessCount > $1.accessCount }
        case .confidence:
            result.sort { $0.confidence > $1.confidence }
        }
        
        return result
    }
    
    var globalCount: Int { memories.filter { $0.providerID == nil }.count }
    var providerCount: Int { memories.filter { $0.providerID != nil }.count }
    
    // MARK: - Actions
    
    func load(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil
        
        let service = MemoryManagementService()
        
        do {
            memories = try service.fetchAll(modelContext: modelContext)
            statistics = try service.statistics(modelContext: modelContext)
            logger.info("Loaded \(self.memories.count) memories")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load memories: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func delete(_ memory: Memory, modelContext: ModelContext) async {
        let service = MemoryManagementService()
        
        do {
            try service.delete(id: memory.id, modelContext: modelContext)
            memories.removeAll { $0.id == memory.id }
            statistics = try service.statistics(modelContext: modelContext)
            logger.info("Deleted memory: \(memory.id)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func deleteAll(modelContext: ModelContext) async {
        let service = MemoryManagementService()
        
        for memory in memories {
            try? service.delete(id: memory.id, modelContext: modelContext)
        }
        
        memories = []
        statistics = try? service.statistics(modelContext: modelContext)
        logger.info("Deleted all memories")
    }
    
    func runCleanup(modelContext: ModelContext) async {
        let service = MemoryManagementService()
        
        let flagged = await service.flagUnused(modelContext: modelContext)
        let cleaned = await service.cleanupFlagged(modelContext: modelContext)
        
        logger.info("Cleanup: flagged \(flagged), cleaned \(cleaned)")
        
        // Reload
        await load(modelContext: modelContext)
    }
}
