//
//  NeonPreviewAssets.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation

struct NeonPreviewAssets {
    static let sampleConversations: [ChatSession] = [
        ChatSession(
            id: UUID(),
            title: "SwiftUI Animation Helpers",
            providerID: "anthropic",
            model: "claude-3-sonnet",
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: ""),
            tags: [ChatTag(id: UUID(), name: "Swift", color: "#FF0066")],
            isPinned: true
        ),
        ChatSession(
            id: UUID(),
            title: "Database Schema Design",
            providerID: "openai",
            model: "gpt-4",
            createdAt: Date().addingTimeInterval(-7200),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: ""),
            tags: [ChatTag(id: UUID(), name: "SQL", color: "#00BFFF")],
            isPinned: false
        ),
        ChatSession(
            id: UUID(),
            title: "API Integration Strategy",
            providerID: "google",
            model: "gemini-pro",
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: ""),
            tags: [],
            isPinned: false
        ),
        ChatSession(
            id: UUID(),
            title: "Code Review: Auth Module",
            providerID: "anthropic",
            model: "claude-3-opus",
            createdAt: Date().addingTimeInterval(-172800),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(lastTokenUsage: nil, totalCostUSD: 0, referenceID: ""),
            tags: [ChatTag(id: UUID(), name: "Security", color: "#FFD700")],
            isPinned: false
        ),
    ]
}
