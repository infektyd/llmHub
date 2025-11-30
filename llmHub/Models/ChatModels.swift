//
//  ChatModels.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/27/25.
//

import Foundation
import SwiftData

struct ChatSession: Identifiable {
    let id: UUID
    var title: String
    let providerID: String
    let model: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var metadata: ChatSessionMetadata
    var jsonMode: Bool = false
    var folderID: UUID?
    var tags: [ChatTag] = []
    var isPinned: Bool = false
}

struct ChatFolder: Identifiable, Hashable {
    let id: UUID
    var name: String
    var icon: String // SF Symbol name
    var color: String // Hex string
    var orderIndex: Int
    var createdAt: Date
    var updatedAt: Date
}

struct ChatTag: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var color: String // Hex string
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thoughtProcess: String?
    let parts: [ChatContentPart]
    let createdAt: Date
    var codeBlocks: [CodeBlock]
    var tokenUsage: TokenUsage?
    var costBreakdown: CostBreakdown?
    
    // Tool calling support
    var toolCallID: String? = nil  // For tool role: links result to the original tool_use
    var toolCalls: [ToolCall]? = nil  // For assistant role: requested tool executions
}

// MARK: - Tool Calling

struct ToolCall: Codable, Sendable {
    let id: String
    let name: String
    let input: String  // JSON string of arguments
}

enum MessageRole: String, Codable {
    case user, assistant, system, tool
}

enum ChatContentPart: Codable, Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case imageURL(URL)
}

struct ChatSessionMetadata {
    var lastTokenUsage: TokenUsage?
    var totalCostUSD: Decimal
    let referenceID: String
}

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
}

struct CostBreakdown: Codable {
    let inputCost: Decimal
    let outputCost: Decimal
    let cachedCost: Decimal
    let totalCost: Decimal
}

struct CodeBlock: Codable {
    let language: String?
    let code: String
}

@Model
final class ChatFolderEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var color: String
    var orderIndex: Int
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \ChatSessionEntity.folder) var sessions: [ChatSessionEntity] = []

    init(folder: ChatFolder) {
        id = folder.id
        name = folder.name
        icon = folder.icon
        color = folder.color
        orderIndex = folder.orderIndex
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
    }
    
    func asDomain() -> ChatFolder {
        ChatFolder(
            id: id,
            name: name,
            icon: icon,
            color: color,
            orderIndex: orderIndex,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class ChatTagEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var color: String
    @Relationship(deleteRule: .nullify, inverse: \ChatSessionEntity.tags) var sessions: [ChatSessionEntity] = []

    init(tag: ChatTag) {
        id = tag.id
        name = tag.name
        color = tag.color
    }
    
    func asDomain() -> ChatTag {
        ChatTag(id: id, name: name, color: color)
    }
}

@Model
final class ChatSessionEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var providerID: String
    var model: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var messages: [ChatMessageEntity]
    var lastTokenUsageInputTokens: Int?
    var lastTokenUsageOutputTokens: Int?
    var lastTokenUsageCachedTokens: Int?
    var totalCostUSD: Decimal
    var referenceID: String
    var jsonMode: Bool = false
    
    // Organization
    var folder: ChatFolderEntity?
    @Relationship(deleteRule: .nullify) var tags: [ChatTagEntity] = []
    var isPinned: Bool = false

    init(session: ChatSession) {
        id = session.id
        title = session.title
        providerID = session.providerID
        model = session.model
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        messages = session.messages.map(ChatMessageEntity.init)
        lastTokenUsageInputTokens = session.metadata.lastTokenUsage?.inputTokens
        lastTokenUsageOutputTokens = session.metadata.lastTokenUsage?.outputTokens
        lastTokenUsageCachedTokens = session.metadata.lastTokenUsage?.cachedTokens
        totalCostUSD = session.metadata.totalCostUSD
        referenceID = session.metadata.referenceID
        jsonMode = session.jsonMode
        isPinned = session.isPinned
        // Relationships (folder and tags) are usually set via service update methods, 
        // but if passed in a domain object we'd need context to link them.
        // For init from new session, these start empty/nil.
    }

    func asDomain() -> ChatSession {
        ChatSession(
            id: id,
            title: title,
            providerID: providerID,
            model: model,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages.map { $0.asDomain() },
            metadata: ChatSessionMetadata(
                lastTokenUsage: lastTokenUsageInputTokens.map { TokenUsage(inputTokens: $0, outputTokens: lastTokenUsageOutputTokens!, cachedTokens: lastTokenUsageCachedTokens!) },
                totalCostUSD: totalCostUSD,
                referenceID: referenceID
            ),
            jsonMode: jsonMode,
            folderID: folder?.id,
            tags: tags.map { $0.asDomain() },
            isPinned: isPinned
        )
    }
}

@Model
final class ChatMessageEntity {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var thoughtProcess: String?
    var partsData: Data? // JSON encoded [ChatContentPart]
    var createdAt: Date
    var codeBlocksData: Data?
    var tokenUsageInputTokens: Int?
    var tokenUsageOutputTokens: Int?
    var tokenUsageCachedTokens: Int?
    var costBreakdownInputCost: Decimal?
    var costBreakdownOutputCost: Decimal?
    var costBreakdownCachedCost: Decimal?
    var costBreakdownTotalCost: Decimal?
    @Relationship var session: ChatSessionEntity?
    
    // Tool calling support
    var toolCallID: String?
    var toolCallsData: Data? // JSON encoded [ToolCall]

    init(message: ChatMessage) {
        id = message.id
        role = message.role.rawValue
        content = message.content
        thoughtProcess = message.thoughtProcess
        partsData = try? JSONEncoder().encode(message.parts)
        createdAt = message.createdAt
        codeBlocksData = try? JSONEncoder().encode(message.codeBlocks)
        tokenUsageInputTokens = message.tokenUsage?.inputTokens
        tokenUsageOutputTokens = message.tokenUsage?.outputTokens
        tokenUsageCachedTokens = message.tokenUsage?.cachedTokens
        costBreakdownInputCost = message.costBreakdown?.inputCost
        costBreakdownOutputCost = message.costBreakdown?.outputCost
        costBreakdownCachedCost = message.costBreakdown?.cachedCost
        costBreakdownTotalCost = message.costBreakdown?.totalCost
        toolCallID = message.toolCallID
        toolCallsData = try? JSONEncoder().encode(message.toolCalls)
    }

    func asDomain() -> ChatMessage {
        var domainMsg = ChatMessage(
            id: id,
            role: MessageRole(rawValue: role)!,
            content: content,
            parts: (try? JSONDecoder().decode([ChatContentPart].self, from: partsData ?? Data())) ?? [],
            createdAt: createdAt,
            codeBlocks: (try? JSONDecoder().decode([CodeBlock].self, from: codeBlocksData ?? Data())) ?? [],
            tokenUsage: tokenUsageInputTokens.map { TokenUsage(inputTokens: $0, outputTokens: tokenUsageOutputTokens!, cachedTokens: tokenUsageCachedTokens!) },
            costBreakdown: costBreakdownInputCost.map { CostBreakdown(inputCost: $0, outputCost: costBreakdownOutputCost!, cachedCost: costBreakdownCachedCost!, totalCost: costBreakdownTotalCost!) },
            toolCallID: toolCallID,
            toolCalls: (try? JSONDecoder().decode([ToolCall].self, from: toolCallsData ?? Data()))
        )
        domainMsg.thoughtProcess = thoughtProcess
        return domainMsg
    }
}
