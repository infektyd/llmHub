//
//  ChatService.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import SwiftData
import OSLog

/// Service responsible for managing chat sessions, messages, and interactions with LLM providers.
final class ChatService {
    /// The SwiftData model context.
    let modelContext: ModelContext
    /// Registry of available LLM providers.
    let providerRegistry: ProviderRegistry
    /// Calculator for session costs.
    private let costCalculator: CostCalculator
    /// Registry of available tools.
    private let toolRegistry: ToolRegistry

    /// Logger instance.
    private let logger = Logger(subsystem: "com.llmhub", category: "ChatService")
    
    /// Maximum number of tool execution loops to prevent infinite recursion.
    private let maxToolIterations = 10

    /// Initializes a new `ChatService`.
    /// - Parameters:
    ///   - modelContext: The SwiftData context.
    ///   - providerRegistry: The provider registry.
    ///   - costCalculator: The cost calculator (default: new instance).
    ///   - toolRegistry: The tool registry (default: nil, creates default).
    init(
        modelContext: ModelContext,
        providerRegistry: ProviderRegistry,
        costCalculator: CostCalculator = CostCalculator(),
        toolRegistry: ToolRegistry? = nil
    ) {
        self.modelContext = modelContext
        self.providerRegistry = providerRegistry
        self.costCalculator = costCalculator
        // Use provided registry or create default on MainActor
        self.toolRegistry = toolRegistry ?? ToolRegistry.createDefaultRegistrySync()
    }

    // MARK: - Sessions

    /// Loads all chat sessions from storage, sorted by update time.
    /// - Returns: An array of `ChatSession`.
    func loadSessions() throws -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSessionEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    /// Creates a new chat session.
    /// - Parameters:
    ///   - providerID: The ID of the LLM provider.
    ///   - model: The model identifier.
    /// - Returns: The created `ChatSession`.
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

    /// Appends a message to an existing session.
    /// - Parameters:
    ///   - message: The message to append.
    ///   - sessionID: The ID of the session.
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

    /// Streams a completion response from the LLM for a given session.
    /// - Parameters:
    ///   - session: The chat session.
    ///   - userMessage: The user's input message.
    ///   - images: Optional images to include in the request.
    /// - Returns: An async throwing stream of `ProviderEvent`.
    func streamCompletion(for session: ChatSession, userMessage: String, images: [Data] = []) async throws -> AsyncThrowingStream<ProviderEvent, Error> {
        
        var parts: [ChatContentPart] = [.text(userMessage)]
        for imgData in images {
            let mimeType = detectImageMimeType(from: imgData)
            parts.append(.image(imgData, mimeType: mimeType))
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
        
        logger.debug("Using provider: \(session.providerID), model: \(session.model)")
        
        let provider = try providerRegistry.provider(for: session.providerID)
        let sessionID = session.id
        let toolReg = self.toolRegistry
        let maxIterations = self.maxToolIterations
        let logger = self.logger
        let service = self
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var iterationCount = 0
                    var continueLoop = true
                    
                    while continueLoop && iterationCount < maxIterations {
                        iterationCount += 1
                        continueLoop = false
                        
                        // Reload session to get updated history (including any tool results)
                        let currentSession = try service.loadSession(id: sessionID)
                        
                        // Build tool definitions from registry
                        let toolDefs: [ToolDefinition]? = toolReg.allTools.isEmpty ? nil : toolReg.allTools.map { ToolDefinition(from: $0) }
                        
                        let request = try provider.buildRequest(messages: currentSession.messages, model: currentSession.model, tools: toolDefs)
                        
                        // Track accumulated tool calls for this iteration
                        var accumulatedToolCalls: [ToolCall] = []
                        
                        // Stream response
                        for try await event in provider.streamResponse(from: request) {
                            switch event {
                            case .token(let text):
                                continuation.yield(.token(text: text))
                                
                            case .thinking(let thought):
                                continuation.yield(.thinking(thought))
                                
                            case .toolUse(let id, let name, let input):
                                // Notify UI of tool use
                                continuation.yield(.toolUse(id: id, name: name, input: input))
                                
                                // Accumulate the tool call
                                let toolCall = ToolCall(id: id, name: name, input: input)
                                accumulatedToolCalls.append(toolCall)
                                
                            case .usage(let usage):
                                continuation.yield(.usage(usage))
                                
                            case .reference(let ref):
                                continuation.yield(.reference(ref))
                                
                            case .completion(let msg):
                                // If we have tool calls, save assistant message with them
                                if !accumulatedToolCalls.isEmpty {
                                    var assistantMsg = msg
                                    assistantMsg.toolCalls = accumulatedToolCalls
                                    try service.appendMessage(assistantMsg, to: sessionID)
                                } else {
                                    // Normal completion - save and we're done
                                    try service.appendMessage(msg, to: sessionID)
                                    continuation.yield(.completion(message: msg))
                                }
                                
                            case .error(let error):
                                continuation.yield(.error(error))
                            }
                        }
                        
                        // After stream completes, execute any pending tool calls
                        if !accumulatedToolCalls.isEmpty {
                            for toolCall in accumulatedToolCalls {
                                logger.info("Executing tool: \(toolCall.name) with input: \(toolCall.input.prefix(100))...")
                                
                                // Execute the tool
                                let toolResult: String
                                if let tool = toolReg.tool(named: toolCall.name) {
                                    do {
                                        // Parse input JSON
                                        let inputDict = try JSONSerialization.jsonObject(
                                            with: toolCall.input.data(using: .utf8) ?? Data()
                                        ) as? [String: Any] ?? [:]
                                        
                                        toolResult = try await tool.execute(input: inputDict)
                                        logger.info("Tool \(toolCall.name) succeeded: \(toolResult.prefix(100))...")
                                    } catch {
                                        toolResult = "Error executing tool: \(error.localizedDescription)"
                                        logger.error("Tool \(toolCall.name) failed: \(error)")
                                    }
                                } else {
                                    toolResult = "Tool '\(toolCall.name)' not found in registry"
                                    logger.warning("Unknown tool requested: \(toolCall.name)")
                                }
                                
                                // Create and save tool result message
                                let toolResultMessage = ChatMessage(
                                    id: UUID(),
                                    role: .tool,
                                    content: toolResult,
                                    parts: [],
                                    createdAt: Date(),
                                    codeBlocks: [],
                                    tokenUsage: nil,
                                    costBreakdown: nil,
                                    toolCallID: toolCall.id
                                )
                                
                                try service.appendMessage(toolResultMessage, to: sessionID)
                                
                                // Notify UI of tool result (as a token for now)
                                continuation.yield(.token(text: "\n[Tool Result: \(toolCall.name)]\n\(toolResult)\n"))
                            }
                            
                            // Continue the loop to let LLM process tool results
                            continueLoop = true
                        }
                    }
                    
                    if iterationCount >= maxIterations {
                        logger.warning("Agent loop reached maximum iterations (\(maxIterations))")
                    }
                    
                    continuation.finish()
                } catch {
                    logger.error("Stream completion error: \(error)")
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
            }
        }
    }
    
    // Helper to load single session
    /// Loads a specific session by ID.
    func loadSession(id: UUID) throws -> ChatSession {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == id })).first else {
            throw ChatServiceError.sessionMissing
        }
        return entity.asDomain()
    }

    /// Updates the token usage and cost for a specific message.
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

    /// Updates the session metadata (last usage, total cost).
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

    // MARK: - Folders

    /// Loads all chat folders.
    func loadFolders() throws -> [ChatFolder] {
        let descriptor = FetchDescriptor<ChatFolderEntity>(sortBy: [SortDescriptor(\.orderIndex)])
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    /// Creates a new chat folder.
    func createFolder(name: String, icon: String, color: String) throws -> ChatFolder {
        let folder = ChatFolder(
            id: UUID(),
            name: name,
            icon: icon,
            color: color,
            orderIndex: try loadFolders().count,
            createdAt: Date(),
            updatedAt: Date()
        )
        let entity = ChatFolderEntity(folder: folder)
        modelContext.insert(entity)
        try modelContext.save()
        return folder
    }

    /// Updates an existing chat folder.
    func updateFolder(_ folder: ChatFolder) throws {
        let folderID = folder.id
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatFolderEntity>(predicate: #Predicate { $0.id == folderID })).first else {
            throw ChatServiceError.folderMissing
        }
        entity.name = folder.name
        entity.icon = folder.icon
        entity.color = folder.color
        entity.updatedAt = Date()
        try modelContext.save()
    }

    /// Deletes a chat folder.
    func deleteFolder(id: UUID) throws {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatFolderEntity>(predicate: #Predicate { $0.id == id })).first else {
            throw ChatServiceError.folderMissing
        }
        // Sessions in this folder will have their folder relationship set to null (nullify rule)
        modelContext.delete(entity)
        try modelContext.save()
    }

    /// Moves a session to a specific folder.
    func moveSession(_ sessionID: UUID, to folderID: UUID?) throws {
        guard let sessionEntity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ChatServiceError.sessionMissing
        }

        if let folderID = folderID {
            guard let folderEntity = try modelContext.fetch(FetchDescriptor<ChatFolderEntity>(predicate: #Predicate { $0.id == folderID })).first else {
                throw ChatServiceError.folderMissing
            }
            sessionEntity.folder = folderEntity
        } else {
            sessionEntity.folder = nil
        }
        try modelContext.save()
    }

    // MARK: - Tags

    /// Loads all chat tags.
    func loadTags() throws -> [ChatTag] {
        let descriptor = FetchDescriptor<ChatTagEntity>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    /// Creates a new tag.
    func createTag(name: String, color: String) throws -> ChatTag {
        let tag = ChatTag(id: UUID(), name: name, color: color)
        let entity = ChatTagEntity(tag: tag)
        modelContext.insert(entity)
        try modelContext.save()
        return tag
    }

    /// Deletes a tag.
    func deleteTag(id: UUID) throws {
        guard let entity = try modelContext.fetch(FetchDescriptor<ChatTagEntity>(predicate: #Predicate { $0.id == id })).first else {
            throw ChatServiceError.tagMissing
        }
        modelContext.delete(entity)
        try modelContext.save()
    }

    /// Adds a tag to a session.
    func addTag(tagID: UUID, to sessionID: UUID) throws {
        guard let sessionEntity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ChatServiceError.sessionMissing
        }
        guard let tagEntity = try modelContext.fetch(FetchDescriptor<ChatTagEntity>(predicate: #Predicate { $0.id == tagID })).first else {
            throw ChatServiceError.tagMissing
        }
        
        if !sessionEntity.tags.contains(where: { $0.id == tagID }) {
            sessionEntity.tags.append(tagEntity)
            try modelContext.save()
        }
    }

    /// Removes a tag from a session.
    func removeTag(tagID: UUID, from sessionID: UUID) throws {
        guard let sessionEntity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ChatServiceError.sessionMissing
        }
        sessionEntity.tags.removeAll(where: { $0.id == tagID })
        try modelContext.save()
    }

    // MARK: - Pinning

    /// Toggles the pinned state of a session.
    func togglePin(sessionID: UUID) throws {
        guard let sessionEntity = try modelContext.fetch(FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ChatServiceError.sessionMissing
        }
        sessionEntity.isPinned.toggle()
        try modelContext.save()
    }
    
    // MARK: - Image Helpers
    
    /// Detects the image MIME type from the file's magic bytes.
    private func detectImageMimeType(from data: Data) -> String {
        guard data.count >= 12 else { return "image/jpeg" }
        
        let bytes = [UInt8](data.prefix(12))
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }
        
        // GIF: 47 49 46 38 (GIF8)
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return "image/gif"
        }
        
        // WebP: RIFF....WEBP (bytes 0-3: RIFF, bytes 8-11: WEBP)
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "image/webp"
        }
        
        // TIFF: 49 49 2A 00 (little-endian) or 4D 4D 00 2A (big-endian)
        if (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
           (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A) {
            return "image/tiff"
        }
        
        // BMP: 42 4D (BM)
        if bytes[0] == 0x42 && bytes[1] == 0x4D {
            return "image/bmp"
        }
        
        // Default fallback
        return "image/jpeg"
    }
}

/// Errors thrown by the ChatService.
enum ChatServiceError: LocalizedError {
    /// The session could not be found.
    case sessionMissing
    /// The message could not be found.
    case messageMissing
    /// The folder could not be found.
    case folderMissing
    /// The tag could not be found.
    case tagMissing

    /// A localized description of the error.
    var errorDescription: String? {
        switch self {
        case .sessionMissing:
            return "Chat session missing"
        case .messageMissing:
            return "Chat message missing"
        case .folderMissing:
            return "Folder missing"
        case .tagMissing:
            return "Tag missing"
        }
    }
}
