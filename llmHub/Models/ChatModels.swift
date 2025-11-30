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
            jsonMode: jsonMode
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
            costBreakdown: costBreakdownInputCost.map { CostBreakdown(inputCost: $0, outputCost: costBreakdownOutputCost!, cachedCost: costBreakdownCachedCost!, totalCost: costBreakdownTotalCost!) }
        )
        domainMsg.thoughtProcess = thoughtProcess
        return domainMsg
    }
}
