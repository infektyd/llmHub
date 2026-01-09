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

/// A central authority to manage permissions for sensitive tools.
/// SECURITY: Implements conversation-scoped authorization with secure-by-default policy.
/// Default permission is .denied (not .notDetermined) to prevent unauthorized access.
@MainActor
class ToolAuthorizationService: ObservableObject {
    private let logger = Logger(subsystem: "com.llmhub", category: "ToolAuthorizationService")

    // Global permissions (legacy, for backward compatibility)
    @Published private(set) var permissions: [String: PermissionStatus] = [:]
    
    // Conversation-scoped permissions: [conversationID: [toolID: status]]
    @Published private(set) var conversationPermissions: [UUID: [String: PermissionStatus]] = [:]
    
    @Published private(set) var pendingAuthRequests: [String] = []

    private let persistenceURL: URL?

    static let shared = ToolAuthorizationService()

    init(persistenceURL: URL? = nil) {
        if let url = persistenceURL {
            self.persistenceURL = url
        } else {
            // Default persistence path in Application Support
            let fileManager = FileManager.default
            let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let dir = urls[0].appendingPathComponent("llmhub/permissions", isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(
                    at: dir, withIntermediateDirectories: true, attributes: nil)
            }
            self.persistenceURL = dir.appendingPathComponent("tool_permissions.json")
        }
        loadPermissions()
    }

    // MARK: - Public API

    /// Checks the current permission status for a given tool ID.
    /// SECURITY: Defaults to .denied (not .notDetermined) for secure-by-default behavior.
    func checkAccess(for toolID: String) -> PermissionStatus {
        permissions[toolID] ?? .denied
    }
    
    /// Checks permission for a tool in a specific conversation context.
    /// SECURITY: Conversation-scoped permissions take precedence over global permissions.
    /// Returns .denied if no permission is explicitly granted.
    func checkAccess(for toolID: String, conversationID: UUID) -> PermissionStatus {
        // Check conversation-specific permission first
        if let convPerms = conversationPermissions[conversationID],
           let status = convPerms[toolID] {
            logger.debug("🔐 [\(conversationID.uuidString.prefix(8))] Tool \(toolID): \(status)")
            return status
        }
        
        // Fall back to global permission, but default to .denied
        let status = permissions[toolID] ?? .denied
        logger.debug("🔐 [Global] Tool \(toolID): \(status)")
        return status
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
    
    // MARK: - Conversation-Scoped Authorization
    
    /// Grants access to a tool for a specific conversation.
    func grantAccessForConversation(toolID: String, conversationID: UUID) {
        if conversationPermissions[conversationID] == nil {
            conversationPermissions[conversationID] = [:]
        }
        conversationPermissions[conversationID]?[toolID] = .authorized
        logger.info("🔓 [\(conversationID.uuidString.prefix(8))] Access granted for \(toolID)")
        saveConversationPermissions()
    }
    
    /// Denies access to a tool for a specific conversation.
    func denyAccessForConversation(toolID: String, conversationID: UUID) {
        if conversationPermissions[conversationID] == nil {
            conversationPermissions[conversationID] = [:]
        }
        conversationPermissions[conversationID]?[toolID] = .denied
        logger.info("🔒 [\(conversationID.uuidString.prefix(8))] Access denied for \(toolID)")
        saveConversationPermissions()
    }
    
    /// Clears all permissions for a conversation (useful on conversation end).
    func clearConversationPermissions(conversationID: UUID) {
        conversationPermissions.removeValue(forKey: conversationID)
        logger.info("🧹 [\(conversationID.uuidString.prefix(8))] Cleared all permissions")
        saveConversationPermissions()
    }
    
    /// Gets all tools with authorized status for a conversation.
    func authorizedTools(for conversationID: UUID) -> [String] {
        guard let convPerms = conversationPermissions[conversationID] else { return [] }
        return convPerms.filter { $0.value == .authorized }.map { $0.key }
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
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: nil)
        }

        do {
            let data = try JSONEncoder().encode(permissions)
            try data.write(to: url, options: .atomic)
            logger.debug("Permissions saved successfully")
        } catch {
            logger.error("Failed to save permissions: \(error.localizedDescription)")
        }
    }
    
    private func saveConversationPermissions() {
        guard let persistenceURL = persistenceURL else { return }
        let convURL = persistenceURL.deletingLastPathComponent()
            .appendingPathComponent("conversation_permissions.json")
        
        do {
            // Convert UUID keys to strings for JSON encoding
            let stringKeyed = Dictionary(uniqueKeysWithValues: 
                conversationPermissions.map { ($0.key.uuidString, $0.value) }
            )
            let data = try JSONEncoder().encode(stringKeyed)
            try data.write(to: convURL, options: .atomic)
            logger.debug("Conversation permissions saved: \(conversationPermissions.count) conversations")
        } catch {
            logger.error("Failed to save conversation permissions: \(error.localizedDescription)")
        }
    }
    
    private func loadConversationPermissions() {
        guard let persistenceURL = persistenceURL else { return }
        let convURL = persistenceURL.deletingLastPathComponent()
            .appendingPathComponent("conversation_permissions.json")
        
        guard let data = try? Data(contentsOf: convURL),
              let stringKeyed = try? JSONDecoder().decode([String: [String: PermissionStatus]].self, from: data)
        else {
            logger.debug("No persisted conversation permissions found")
            return
        }
        
        // Convert string keys back to UUIDs
        conversationPermissions = Dictionary(uniqueKeysWithValues: 
            stringKeyed.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            }
        )
        logger.debug("Loaded conversation permissions: \(conversationPermissions.count) conversations")
    }
}

// MARK: - PermissionStatus Extension

extension PermissionStatus: Codable {}
