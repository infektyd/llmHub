//
//  ToolAuthorizationService.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import Foundation
import OSLog

// MARK: - Permission Types
// PermissionStatus is now defined in SharedTypes.swift

// MARK: - Actor

/// A central authority to manage permissions for sensitive tools (e.g., "drive_access", "calendar_write").
/// Handles persistence and thread-safe status checks.
actor ToolAuthorizationService {
    private let logger = Logger(subsystem: "com.llmhub", category: "ToolAuthorizationService")

    // Persistent store of permissions
    private var permissions: [String: PermissionStatus] = [:]
    private let customPersistenceURL: URL?

    // File to persist permissions (simple JSON)
    private var persistenceURL: URL? {
        if let custom = customPersistenceURL { return custom }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("tool_permissions.json")
    }

    init(persistenceURL: URL? = nil) {
        self.customPersistenceURL = persistenceURL
        Task {
            await loadPermissions()
        }
    }

    // MARK: - Public API

    /// Checks the current permission status for a given tool ID.
    func checkAccess(for toolID: String) -> PermissionStatus {
        return permissions[toolID] ?? .notDetermined
    }

    /// Requests access for a tool.
    /// Currently implements an "Auto-approve" policy for the MVP.
    /// Future iterations may integrate with the UI to show a permission prompt.
    func requestAccess(for toolID: String) async -> PermissionStatus {
        if let status = permissions[toolID], status != .notDetermined {
            return status
        }

        logger.info("Requesting access for tool: \(toolID)")

        // Auto-approve policy for MVP/Prototype phase
        let newStatus: PermissionStatus = .authorized

        updatePermission(for: toolID, status: newStatus)
        return newStatus
    }

    /// Explicitly grants access to a tool (e.g. from Settings).
    func grantAccess(for toolID: String) {
        updatePermission(for: toolID, status: .authorized)
        logger.info("Access granted for \(toolID)")
    }

    /// Explicitly revokes access to a tool.
    func revokeAccess(for toolID: String) {
        updatePermission(for: toolID, status: .denied)
        logger.info("Access revoked for \(toolID)")
    }

    /// Resets access status to .notDetermined.
    func resetAccess(for toolID: String) {
        updatePermission(for: toolID, status: .notDetermined)
        logger.info("Access reset for \(toolID)")
    }

    // MARK: - Persistence

    private func updatePermission(for toolID: String, status: PermissionStatus) {
        permissions[toolID] = status
        savePermissions()
    }

    private func loadPermissions() {
        guard let url = persistenceURL,
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let loaded = try? JSONDecoder().decode([String: PermissionStatus].self, from: data)
        else {
            return
        }
        self.permissions = loaded
        logger.debug("Permissions loaded: \(self.permissions.count) entries")
    }

    private func savePermissions() {
        guard let url = persistenceURL else { return }

        // Ensure directory exists
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        do {
            let data = try JSONEncoder().encode(permissions)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save permissions: \(error.localizedDescription)")
        }
    }
}
