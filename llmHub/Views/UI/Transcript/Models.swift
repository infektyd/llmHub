//
//  Canvas2Models.swift
//  llmHub
//
//  View models and data structures for the Canvas2 UI
//

import CryptoKit
import Foundation
import SwiftUI

// MARK: - View Models

struct TranscriptRowViewModel: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    let headerLabel: String  // e.g. "Claude 3.5 Sonnet", "You"
    let headerMetaText: String?
    let content: String  // Markdown body
    let isStreaming: Bool
    let generationID: UUID?
    let artifacts: [ArtifactPayload]
    let toolCallID: String? = nil
    let toolResultMeta: ToolResultMeta? = nil
    let toolCallArguments: String? = nil

    // Equatable conformance for efficient SwiftUI diffing
    static func == (lhs: TranscriptRowViewModel, rhs: TranscriptRowViewModel) -> Bool {
        return lhs.id == rhs.id && lhs.role == rhs.role && lhs.headerLabel == rhs.headerLabel
            && lhs.headerMetaText == rhs.headerMetaText
            && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
            && lhs.generationID == rhs.generationID
            && lhs.artifacts == rhs.artifacts
            && lhs.toolCallID == rhs.toolCallID
            && lhs.toolResultMeta == rhs.toolResultMeta
            && lhs.toolCallArguments == rhs.toolCallArguments
    }
}

struct CanvasConversationSummary: Identifiable, Equatable {
    let id: UUID
    let displayTitle: String
    let updatedAt: Date
    let isArchived: Bool
}

enum Canvas2StableIDs {
    static func artifactID(messageID: UUID, metadata: ArtifactMetadata) -> UUID {
        // Stable across recomputes so streaming updates don't invalidate past rows and sidebars.
        // Hash: messageID + filename + language
        var hasher = SHA256()
        hasher.update(data: Data(messageID.uuidString.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(metadata.filename.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(metadata.language.rawValue.utf8))
        let digest = hasher.finalize()
        let bytes = Array(digest)
        let uuidBytes = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }
}

// Note: ArtifactKind, ArtifactStatus, ArtifactAction, ArtifactPayload, and ArtifactMetadata
// are defined in Models/UI/ArtifactTypes.swift
