//
//  ChatModels.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/27/25.
//

import Foundation
import SwiftData

/// Represents a chat session in the application, containing all messages and metadata.
struct ChatSession: Identifiable {
    /// The unique identifier of the chat session.
    let id: UUID
    /// The title of the chat session, usually displayed in the sidebar.
    var title: String
    /// The identifier of the LLM provider used for this session (e.g., "openai").
    let providerID: String
    /// The specific model identifier used for this session (e.g., "gpt-4").
    let model: String
    /// The date when the session was created.
    let createdAt: Date
    /// The date when the session was last updated.
    var updatedAt: Date
    /// The list of messages in the session.
    var messages: [ChatMessage]
    /// Metadata associated with the session, such as token usage and cost.
    var metadata: ChatSessionMetadata
    /// Indicates whether the session is in JSON mode, forcing JSON output from the model.
    var jsonMode: Bool = false
    /// The unique identifier of the folder this session belongs to, if any.
    var folderID: UUID?
    /// A list of tags associated with the session for organization.
    var tags: [ChatTag] = []
    /// Indicates whether the session is pinned to the top of the list.
    var isPinned: Bool = false
}

/// Represents a folder used to organize chat sessions.
struct ChatFolder: Identifiable, Hashable {
    /// The unique identifier of the folder.
    let id: UUID
    /// The name of the folder.
    var name: String
    /// The SF Symbol name used for the folder's icon.
    var icon: String // SF Symbol name
    /// The hex string representation of the folder's color.
    var color: String // Hex string
    /// The index used to order the folder in a list.
    var orderIndex: Int
    /// The date when the folder was created.
    var createdAt: Date
    /// The date when the folder was last updated.
    var updatedAt: Date
}

/// Represents a tag used to categorize chat sessions.
struct ChatTag: Identifiable, Hashable, Codable {
    /// The unique identifier of the tag.
    let id: UUID
    /// The name of the tag.
    var name: String
    /// The hex string representation of the tag's color.
    var color: String // Hex string
}

/// Represents a single message within a chat session.
struct ChatMessage: Identifiable {
    /// The unique identifier of the message.
    let id: UUID
    /// The role of the message sender (e.g., user, assistant).
    let role: MessageRole
    /// The text content of the message.
    var content: String
    /// The internal thought process of the model, if available (e.g., for reasoning models).
    var thoughtProcess: String?
    /// The content parts of the message, allowing for multimodal content like images.
    let parts: [ChatContentPart]
    /// The date when the message was created.
    let createdAt: Date
    /// A list of code blocks extracted from the message content.
    var codeBlocks: [CodeBlock]
    /// The token usage associated with generating this message.
    var tokenUsage: TokenUsage?
    /// The cost breakdown associated with generating this message.
    var costBreakdown: CostBreakdown?
    
    // Tool calling support
    /// The ID of the tool call this message is a response to (only for tool role).
    var toolCallID: String? = nil
    /// The list of tool calls requested by the assistant (only for assistant role).
    var toolCalls: [ToolCall]? = nil
}

// MARK: - Tool Calling

/// Represents a request for a tool execution.
struct ToolCall: Codable, Sendable {
    /// The unique identifier for the tool call.
    let id: String
    /// The name of the tool to be called.
    let name: String
    /// The JSON string representation of the arguments for the tool.
    let input: String
}

/// Defines the role of the message sender.
enum MessageRole: String, Codable {
    /// The user interacting with the model.
    case user
    /// The AI model responding to the user.
    case assistant
    /// The system providing instructions to the model.
    case system
    /// A tool providing output back to the model.
    case tool
}

/// Represents a part of the message content, supporting text and images.
enum ChatContentPart: Codable, Sendable {
    /// A text part.
    case text(String)
    /// An image part containing raw data and a mime type.
    case image(Data, mimeType: String)
    /// An image part referring to a URL.
    case imageURL(URL)
}

/// Metadata associated with a chat session.
struct ChatSessionMetadata {
    /// The token usage for the last interaction.
    var lastTokenUsage: TokenUsage?
    /// The total cost in USD for the session.
    var totalCostUSD: Decimal
    /// A reference ID for the session, often used for tracking.
    let referenceID: String
}

/// Represents token usage statistics.
struct TokenUsage {
    /// The number of input tokens used.
    let inputTokens: Int
    /// The number of output tokens generated.
    let outputTokens: Int
    /// The number of cached tokens used.
    let cachedTokens: Int
}

/// Represents the cost breakdown for a request.
struct CostBreakdown: Codable {
    /// The cost associated with input tokens.
    let inputCost: Decimal
    /// The cost associated with output tokens.
    let outputCost: Decimal
    /// The cost associated with cached tokens.
    let cachedCost: Decimal
    /// The total cost for the request.
    let totalCost: Decimal
}

/// Represents a block of code within a message.
struct CodeBlock: Codable {
    /// The programming language of the code block.
    let language: String?
    /// The code content.
    let code: String
}

/// A SwiftData entity representing a chat folder for persistence.
@Model
final class ChatFolderEntity {
    /// The unique identifier of the folder.
    @Attribute(.unique) var id: UUID
    /// The name of the folder.
    var name: String
    /// The icon name for the folder.
    var icon: String
    /// The color string for the folder.
    var color: String
    /// The order index for the folder.
    var orderIndex: Int
    /// The creation date of the folder.
    var createdAt: Date
    /// The last update date of the folder.
    var updatedAt: Date
    /// The sessions contained within this folder.
    @Relationship(deleteRule: .nullify, inverse: \ChatSessionEntity.folder) var sessions: [ChatSessionEntity] = []

    /// Initializes a new `ChatFolderEntity` from a domain model.
    /// - Parameter folder: The `ChatFolder` domain model.
    init(folder: ChatFolder) {
        id = folder.id
        name = folder.name
        icon = folder.icon
        color = folder.color
        orderIndex = folder.orderIndex
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
    }
    
    /// Converts the entity back to a domain model.
    /// - Returns: A `ChatFolder` instance.
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

/// A SwiftData entity representing a chat tag for persistence.
@Model
final class ChatTagEntity {
    /// The unique identifier of the tag.
    @Attribute(.unique) var id: UUID
    /// The name of the tag.
    var name: String
    /// The color string for the tag.
    var color: String
    /// The sessions associated with this tag.
    @Relationship(deleteRule: .nullify, inverse: \ChatSessionEntity.tags) var sessions: [ChatSessionEntity] = []

    /// Initializes a new `ChatTagEntity` from a domain model.
    /// - Parameter tag: The `ChatTag` domain model.
    init(tag: ChatTag) {
        id = tag.id
        name = tag.name
        color = tag.color
    }
    
    /// Converts the entity back to a domain model.
    /// - Returns: A `ChatTag` instance.
    func asDomain() -> ChatTag {
        ChatTag(id: id, name: name, color: color)
    }
}

/// A SwiftData entity representing a chat session for persistence.
@Model
final class ChatSessionEntity {
    /// The unique identifier of the session.
    @Attribute(.unique) var id: UUID
    /// The title of the session.
    var title: String
    /// The provider ID for the session.
    var providerID: String
    /// The model identifier for the session.
    var model: String
    /// The creation date of the session.
    var createdAt: Date
    /// The last update date of the session.
    var updatedAt: Date
    /// The messages contained in the session.
    @Relationship(deleteRule: .cascade) var messages: [ChatMessageEntity]
    /// The number of input tokens used in the last request.
    var lastTokenUsageInputTokens: Int?
    /// The number of output tokens generated in the last request.
    var lastTokenUsageOutputTokens: Int?
    /// The number of cached tokens used in the last request.
    var lastTokenUsageCachedTokens: Int?
    /// The total cost in USD accumulated for the session.
    var totalCostUSD: Decimal
    /// A reference ID for the session.
    var referenceID: String
    /// Indicates if JSON mode is enabled.
    var jsonMode: Bool = false
    
    // Organization
    /// The folder this session belongs to.
    var folder: ChatFolderEntity?
    /// The tags associated with this session.
    @Relationship(deleteRule: .nullify) var tags: [ChatTagEntity] = []
    /// Indicates if the session is pinned.
    var isPinned: Bool = false

    /// Initializes a new `ChatSessionEntity` from a domain model.
    /// - Parameter session: The `ChatSession` domain model.
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

    /// Converts the entity back to a domain model.
    /// - Returns: A `ChatSession` instance.
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

/// A SwiftData entity representing a chat message for persistence.
@Model
final class ChatMessageEntity {
    /// The unique identifier of the message.
    @Attribute(.unique) var id: UUID
    /// The role of the sender.
    var role: String
    /// The content of the message.
    var content: String
    /// The thought process, if any.
    var thoughtProcess: String?
    /// The JSON encoded data for message parts.
    var partsData: Data? // JSON encoded [ChatContentPart]
    /// The creation date of the message.
    var createdAt: Date
    /// The JSON encoded data for code blocks.
    var codeBlocksData: Data?
    /// The input tokens used for this message.
    var tokenUsageInputTokens: Int?
    /// The output tokens used for this message.
    var tokenUsageOutputTokens: Int?
    /// The cached tokens used for this message.
    var tokenUsageCachedTokens: Int?
    /// The input cost for this message.
    var costBreakdownInputCost: Decimal?
    /// The output cost for this message.
    var costBreakdownOutputCost: Decimal?
    /// The cached cost for this message.
    var costBreakdownCachedCost: Decimal?
    /// The total cost for this message.
    var costBreakdownTotalCost: Decimal?
    /// The session this message belongs to.
    @Relationship var session: ChatSessionEntity?
    
    // Tool calling support
    /// The ID of the tool call this message responds to.
    var toolCallID: String?
    /// The JSON encoded data for tool calls.
    var toolCallsData: Data? // JSON encoded [ToolCall]

    /// Initializes a new `ChatMessageEntity` from a domain model.
    /// - Parameter message: The `ChatMessage` domain model.
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

    /// Converts the entity back to a domain model.
    /// - Returns: A `ChatMessage` instance.
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
