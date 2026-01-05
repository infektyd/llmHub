//
//  ChatModels.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/27/25.
//

import Foundation
import SwiftData

/// Represents a chat session in the application, containing all messages and metadata.
struct ChatSession: Identifiable, Sendable {
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
    /// Per-session user preference for requesting model reasoning/thinking output.
    var thinkingPreference: ThinkingPreference = .auto
    /// The unique identifier of the folder this session belongs to, if any.
    var folderID: UUID?
    /// A list of tags associated with the session for organization.
    var tags: [ChatTag] = []
    /// Indicates whether the session is pinned to the top of the list.
    var isPinned: Bool = false
}

/// Represents a folder used to organize chat sessions.
struct ChatFolder: Identifiable, Hashable, Sendable {
    /// The unique identifier of the folder.
    let id: UUID
    /// The name of the folder.
    var name: String
    /// The SF Symbol name used for the folder's icon.
    var icon: String  // SF Symbol name
    /// The hex string representation of the folder's color.
    var color: String  // Hex string
    /// The index used to order the folder in a list.
    var orderIndex: Int
    /// The date when the folder was created.
    var createdAt: Date
    /// The date when the folder was last updated.
    var updatedAt: Date
}

/// Represents a tag used to categorize chat sessions.
struct ChatTag: Identifiable, Hashable, Codable, Sendable {
    /// The unique identifier of the tag.
    let id: UUID
    /// The name of the tag.
    var name: String
    /// The hex string representation of the tag's color.
    var color: String  // Hex string
}

// MARK: - Attachments

/// Defines the type of an attachment.
enum AttachmentType: String, Codable, Equatable, Sendable {
    case image
    case text
    case code
    case pdf
    case other

    var icon: String {
        switch self {
        case .image: return "photo"
        case .text: return "doc.text"
        case .code: return "curlybraces"
        case .pdf: return "doc.richtext"
        case .other: return "doc"
        }
    }
}

/// Represents a file attachment in a message.
struct Attachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let url: URL
    let type: AttachmentType
    let previewText: String?  // First ~200 chars for text/code

    init(
        id: UUID = UUID(), filename: String, url: URL, type: AttachmentType,
        previewText: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.url = url
        self.type = type
        self.previewText = previewText
    }
}

// MARK: - Artifacts

/// A lightweight language classification used for artifact rendering.
/// Note: Syntax highlighting is handled in the UI layer (Splash uses Swift grammar).
enum CodeLanguage: String, Codable, Sendable {
    case json
    case swift
    case python
    case javascript
    case markdown
    case text

    static func detect(from content: String, filename: String?) -> CodeLanguage {
        if let ext = filename?.split(separator: ".").last?.lowercased() {
            switch ext {
            case "json": return .json
            case "swift": return .swift
            case "py": return .python
            case "js", "ts": return .javascript
            case "md": return .markdown
            default: break
            }
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return .json }
        if content.contains("func ") || content.contains("class ") || content.contains("import ") {
            return .swift
        }
        if content.contains("def ") { return .python }
        if content.contains("console.") || content.contains("function ") { return .javascript }
        if content.contains("```") { return .markdown }
        return .text
    }

    static func looksLikeLargePasteArtifact(_ content: String) -> Bool {
        guard content.count > 500 else { return false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return true }
        if content.contains("```") { return true }
        if content.contains("func ") || content.contains("class ") || content.contains("import ") {
            return true
        }
        return false
    }

    var preferredFileExtension: String {
        switch self {
        case .json: return "json"
        case .swift: return "swift"
        case .python: return "py"
        case .javascript: return "js"
        case .markdown: return "md"
        case .text: return "txt"
        }
    }

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .swift: return "Swift"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .markdown: return "Markdown"
        case .text: return "Plain Text"
        }
    }
}

/// Represents a single message within a chat session.
struct ChatMessage: Identifiable, Equatable, Sendable {
    /// The unique identifier of the message.
    let id: UUID
    /// Stable identity for joining a streaming overlay message with its persisted assistant message.
    /// Rationale: streaming uses a local message UUID, while persisted assistant messages may use a
    /// different UUID from the provider/tool loop. `generationID` is the stable join key.
    var generationID: UUID? = nil
    /// The role of the message sender (e.g., user, assistant).
    let role: MessageRole
    /// The text content of the message.
    var content: String
    /// The internal thought process of the model, if available (e.g., for reasoning models).
    var thoughtProcess: String?
    /// The content parts of the message, allowing for multimodal content like images.
    let parts: [ChatContentPart]
    /// The list of attachments associated with the message.
    var attachments: [Attachment] = []
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

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.generationID == rhs.generationID && lhs.role == rhs.role
            && lhs.content == rhs.content
            && lhs.thoughtProcess == rhs.thoughtProcess && lhs.parts == rhs.parts
            && lhs.attachments == rhs.attachments && lhs.createdAt == rhs.createdAt
            && lhs.codeBlocks == rhs.codeBlocks && lhs.tokenUsage == rhs.tokenUsage
            && lhs.costBreakdown == rhs.costBreakdown && lhs.toolCallID == rhs.toolCallID
            && lhs.toolCalls == rhs.toolCalls
    }
}

// MARK: - Artifact Detection

extension ChatMessage {
    /// True if this message contains any file attachment, or if the content looks like a large pasted artifact.
    var hasArtifact: Bool {
        !artifactMetadatas.isEmpty
    }

    /// Convenience for rendering a single artifact card.
    var artifactMetadata: ArtifactMetadata? {
        artifactMetadatas.first
    }

    /// Returns all artifact metadata associated with this message.
    /// - Includes: file attachments (text/code/pdf/other) and large paste content.
    var artifactMetadatas: [ArtifactMetadata] {
        var results: [ArtifactMetadata] = []

        // Large paste in content.
        if rendersContentAsArtifact {
            let lang = CodeLanguage.detect(from: content, filename: nil)
            let filename = "Paste.\(lang.preferredFileExtension)"
            results.append(
                ArtifactMetadata(
                    filename: filename,
                    content: content,
                    language: lang,
                    sizeBytes: content.utf8.count,
                    fileURL: nil
                )
            )
        }

        // File attachments.
        for attachment in attachments {
            guard attachment.type != .image else { continue }

            let attrs = FileManager.default.attributesOfItemSafe(atPath: attachment.url.path)
            let sizeBytes =
                (attrs[.size] as? NSNumber)?.intValue
                ?? (attrs[.size] as? Int)
                ?? attachment.previewText?.utf8.count
                ?? 0

            let lang = CodeLanguage.detect(
                from: attachment.previewText ?? "", filename: attachment.filename)

            results.append(
                ArtifactMetadata(
                    filename: attachment.filename,
                    content: attachment.previewText ?? "",
                    language: lang,
                    sizeBytes: sizeBytes,
                    fileURL: attachment.url
                )
            )
        }

        return results
    }

    /// True when the main message content should be rendered as an artifact card rather than inline markdown.
    var rendersContentAsArtifact: Bool {
        role == .user && CodeLanguage.looksLikeLargePasteArtifact(content)
    }
}

extension FileManager {
    fileprivate func attributesOfItemSafe(atPath path: String) -> [FileAttributeKey: Any] {
        (try? attributesOfItem(atPath: path)) ?? [:]
    }
}

/// Represents a request for a tool execution.
struct ToolCall: Codable, Sendable, Equatable {
    /// The unique identifier for the tool call.
    let id: String
    /// The name of the tool to be called.
    let name: String
    /// The JSON string representation of the arguments for the tool.
    let input: String
    /// Gemini-only: thought signature that must be round-tripped for function calling (Gemini 3).
    var geminiThoughtSignature: String? = nil
}

/// Defines the role of the message sender.
enum MessageRole: String, Codable, Equatable {
    /// The user interacting with the model.
    case user
    /// The AI model responding to the user.
    case assistant
    /// The system providing instructions to the model.
    case system
    /// A tool providing output back to the model.
    case tool
}

/// A reference captured from a message selection, used to quote earlier output into a new prompt.
struct ChatReference: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let sourceMessageID: UUID
    let role: MessageRole

    init(id: UUID = UUID(), text: String, sourceMessageID: UUID, role: MessageRole) {
        self.id = id
        self.text = text
        self.sourceMessageID = sourceMessageID
        self.role = role
    }
}

/// Represents a part of the message content, supporting text and images.
enum ChatContentPart: Codable, Sendable, Equatable {
    /// A text part.
    case text(String)
    /// An image part containing raw data and a mime type.
    case image(Data, mimeType: String)
    /// An image part referring to a URL.
    case imageURL(URL)
}

/// Metadata associated with a chat session.
struct ChatSessionMetadata: Sendable {
    /// The token usage for the last interaction.
    var lastTokenUsage: TokenUsage?
    /// The total cost in USD for the session.
    var totalCostUSD: Decimal
    /// A reference ID for the session, often used for tracking.
    let referenceID: String
}

/// Represents token usage statistics.
struct TokenUsage: Equatable, Sendable {
    /// The number of input tokens used.
    let inputTokens: Int
    /// The number of output tokens generated.
    let outputTokens: Int
    /// The number of cached tokens used.
    let cachedTokens: Int
}

/// Represents the cost breakdown for a request.
struct CostBreakdown: Codable, Equatable, Sendable {
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
struct CodeBlock: Codable, Equatable, Sendable {
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
    @Relationship(deleteRule: .nullify, inverse: \ChatSessionEntity.folder) var sessions:
        [ChatSessionEntity] = []

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
    @Relationship(deleteRule: .nullify, inverse: \ChatSessionEntity.tags) var sessions:
        [ChatSessionEntity] = []

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
    /// Raw storage for `ThinkingPreference`.
    var thinkingPreferenceRaw: String = ThinkingPreference.auto.rawValue

    // Organization
    /// The folder this session belongs to.
    var folder: ChatFolderEntity?
    /// The tags associated with this session.
    @Relationship(deleteRule: .nullify) var tags: [ChatTagEntity] = []
    /// Indicates if the session is pinned.
    var isPinned: Bool = false
    /// Optional custom symbol shown for pinned sessions (nil = use defaults).
    var pinnedSymbol: String?
    /// Indicates if the session is archived (hidden from main view).
    var isArchived: Bool = false
    /// Optional project scope for the session (used for hierarchical sidebar grouping).
    var parentProjectID: UUID?
    /// JSON-encoded array of artifact IDs (references into a future artifacts store).
    var artifactIDsData: Data?

    // MARK: - AFM-Generated Metadata
    /// AI-generated title for the conversation (e.g., "Swift concurrency debugging").
    var afmTitle: String?
    /// Single emoji representing the conversation topic.
    var afmEmoji: String?
    /// Primary category: "coding", "research", "creative", "planning", "support", "general".
    var afmCategory: String?
    /// User intent: "quickQuestion", "debugging", "exploration", "creation", "reference".
    var afmIntent: String?
    /// JSON-encoded array of topic strings (e.g., ["swift", "async", "actors"]).
    var afmTopics: Data?
    /// When AFM last classified this conversation.
    var afmClassifiedAt: Date?

    // MARK: - Lifecycle Management
    /// User's apparent intent: "quickQuestion", "debugging", "exploration", "creation", "reference".
    var lifecycleIntent: String?
    /// Suggested retention: "keep", "archive", "reviewIn7Days", "autoDeleteOK".
    var lifecycleRetention: String?
    /// Whether the conversation appears complete/resolved.
    var isComplete: Bool = false
    /// Whether the conversation contains code blocks, tool outputs, or files.
    var hasArtifacts: Bool = false
    /// Updated on each message for staleness tracking.
    var lastActivityAt: Date?
    /// When this conversation was flagged for cleanup review.
    var flaggedForCleanupAt: Date?

    /// Decoded topics array from JSON data.
    var afmTopicsArray: [String] {
        guard let data = afmTopics else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Decoded artifact IDs array from JSON data.
    var artifactIDs: [UUID] {
        get {
            guard let data = artifactIDsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            artifactIDsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Display title preferring AFM-generated title over default.
    var displayTitle: String {
        if let afm = afmTitle, !afm.isEmpty {
            if let emoji = afmEmoji, !emoji.isEmpty {
                return "\(emoji) \(afm)"
            }
            return afm
        }
        return title
    }

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
        thinkingPreferenceRaw = session.thinkingPreference.rawValue
        isPinned = session.isPinned
        parentProjectID = session.folderID
        // Initialize lifecycle tracking
        lastActivityAt = session.createdAt
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
                lastTokenUsage: lastTokenUsageInputTokens.map {
                    TokenUsage(
                        inputTokens: $0, outputTokens: lastTokenUsageOutputTokens!,
                        cachedTokens: lastTokenUsageCachedTokens!)
                },
                totalCostUSD: totalCostUSD,
                referenceID: referenceID
            ),
            jsonMode: jsonMode,
            thinkingPreference: ThinkingPreference(rawValue: thinkingPreferenceRaw) ?? .auto,
            folderID: folder?.id,
            tags: tags.map { $0.asDomain() },
            isPinned: isPinned
        )
    }
}

@MainActor
extension ChatSessionEntity {
    var thinkingPreference: ThinkingPreference {
        get { ThinkingPreference(rawValue: thinkingPreferenceRaw) ?? .auto }
        set { thinkingPreferenceRaw = newValue.rawValue }
    }
}

// MARK: - Token Estimation Extensions

extension ChatMessage {
    /// The estimated token count for this message, including protocol overhead.
    var estimatedTokens: Int {
        TokenEstimator.estimate(content) + 4  // content + overhead
    }
}

extension Array where Element == ChatMessage {
    /// The total estimated token count for all messages in the array.
    var estimatedTokens: Int {
        reduce(0) { $0 + $1.estimatedTokens }
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
    var partsData: Data?  // JSON encoded [ChatContentPart]
    /// The JSON encoded data for attachments.
    var attachmentsData: Data?  // JSON encoded [Attachment]
    /// The creation date of the message.
    var createdAt: Date
    /// Stable identity for merging streamed assistant messages with persisted messages.
    var generationID: UUID?
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
    var toolCallsData: Data?  // JSON encoded [ToolCall]

    /// Initializes a new `ChatMessageEntity` from a domain model.
    /// - Parameter message: The `ChatMessage` domain model.
    init(message: ChatMessage) {
        id = message.id
        generationID = message.generationID
        role = message.role.rawValue
        content = message.content
        thoughtProcess = message.thoughtProcess
        partsData = try? JSONEncoder().encode(message.parts)
        attachmentsData = try? JSONEncoder().encode(message.attachments)
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
            generationID: generationID,
            role: MessageRole(rawValue: role)!,
            content: content,
            parts: (try? JSONDecoder().decode([ChatContentPart].self, from: partsData ?? Data()))
                ?? [],
            attachments: (try? JSONDecoder().decode(
                [Attachment].self, from: attachmentsData ?? Data())) ?? [],
            createdAt: createdAt,
            codeBlocks: (try? JSONDecoder().decode([CodeBlock].self, from: codeBlocksData ?? Data()))
                ?? [],
            tokenUsage: tokenUsageInputTokens.map {
                TokenUsage(
                    inputTokens: $0, outputTokens: tokenUsageOutputTokens!,
                    cachedTokens: tokenUsageCachedTokens!)
            },
            costBreakdown: costBreakdownInputCost.map {
                CostBreakdown(
                    inputCost: $0, outputCost: costBreakdownOutputCost!,
                    cachedCost: costBreakdownCachedCost!, totalCost: costBreakdownTotalCost!)
            },
            toolCallID: toolCallID,
            toolCalls: (try? JSONDecoder().decode([ToolCall].self, from: toolCallsData ?? Data()))
        )
        domainMsg.thoughtProcess = thoughtProcess
        return domainMsg
    }
}

// MARK: - Artifact Detection (Entity)

@MainActor
extension ChatMessageEntity {
    var hasArtifact: Bool {
        asDomain().hasArtifact
    }

    var artifactMetadata: ArtifactMetadata? {
        asDomain().artifactMetadata
    }

    var artifactMetadatas: [ArtifactMetadata] {
        asDomain().artifactMetadatas
    }

    var rendersContentAsArtifact: Bool {
        asDomain().rendersContentAsArtifact
    }
}
