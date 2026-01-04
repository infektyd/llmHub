//
//  ArtifactTypes.swift
//  llmHub
//
//  UI-facing artifact type definitions for cards and inspector views.
//

import Foundation
import SwiftUI

// MARK: - Artifact Kind

/// The type/category of artifact content.
enum ArtifactKind: String, Codable, Sendable, CaseIterable {
    case code
    case text
    case image
    case toolResult
    case other
    
    var displayName: String {
        switch self {
        case .code: return "Code"
        case .text: return "Text"
        case .image: return "Image"
        case .toolResult: return "Tool Result"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .image: return "photo"
        case .toolResult: return "gearshape.2"
        case .other: return "doc"
        }
    }
}

// MARK: - Artifact Status

/// The current status of an artifact (e.g., tool execution state).
enum ArtifactStatus: String, Codable, Sendable {
    case pending
    case success
    case failure
    
    var color: Color {
        switch self {
        case .pending: return .orange
        case .success: return .green
        case .failure: return .red
        }
    }
}

// MARK: - Artifact Action

/// Actions available on an artifact card.
enum ArtifactAction: String, Codable, Sendable, CaseIterable {
    case copy
    case open
    case download
    case share
    case retry
    
    var displayName: String {
        switch self {
        case .copy: return "Copy"
        case .open: return "Open"
        case .download: return "Download"
        case .share: return "Share"
        case .retry: return "Retry"
        }
    }
    
    var icon: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .open: return "arrow.up.right.square"
        case .download: return "arrow.down.circle"
        case .share: return "square.and.arrow.up"
        case .retry: return "arrow.clockwise"
        }
    }
}

// MARK: - Artifact Payload

/// Display-oriented artifact model for UI rendering.
/// Used by ArtifactCardView and inspector panels.
struct ArtifactPayload: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let kind: ArtifactKind
    let status: ArtifactStatus
    let previewText: String
    let actions: [ArtifactAction]
    let metadata: [String: String]?
    
    init(
        id: UUID = UUID(),
        title: String,
        kind: ArtifactKind,
        status: ArtifactStatus = .success,
        previewText: String,
        actions: [ArtifactAction] = [.copy],
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.previewText = previewText
        self.actions = actions
        self.metadata = metadata
    }
}

// MARK: - Artifact Metadata

/// Metadata for file-backed artifacts (used by ArtifactCard).
struct ArtifactMetadata: Identifiable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let content: String
    let language: ArtifactLanguage
    let sizeBytes: Int
    let fileURL: URL?
    
    init(
        id: UUID = UUID(),
        filename: String,
        content: String,
        language: ArtifactLanguage,
        sizeBytes: Int,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.filename = filename
        self.content = content
        self.language = language
        self.sizeBytes = sizeBytes
        self.fileURL = fileURL
    }
}

/// Language/syntax type for syntax highlighting.
enum ArtifactLanguage: String, Codable, Sendable, CaseIterable {
    case json
    case swift
    case python
    case javascript
    case markdown
    case text
    
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
    
    /// Infer language from filename extension.
    static func infer(from filename: String) -> ArtifactLanguage {
        let ext = filename.split(separator: ".").last?.lowercased() ?? ""
        switch ext {
        case "json", "jsonl": return .json
        case "swift": return .swift
        case "py": return .python
        case "js", "ts", "jsx", "tsx": return .javascript
        case "md", "markdown": return .markdown
        default: return .text
        }
    }
}
