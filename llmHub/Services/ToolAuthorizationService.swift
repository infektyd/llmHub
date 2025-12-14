//
//  ToolAuthorizationService.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import Combine
import Foundation
import OSLog

// MARK: - Permission Types
// PermissionStatus is now defined in SharedTypes.swift

// MARK: - Service

/// A central authority to manage permissions for sensitive tools (e.g., "drive_access", "calendar_write").
/// Handles persistence and thread-safe status checks.
@MainActor
class ToolAuthorizationService: ObservableObject {
    private let logger = Logger(subsystem: "com.llmhub", category: "ToolAuthorizationService")

    @Published private(set) var permissions: [String: PermissionStatus] = [:]
    @Published private(set) var pendingAuthRequests: [String] = []

    private let persistenceURL: URL?

    init(persistenceURL: URL? = nil) {
        if let url = persistenceURL {
            self.persistenceURL = url
        } else {
            // Default persistence path in Application Support
            let fileManager = FileManager.default
            let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let dir = urls[0].appendingPathComponent("llmhub/permissions", isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            self.persistenceURL = dir.appendingPathComponent("tool_permissions.json")
        }
        loadPermissions()
    }

    // MARK: - Public API

    /// Checks the current permission status for a given tool ID.
    func checkAccess(for toolID: String) -> PermissionStatus {
        permissions[toolID] ?? .notDetermined
    }

    /// Requests access for a tool (synchronous).
    /// Currently implements an "Auto-approve" policy for the MVP.
    /// Future iterations may integrate with the UI to show a permission prompt.
    func requestAccess(for toolID: String) -> PermissionStatus {
        if let status = permissions[toolID], status != .notDetermined {
            return status
        }

        if !pendingAuthRequests.contains(toolID) {
            pendingAuthRequests.append(toolID)
        }
        logger.info("Pending auth for \(toolID)")
        return .notDetermined
    }

    /// Requests access for a tool (async).
    /// Blocks until the user approves or denies access.
    func requestAccessAsync(for toolID: String) async -> PermissionStatus {
        if let status = permissions[toolID], status != .notDetermined {
            return status
        }
        logger.info("Requesting access for tool: \(toolID)")

        // Add to pending for UI prompt
        if !pendingAuthRequests.contains(toolID) {
            pendingAuthRequests.append(toolID)
        }

        // Poll until authorized/denied (UI updates permissions)
        while permissions[toolID] == nil || permissions[toolID] == .notDetermined {
            try? await Task.sleep(nanoseconds: 100_000_000)  // Poll 0.1s
        }
        return permissions[toolID] ?? .denied
    }

    /// Explicitly grants access to a tool (e.g. from Settings).
    func grantAccess(for toolID: String) {
        permissions[toolID] = .authorized
        pendingAuthRequests.removeAll { $0 == toolID }
        savePermissions()
        logger.info("Access granted for \(toolID)")
    }

    /// Explicitly revokes access to a tool.
    func revokeAccess(for toolID: String) {
        permissions[toolID] = .denied
        pendingAuthRequests.removeAll { $0 == toolID }
        savePermissions()
        logger.info("Access revoked for \(toolID)")
    }

    /// Denies access to a tool.
    func denyAccess(for toolID: String) {
        permissions[toolID] = .denied
        pendingAuthRequests.removeAll { $0 == toolID }
        savePermissions()
        logger.info("Access denied for \(toolID)")
    }

    /// Allows access once (MVP: same as grant).
    func allowOnce(for toolID: String) {
        grantAccess(for: toolID)  // MVP same as grant
    }

    /// Resets access status to .notDetermined.
    func resetAccess(for toolID: String) {
        updatePermission(for: toolID, status: .notDetermined)
        logger.info("Access reset for \(toolID)")
    }

    /// UI callback to resolve pending auth.
    nonisolated func resolvePending(toolID: String, status: PermissionStatus) {
        Task { @MainActor in
            updatePermission(for: toolID, status: status)
            pendingAuthRequests.removeAll { $0 == toolID }
        }
    }

    /// Check if a tool is pending authorization.
    func isPending(toolID: String) -> Bool {
        pendingAuthRequests.contains(toolID)
    }

    /// Get all pending authorization requests.
    func allPendingRequests() -> [String] {
        pendingAuthRequests
    }

    // MARK: - Persistence

    private func updatePermission(for toolID: String, status: PermissionStatus) {
        permissions[toolID] = status
        savePermissions()
    }

    private func loadPermissions() {
        guard let url = persistenceURL,
            let data = try? Data(contentsOf: url),
            let loaded = try? JSONDecoder().decode([String: PermissionStatus].self, from: data)
        else {
            logger.debug("No persisted permissions found, starting fresh")
            return
        }
        self.permissions = loaded
        logger.debug("Permissions loaded: \(self.permissions.count) entries")
    }

    private func savePermissions() {
        guard let url = persistenceURL else {
            logger.warning("No persistence URL configured")
            return
        }

        // Ensure directory exists
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        do {
            let data = try JSONEncoder().encode(permissions)
            try data.write(to: url, options: .atomic)
            logger.debug("Permissions saved successfully")
        } catch {
            logger.error("Failed to save permissions: \(error.localizedDescription)")
        }
    }
}
