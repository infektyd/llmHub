//
//  SandboxManager.swift
//  llmHub
//
//  Manages isolated temp directories for code execution
//

import Foundation
import OSLog

/// Manages isolated sandbox directories for safe code execution.
actor SandboxManager {
    /// Logger instance.
    private let logger = Logger(subsystem: "com.llmhub", category: "SandboxManager")
    /// The base directory for all sandboxes.
    private let baseDirectory: URL
    /// Dictionary of active sandboxes keyed by execution ID.
    private var activeSandboxes: [UUID: URL] = [:]

    /// Initializes a new `SandboxManager`.
    init() {
        self.baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmHub-sandbox", isDirectory: true)

        // Ensure base directory exists
        try? FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Sandbox Lifecycle

    /// Create a new isolated sandbox directory for code execution.
    /// - Parameter executionID: The unique ID of the execution.
    /// - Returns: The URL of the created sandbox.
    func createSandbox(for executionID: UUID) throws -> URL {
        let sandboxPath = baseDirectory
            .appendingPathComponent(executionID.uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: sandboxPath,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700] // Owner read/write/execute only
            )

            activeSandboxes[executionID] = sandboxPath
            logger.debug("Created sandbox at: \(sandboxPath.path)")
            return sandboxPath

        } catch {
            logger.error("Failed to create sandbox: \(error.localizedDescription)")
            throw CodeExecutionError.sandboxCreationFailed(error.localizedDescription)
        }
    }

    /// Write code to a file within the sandbox.
    /// - Parameters:
    ///   - sandboxPath: The sandbox directory URL.
    ///   - code: The code content.
    ///   - language: The programming language.
    /// - Returns: The URL of the written file.
    func writeCodeFile(
        in sandboxPath: URL,
        code: String,
        language: SupportedLanguage
    ) throws -> URL {
        let filename = "main\(language.fileExtensionValue)"
        let filePath = sandboxPath.appendingPathComponent(filename)

        do {
            try code.write(to: filePath, atomically: true, encoding: .utf8)

            // Make executable for scripts that need it
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: filePath.path
            )

            logger.debug("Wrote code file: \(filePath.path)")
            return filePath

        } catch {
            logger.error("Failed to write code file: \(error.localizedDescription)")
            throw CodeExecutionError.fileWriteFailed(error.localizedDescription)
        }
    }

    /// Clean up a specific sandbox after execution.
    /// - Parameter executionID: The execution ID to cleanup.
    func cleanupSandbox(for executionID: UUID) {
        guard let sandboxPath = activeSandboxes.removeValue(forKey: executionID) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: sandboxPath)
            logger.debug("Cleaned up sandbox: \(sandboxPath.path)")
        } catch {
            logger.warning("Failed to cleanup sandbox: \(error.localizedDescription)")
        }
    }

    /// Clean up all sandboxes (call on app termination or periodically).
    func cleanupAllSandboxes() {
        for (id, _) in activeSandboxes {
            cleanupSandbox(for: id)
        }

        // Also clean any orphaned sandboxes from previous runs
        cleanupOrphanedSandboxes()
    }

    /// Remove sandboxes older than the specified age.
    /// - Parameter age: Maximum age in seconds (default: 3600).
    func cleanupOrphanedSandboxes(olderThan age: TimeInterval = 3600) {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-age)

        for url in contents {
            guard let attributes = try? url.resourceValues(forKeys: [.creationDateKey]),
                  let creationDate = attributes.creationDate,
                  creationDate < cutoffDate else {
                continue
            }

            // Check if it's still active
            if let uuid = UUID(uuidString: url.lastPathComponent),
               activeSandboxes[uuid] != nil {
                continue
            }

            do {
                try fileManager.removeItem(at: url)
                logger.debug("Cleaned up orphaned sandbox: \(url.path)")
            } catch {
                logger.warning("Failed to cleanup orphaned sandbox: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sandbox Utilities

    /// Get the path to a sandbox for a given execution ID.
    /// - Parameter executionID: The execution ID.
    /// - Returns: The sandbox URL if active.
    func sandboxPath(for executionID: UUID) -> URL? {
        activeSandboxes[executionID]
    }

    /// Check if a path is within a sandbox.
    /// - Parameters:
    ///   - path: The path to check.
    ///   - executionID: The execution ID of the sandbox.
    /// - Returns: True if the path is inside the sandbox.
    func isPathInSandbox(_ path: URL, for executionID: UUID) -> Bool {
        guard let sandboxPath = activeSandboxes[executionID] else {
            return false
        }

        let resolvedPath = path.standardizedFileURL.path
        let resolvedSandbox = sandboxPath.standardizedFileURL.path

        return resolvedPath.hasPrefix(resolvedSandbox)
    }

    /// List files created during execution within a sandbox.
    /// - Parameter executionID: The execution ID.
    /// - Returns: A list of file URLs.
    func listSandboxContents(for executionID: UUID) -> [URL] {
        guard let sandboxPath = activeSandboxes[executionID] else {
            return []
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sandboxPath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                files.append(url)
            }
        }

        return files
    }

    /// Read output files from sandbox (e.g., generated images).
    /// - Parameters:
    ///   - executionID: The execution ID.
    ///   - extensions: Set of file extensions to read.
    /// - Returns: An array of tuples containing filename and data.
    func readOutputFiles(
        for executionID: UUID,
        matching extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "json", "txt"]
    ) -> [(filename: String, data: Data)] {
        let files = listSandboxContents(for: executionID)

        var outputs: [(String, Data)] = []

        for file in files {
            let ext = file.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }

            // Skip the source file
            if SupportedLanguage.allCases.map({ $0.fileExtensionValue }).contains(".\(ext)") {
                continue
            }

            if let data = try? Data(contentsOf: file) {
                outputs.append((file.lastPathComponent, data))
            }
        }

        return outputs
    }
}

// MARK: - Sandbox Environment

extension SandboxManager {
    /// Get environment variables configured for sandboxed execution.
    /// - Parameter executionID: The execution ID.
    /// - Returns: A dictionary of environment variables.
    func sandboxEnvironment(for executionID: UUID) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Restrict HOME to sandbox
        if let sandboxPath = activeSandboxes[executionID] {
            env["HOME"] = sandboxPath.path
            env["TMPDIR"] = sandboxPath.path
            env["XDG_CACHE_HOME"] = sandboxPath.path
        }

        // Remove potentially dangerous environment variables
        env.removeValue(forKey: "SSH_AUTH_SOCK")
        env.removeValue(forKey: "GPG_AGENT_INFO")

        return env
    }
}
