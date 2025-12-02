//
//  WorkbenchViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing the main workbench state, including navigation, selection, and tool execution visibility.
@Observable
class WorkbenchViewModel {
    /// The currently selected conversation identifier.
    var selectedConversationID: UUID?
    /// The visibility state of the navigation split view columns.
    var columnVisibility: NavigationSplitViewVisibility = .all
    /// Controls the visibility of the tool inspector pane.
    var toolInspectorVisible: Bool = false
    /// The currently selected LLM provider.
    var selectedProvider: UILLMProvider?
    /// The currently selected model within the provider.
    var selectedModel: UILLMModel?
    /// The currently active tool execution being displayed.
    var activeToolExecution: ToolExecution?

    // Search
    /// The current search text for filtering conversations.
    var searchText: String = ""
    /// The set of expanded folder IDs in the sidebar.
    var expandedFolders: Set<UUID> = []

    /// Initializes a new `WorkbenchViewModel` with default settings.
    init() {
        // Set default provider and model
        if let firstProvider = UILLMProvider.sampleProviders.first {
            selectedProvider = firstProvider
            selectedModel = firstProvider.models.first
        }
    }

    /// Creates a new conversation session and selects it.
    /// - Parameter modelContext: The SwiftData context used for persistence.
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

    /// Deletes a conversation by its ID.
    /// - Parameters:
    ///   - id: The UUID of the conversation to delete.
    ///   - modelContext: The SwiftData context.
    func deleteConversation(id: UUID, modelContext: ModelContext) {
        // Implementation for deleting conversation
        // This would typically involve finding the entity and deleting it
        // For now, we'll rely on the view to handle deletion via SwipeActions or context menu
        // calling a delete function that takes the entity
    }
}
