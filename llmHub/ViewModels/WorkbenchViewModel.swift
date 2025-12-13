//
//  WorkbenchViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import SwiftData
import SwiftUI
import os

private let vmLogger = Logger(subsystem: "com.llmhub", category: "WorkbenchVM")

/// ViewModel managing the main workbench state, including navigation, selection, and tool execution visibility.
@Observable
@MainActor
class WorkbenchViewModel {
    /// The currently selected conversation identifier.
    var selectedConversationID: UUID? {
        didSet {
            print("🟢 VIEWMODEL: selectedConversationID changed: \(String(describing: oldValue)) → \(String(describing: selectedConversationID))")
        }
    }
    /// Set of conversation IDs selected for multi-select operations (Cmd+click).
    var selectedConversationIDs: Set<UUID> = []
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

    // MARK: - Token & Cost Stats
    var currentSessionTokens: Int = 0
    var currentSessionCost: Decimal = 0.0
    var tokenPercentage: Double = 0.0

    /// Initializes a new `WorkbenchViewModel` with default settings.
    init() {
        // selectedProvider and selectedModel will be set from real ModelRegistry data
        // via onAppear in NeonWorkbenchWindow
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

    /// Toggles selection for a conversation (Cmd+click behavior).
    /// - Parameter id: The UUID of the conversation to toggle.
    func toggleSelection(id: UUID) {
        if selectedConversationIDs.contains(id) {
            selectedConversationIDs.remove(id)
        } else {
            selectedConversationIDs.insert(id)
        }
    }

    /// Selects a range of conversations (Shift+click behavior).
    /// - Parameters:
    ///   - targetID: The conversation ID to select up to.
    ///   - sessions: All available sessions in order.
    func selectRange(to targetID: UUID, in sessions: [ChatSessionEntity]) {
        guard let lastSelected = selectedConversationID ?? selectedConversationIDs.first else {
            selectedConversationIDs.insert(targetID)
            return
        }

        // Find indices
        guard let startIndex = sessions.firstIndex(where: { $0.id == lastSelected }),
              let endIndex = sessions.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        // Select all in range
        let range = startIndex <= endIndex ? startIndex...endIndex : endIndex...startIndex
        for index in range {
            selectedConversationIDs.insert(sessions[index].id)
        }
    }

    /// Checks if a conversation is multi-selected.
    /// - Parameter id: The UUID to check.
    /// - Returns: True if the conversation is in the multi-select set.
    func isMultiSelected(id: UUID) -> Bool {
        selectedConversationIDs.contains(id)
    }

    /// Deletes a single conversation by its ID.
    /// - Parameters:
    ///   - id: The UUID of the conversation to delete.
    ///   - modelContext: The SwiftData context.
    func deleteConversation(id: UUID, modelContext: ModelContext) {
        let fetchDescriptor = FetchDescriptor<ChatSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let sessions = try modelContext.fetch(fetchDescriptor)
            if let session = sessions.first {
                modelContext.delete(session)
                try modelContext.save()

                // Clear selection if deleted
                if selectedConversationID == id {
                    selectedConversationID = nil
                }
                selectedConversationIDs.remove(id)
            }
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    /// Deletes all currently multi-selected conversations.
    /// - Parameter modelContext: The SwiftData context.
    func deleteSelectedConversations(modelContext: ModelContext) {
        guard !selectedConversationIDs.isEmpty else { return }

        let idsToDelete = Array(selectedConversationIDs)

        for id in idsToDelete {
            deleteConversation(id: id, modelContext: modelContext)
        }

        selectedConversationIDs.removeAll()
    }

    /// Clears the multi-selection set.
    func clearSelection() {
        vmLogger.debug("clearSelection called - was \(self.selectedConversationIDs.count)")
        selectedConversationIDs.removeAll()
    }

    /// Updates token and cost statistics for the given session.
    func updateStats(for session: ChatSessionEntity) {
        let messages = session.messages.map { $0.asDomain() }
        let modelID = session.model
        let contextWindow = selectedModel?.contextWindow ?? 128_000
        
        Task {
            // 1. Estimate Tokens (CPU intensive if long history)
            let totalTokens = TokenEstimator.estimate(messages: messages)
            
            // 2. Calculate Cost (Async/Task for pricing calculation if needed)
            let totalCost = calculateTotalCost(for: messages, modelID: modelID)
            
            // 3. Calculate Percentage
            let percentage = min(Double(totalTokens) / Double(contextWindow) * 100.0, 100.0)
            
            await MainActor.run {
                self.currentSessionTokens = totalTokens
                self.currentSessionCost = totalCost
                self.tokenPercentage = percentage
            }
        }
    }

    private func calculateTotalCost(for messages: [ChatMessage], modelID: String) -> Decimal {
        var total: Decimal = 0.0
        let calculator = CostCalculator()
        let pricing = getPricing(for: modelID)
        
        for message in messages {
            if let stored = message.costBreakdown?.totalCost, stored > 0 {
                total += stored
            } else {
                // Estimate based on content
                let tokens = TokenEstimator.estimate(message.content)
                // Heuristic: User/System = Input, Assistant = Output
                let usage: TokenUsage
                if message.role == .assistant {
                    usage = TokenUsage(inputTokens: 0, outputTokens: tokens, cachedTokens: 0)
                } else {
                    usage = TokenUsage(inputTokens: tokens, outputTokens: 0, cachedTokens: 0)
                }
                
                let estimated = calculator.cost(for: usage, pricing: pricing)
                total += estimated.totalCost
            }
        }
        return total
    }

    private func getPricing(for modelID: String) -> PricingMetadata {
        // Approximate generic defaults if ModelRegistry isn't providing specific pricing metadata
        // In a real implementation, this should lookup from ModelRegistry
        let lowerID = modelID.lowercased()
        if lowerID.contains("gpt-4o-mini") {
            return PricingMetadata(inputPer1KUSD: 0.00015, outputPer1KUSD: 0.0006, currency: "USD")
        } else if lowerID.contains("gpt-4o") {
            return PricingMetadata(inputPer1KUSD: 0.005, outputPer1KUSD: 0.015, currency: "USD")
        } else if lowerID.contains("claude-3-5-sonnet") {
            return PricingMetadata(inputPer1KUSD: 0.003, outputPer1KUSD: 0.015, currency: "USD")
        } else if lowerID.contains("claude-3-haiku") {
            return PricingMetadata(inputPer1KUSD: 0.00025, outputPer1KUSD: 0.00125, currency: "USD")
        }
        // Fallback (Generic High-End)
        return PricingMetadata(inputPer1KUSD: 0.005, outputPer1KUSD: 0.015, currency: "USD")
    }
}