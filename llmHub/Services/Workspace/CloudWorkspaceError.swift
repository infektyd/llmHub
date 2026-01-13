import Foundation

enum CloudWorkspaceError: LocalizedError {
    case iCloudUnavailable
    case workspaceNotFound(UUID)
    case notADirectory(URL)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available. Please sign in to iCloud and enable iCloud Drive."
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id.uuidString)"
        case .notADirectory(let url):
            return "Expected directory at: \(url.path)"
        case .unknownError:
            return "An unknown error occurred."
        }
    }
}
