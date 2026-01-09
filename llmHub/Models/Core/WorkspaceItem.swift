//
//  WorkspaceItem.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import Foundation

struct WorkspaceItem: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let data: Data
    let contentType: String // e.g., "text/plain", "image/png"
    let createdAt: Date
    let metadata: [String: String]

    // Backward compatibility / Helper for text
    var content: String? {
        String(data: data, encoding: .utf8)
    }

    nonisolated init(
        id: UUID = UUID(),
        filename: String,
        data: Data,
        contentType: String = "application/octet-stream",
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.filename = filename
        self.data = data
        self.contentType = contentType
        self.createdAt = createdAt
        self.metadata = metadata
    }

    // Convenience init for text content
    nonisolated init(id: UUID = UUID(), filename: String, content: String, metadata: [String: String] = [:]) {
        self.id = id
        self.filename = filename
        self.data = content.data(using: .utf8) ?? Data()
        self.contentType = "text/plain"
        self.createdAt = Date()
        self.metadata = metadata
    }
}

extension WorkspaceItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, filename, data, contentType, createdAt, metadata
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.filename = try container.decode(String.self, forKey: .filename)
        self.data = try container.decode(Data.self, forKey: .data)
        self.contentType = try container.decode(String.self, forKey: .contentType)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(filename, forKey: .filename)
        try container.encode(data, forKey: .data)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(metadata, forKey: .metadata)
    }
}
