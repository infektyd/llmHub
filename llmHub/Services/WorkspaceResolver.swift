//
//  WorkspaceResolver.swift
//  llmHub
//
//  Cross-platform workspace path resolution.
//  Handles sandboxing differences between macOS and iOS/iPadOS.
//

import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Resolves the workspace directory for tool file operations.
/// Handles platform-specific sandboxing and user configuration.
struct WorkspaceResolver: Sendable {

    /// Workspace resolution strategy.
    enum Strategy: Sendable {
        /// Use the app's sandbox Documents directory (iOS default).
        case documents
        /// Use a user-configured project folder (macOS typical).
        case userConfigured(URL)
        /// Use the user's home directory (macOS fallback).
        case homeDirectory
        /// Use a temporary sandbox for ephemeral operations.
        case temporary
    }

    /// Resolves the workspace URL based on platform and configuration.
    /// - Parameters:
    ///   - platform: The current platform (macOS, iOS).
    ///   - userOverride: Optional user-configured workspace path.
    /// - Returns: The resolved workspace URL.
    nonisolated static func resolve(
        platform: ToolEnvironment.Platform,
        userOverride: URL? = nil
    ) -> URL {
        // User override takes precedence if valid
        if let override = userOverride, isValidWorkspace(override, on: platform) {
            return override.standardizedFileURL
        }

        // Platform-specific defaults
        switch platform {
        case .macOS:
            return resolveMacOSWorkspace()
        case .iOS:
            return resolveIOSWorkspace()
        }
    }

    /// Validates that a workspace URL is accessible on the given platform.
    /// - Parameters:
    ///   - url: The URL to validate.
    ///   - platform: The current platform.
    /// - Returns: true if the workspace is valid and accessible.
    nonisolated static func isValidWorkspace(_ url: URL, on platform: ToolEnvironment.Platform) -> Bool {
        let fm = FileManager.default

        // Must be a directory
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        // Must be readable
        guard fm.isReadableFile(atPath: url.path) else {
            return false
        }

        // On iOS, must be inside sandbox or have security-scoped access
        if platform == .iOS {
            return isInsideIOSSandbox(url)
        }

        return true
    }

    // MARK: - Platform-Specific Resolution

    private nonisolated static func resolveMacOSWorkspace() -> URL {
        #if os(macOS)
            // Rationale: Tools should operate within an app-controlled workspace root, never $HOME.
            // When App Sandbox is enabled, this directory resolves inside the app container.
            let fm = FileManager.default
            let appSupport =
                fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory

            let workspace = appSupport.appendingPathComponent("llmHub/Workspace", isDirectory: true)
            if !fm.fileExists(atPath: workspace.path) {
                try? fm.createDirectory(at: workspace, withIntermediateDirectories: true)
            }
            return workspace.standardizedFileURL
        #else
            // Fallback for non-macOS platforms
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        #endif
    }

    private nonisolated static func resolveIOSWorkspace() -> URL {
        // Use Documents directory on iOS
        guard
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        else {
            // Fallback to temp directory if Documents unavailable
            return FileManager.default.temporaryDirectory
        }
        return documents.standardizedFileURL
    }

    /// Checks if a URL is inside the iOS app sandbox.
    private nonisolated static func isInsideIOSSandbox(_ url: URL) -> Bool {
        guard
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        else {
            return false
        }

        // Get the container directory (parent of Documents)
        let container = documents.deletingLastPathComponent()
        let standardizedContainer = container.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL.path

        return standardizedURL.hasPrefix(standardizedContainer)
    }

    // MARK: - Security-Scoped Bookmarks (iOS External Access)

    #if canImport(UIKit)
        /// Stores a security-scoped bookmark for user-granted external directory access.
        /// - Parameter url: The URL granted by UIDocumentPickerViewController.
        /// - Returns: Bookmark data that can be persisted and restored.
        static func createSecurityScopedBookmark(for url: URL) throws -> Data {
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw WorkspaceResolutionError.accessDenied(url)
            }
            defer { url.stopAccessingSecurityScopedResource() }

            return try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        /// Resolves a security-scoped bookmark to a URL.
        /// - Parameter bookmarkData: The stored bookmark data.
        /// - Returns: The resolved URL with security-scoped access.
        static func resolveSecurityScopedBookmark(_ bookmarkData: Data) throws -> URL {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                throw WorkspaceResolutionError.staleBookmark
            }

            // Start accessing before returning
            guard url.startAccessingSecurityScopedResource() else {
                throw WorkspaceResolutionError.accessDenied(url)
            }

            return url
        }
    #endif
}

// MARK: - Workspace Resolution Errors

/// Errors related to workspace resolution.
enum WorkspaceResolutionError: LocalizedError, Sendable {
    case accessDenied(URL)
    case staleBookmark
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let url):
            return "Access denied to workspace: \(url.path)"
        case .staleBookmark:
            return "Security-scoped bookmark is stale and needs to be refreshed"
        case .invalidPath(let path):
            return "Invalid workspace path: \(path)"
        }
    }
}
