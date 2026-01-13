import Foundation

/// Metadata for a workspace, stored as manifest.json.
struct WorkspaceManifest: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    var modifiedAt: Date
    let platform: String  // "macOS" or "iOS" — where it was created

    var name: String?
    var description: String?
}
