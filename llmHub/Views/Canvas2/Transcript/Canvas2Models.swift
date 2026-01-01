//
//  Canvas2Models.swift
//  llmHub
//
//  View models and data structures for the Canvas2 UI
//

import Foundation
import SwiftUI

// MARK: - View Models

struct TranscriptRowViewModel: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let headerLabel: String  // e.g. "Claude 3.5 Sonnet", "You"
    let content: String  // Markdown body
    let isStreaming: Bool
    let artifacts: [ArtifactPayload]

    // Equatable conformance for efficient SwiftUI diffing
    static func == (lhs: TranscriptRowViewModel, rhs: TranscriptRowViewModel) -> Bool {
        return lhs.id == rhs.id && lhs.role == rhs.role && lhs.headerLabel == rhs.headerLabel
            && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
            && lhs.artifacts == rhs.artifacts
    }
}

enum ArtifactKind: String, Equatable {
    case code
    case text
    case image
    case toolResult
    case other
}

enum ArtifactStatus: String, Equatable {
    case pending
    case success
    case failure
}

enum ArtifactAction: String, Equatable {
    case copy
    case open
    case preview
}

struct ArtifactPayload: Identifiable, Equatable {
    let id: UUID
    let title: String
    let kind: ArtifactKind
    let status: ArtifactStatus
    let previewText: String
    let actions: [ArtifactAction]

    // Mapped from existing ArtifactMetadata if present
    let metadata: ArtifactMetadata?

    static func == (lhs: ArtifactPayload, rhs: ArtifactPayload) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title && lhs.kind == rhs.kind
            && lhs.status == rhs.status && lhs.previewText == rhs.previewText
            && lhs.actions == rhs.actions
    }
}
