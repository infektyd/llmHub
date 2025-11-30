//
//  ChatService.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import SwiftData
import OSLog

final class ChatService {
    let modelContext: ModelContext
    let providerRegistry: ProviderRegistry
    private let costCalculator: CostCalculator

    private let logger = Logger(subsystem: "com.llmhub", category: "ChatService")

    init(modelContext: ModelContext, providerRegistry: ProviderRegistry, costCalculator: CostCalculator = CostCalculator()) {
        self.modelContext = modelContext
        self.providerRegistry = providerRegistry
        self.costCalculator = costCalculator
    }

    func loadSessions() throws -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSessionEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    func createSession(providerID: String, model: String) throws -> ChatSession {
        let referenceID = ReferenceFormatter.newReferenceID()
        let session = ChatSession(
            id: UUID(),
            title: "Untitled",
            providerID: providerID,
            model: model,
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: .zero, referenceID: referenceID)
        )
        let entity = ChatSessionEntity(session: session)
        modelContext.insert(entity)
        try modelContext.save()
        return session
    }

    func appendMessage(_ message: ChatMessage, to sessionID: UUID) throws {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ChatServiceError.sessionMissing
        }
        let messageEntity = ChatMessageEntity(message: message)
        messageEntity.session = entity
        entity.messages.append(messageEntity)
        entity.updatedAt = Date()
        try modelContext.save()
    }

    func streamCompletion(for session: ChatSession, userMessage: String, images: [Data] = []) async throws -> AsyncThrowingStream<ProviderEvent, Error> {
        
         var parts: [ChatContentPart] = [.text(userMessage)]
        for imgData in images {
            parts.append(.image(imgData, mimeType: "image/jpeg")) // Defaulting to jpeg for simplicity
        }
        
        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: userMessage,
            parts: parts,
            createdAt: Date(),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil
        )
        
        try appendMessage(message, to: session.id)
        
        // Reload session to get full history
        let updatedSession = try loadSession(id: session.id)
        
        logger.debug("Using provider: \(updatedSession.providerID), model: \(updatedSession.model)")

        // This loop handles tool calls.
        // For streaming, it's tricky because the stream yields chunks.
        // If a tool call occurs, we usually get a specific stop reason or event.
        // LLMProviderProtocol's streamResponse returns ProviderEvent.
        
        let provider = try providerRegistry.provider(for: updatedSession.providerID)
        let request = try provider.buildRequest(messages: updatedSession.messages, model: updatedSession.model)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Initial Request
                    for try await event in provider.streamResponse(from: request) {
                        switch event {
                        case .toolUse(let id, let name, let input):
                            // HANDLE TOOL EXECUTION HERE
                            // 1. Notify UI of tool use?
                            continuation.yield(.toolUse(id: id, name: name, input: input))
                            
                            // 2. Execute Tool (Mock for now, or registry lookup)
                            // In a real agent loop, we'd wait for this stream to finish (accumulating the tool call),
                            // then execute, append result, and call provider again.
                            // Since this is a stream, we can't easily "pause and recurse" inside the stream yield.
                            // A common pattern is: The stream yields the tool call delta.
                            // The client (UI) sees it.
                            // The Service needs to collect the full tool call message.
                            
                            // For this MVP step: we just yield it.
                            // A proper "Agent Loop" usually requires a different signature than just returning a stream of the *first* response.
                            // But let's assume we want to support it.
                            break
                            
                        default:
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
            }
        }
    }
    
    // Helper to load single session
    func loadSession(id: UUID) throws -> ChatSession {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == id })).first else {
            throw ChatServiceError.sessionMissing
        }
        return entity.asDomain()
    }

    func updateMessageTokenUsage(messageID: UUID, tokenUsage: TokenUsage, costBreakdown: CostBreakdown) throws {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatMessageEntity>(predicate: #Predicate { $0.id == messageID })).first else {
            throw ChatServiceError.messageMissing
        }
        entity.tokenUsageInputTokens = tokenUsage.inputTokens
        entity.tokenUsageOutputTokens = tokenUsage.outputTokens
        entity.tokenUsageCachedTokens = tokenUsage.cachedTokens
        entity.costBreakdownInputCost = costBreakdown.inputCost
        entity.costBreakdownOutputCost = costBreakdown.outputCost
        entity.costBreakdownCachedCost = costBreakdown.cachedCost
        entity.costBreakdownTotalCost = costBreakdown.totalCost
        try modelContext.save()
    }

    func updateSessionMetadata(sessionID: UUID, lastTokenUsage: TokenUsage, additionalCost: Decimal) throws {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ChatServiceError.sessionMissing
        }
        entity.lastTokenUsageInputTokens = lastTokenUsage.inputTokens
        entity.lastTokenUsageOutputTokens = lastTokenUsage.outputTokens
        entity.lastTokenUsageCachedTokens = lastTokenUsage.cachedTokens
        entity.totalCostUSD += additionalCost
        try modelContext.save()
    }
}

enum ChatServiceError: LocalizedError {
    case sessionMissing
    case messageMissing

    var errorDescription: String? {
        switch self {
        case .sessionMissing: "Chat session missing"
        case .messageMissing: "Chat message missing"
        }
    }
}
