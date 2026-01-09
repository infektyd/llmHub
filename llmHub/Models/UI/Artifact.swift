//
//  Artifact.swift
//  llmHub
//
//  Created by User on 2026-01-02.
//

import Foundation
import SwiftUI

/// Represents a distinct piece of non-conversational content (code, file, etc.)
/// This is used primarily for:
/// 1. Staging (formatting/previewing before sending)
/// 2. Structural representation in the transcript (separated from message text)
struct Artifact: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var content: String
    var kind: ArtifactKind
    var language: String? // e.g. "swift", "python"

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        kind: ArtifactKind,
        language: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.kind = kind
        self.language = language
    }
}

// Extension to map to the display-oriented ArtifactPayload
extension Artifact {
    func toPayload() -> ArtifactPayload {
        ArtifactPayload(
            id: id,
            title: title,
            kind: kind,
            status: .success, // Staged/detected artifacts are generally "ready"
            previewText: content,
            actions: [.copy, .open],
            metadata: language.map { ["language": $0] }
        )
    }
}
