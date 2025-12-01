//
//  WorkbenchViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
class WorkbenchViewModel {
    var selectedConversationID: UUID?
    var columnVisibility: NavigationSplitViewVisibility = .all
    var toolInspectorVisible: Bool = false
    var selectedProvider: UILLMProvider?
    var selectedModel: UILLMModel?
    var activeToolExecution: ToolExecution?

    // Search
    var searchText: String = ""
    var expandedFolders: Set<UUID> = []

    init() {
        // Set default provider and model
        if let firstProvider = UILLMProvider.sampleProviders.first {
            selectedProvider = firstProvider
            selectedModel = firstProvider.models.first
        }
    }

    func createNewConversation(modelContext: ModelContext) {
        let newSession = ChatSession(
            id: UUID(),
            title: "New Conversation",
            providerID: selectedProvider?.name ?? "Unknown",
            model: selectedModel?.name ?? "Unknown",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(
                lastTokenUsage: nil, totalCostUSD: 0, referenceID: UUID().uuidString)
        )

        let entity = ChatSessionEntity(session: newSession)
        modelContext.insert(entity)

        selectedConversationID = newSession.id
    }

    func deleteConversation(id: UUID, modelContext: ModelContext) {
        // Implementation for deleting conversation
        // This would typically involve finding the entity and deleting it
        // For now, we'll rely on the view to handle deletion via SwipeActions or context menu
        // calling a delete function that takes the entity
    }
}
