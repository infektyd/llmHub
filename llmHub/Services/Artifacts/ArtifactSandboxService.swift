//
//  ArtifactSandboxService.swift
//  llmHub
//
//  Manages the curated artifact sandbox - a secure location where users
//  explicitly upload files for LLM access. LLMs can ONLY access files
//  in this sandbox, preventing unauthorized file system access.
//

import Foundation
import OSLog
import UniformTypeIdentifiers

// MARK: - SandboxedArtifact Model

/// Represents a file that has been imported into the artifact sandbox.
struct SandboxedArtifact: Identifiable, Codable, Sendable, Equatable {
    /// Unique identifier for this artifact.
    let id: UUID
    /// The filename (without path).
    let filename: String
    /// The original path where the file came from (for reference only).
    let originalPath: String?
    /// When the file was imported into the sandbox.
    let importedAt: Date
    /// File size in bytes.
    let sizeBytes: Int
    /// MIME type of the file.
    let mimeType: String
    /// Relative path within the sandbox (for folder structure preservation).
    let sandboxRelativePath: String
    /// Optional user-provided tags for organization.
    var tags: [String] = []
    /// Optional notes about the artifact.
    var notes: String?

    /// The icon to display for this artifact type.
    var iconName: String {
        switch mimeType {
        case _ where mimeType.hasPrefix("image/"):
            return "photo"
        case "application/pdf":
            return "doc.richtext"
        case "application/json":
            return "curlybraces"
        case _ where mimeType.hasPrefix("text/"):
            return "doc.text"
        case _ where filename.hasSuffix(".swift"):
            return "swift"
        case _ where filename.hasSuffix(".py"):
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    /// Human-readable file size.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

// MARK: - ArtifactSandboxService

/// Central service for managing the curated artifact sandbox.
///
/// SECURITY: This service is the ONLY way files should enter the sandbox.
/// All file tool operations are restricted to files managed by this service.
actor ArtifactSandboxService {

    // MARK: - Singleton

    /// Shared instance for app-wide artifact management.
    static let shared = ArtifactSandboxService()

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.llmhub", category: "ArtifactSandbox")

    /// The root directory of the artifact sandbox.
    let sandboxURL: URL

    /// Path to the manifest file tracking all artifacts.
    private let manifestURL: URL

    /// In-memory cache of the manifest.
    private var manifest: [SandboxedArtifact] = []

    // MARK: - Initialization

    init() {
        // Determine sandbox location
        let appSupport =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory

        // Use a dedicated directory for the artifact library
        self.sandboxURL =
            appSupport
            .deletingLastPathComponent()
            .appendingPathComponent("Syntra.llmHub/Data/ArtifactLibrary", isDirectory: true)

        self.manifestURL = sandboxURL.appendingPathComponent(".artifact_manifest.json")

        // Ensure directories exist
        do {
            try FileManager.default.createDirectory(
                at: sandboxURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]  // Owner-only access
            )
            logger.info("Artifact sandbox initialized at: \(self.sandboxURL.path)")
        } catch {
            logger.error(
                "Failed to create artifact sandbox directory: \(error.localizedDescription)")
        }

        // Load manifest
        Task {
            await loadManifest()
        }
    }

    // MARK: - Public API

    /// Import a file from an external location into the sandbox.
    /// The file is COPIED, not moved - the original remains untouched.
    ///
    /// - Parameter sourceURL: The URL of the file to import.
    /// - Returns: The imported artifact metadata.
    /// - Throws: If the file cannot be read or copied.
    func importFile(from sourceURL: URL) async throws -> SandboxedArtifact {
        let fm = FileManager.default

        // Verify source exists and is a file
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw ArtifactSandboxError.sourceNotFound(sourceURL)
        }

        // Get file attributes
        let attrs = try fm.attributesOfItem(atPath: sourceURL.path)
        let sizeBytes = (attrs[.size] as? Int) ?? 0

        // Determine MIME type
        let mimeType = detectMimeType(for: sourceURL)

        // Generate unique filename to avoid collisions
        let datePrefix = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let originalFilename = sourceURL.lastPathComponent
        let uniqueFilename = "\(datePrefix)_\(originalFilename)"

        // Destination in sandbox
        let destinationURL = sandboxURL.appendingPathComponent(uniqueFilename)

        // Copy file to sandbox
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)

        // Set restrictive permissions
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)

        // Create artifact record
        let artifact = SandboxedArtifact(
            id: UUID(),
            filename: originalFilename,
            originalPath: sourceURL.path,
            importedAt: Date(),
            sizeBytes: sizeBytes,
            mimeType: mimeType,
            sandboxRelativePath: uniqueFilename
        )

        // Update manifest
        manifest.append(artifact)
        try await saveManifest()

        logger.info("Imported artifact: \(originalFilename) (\(sizeBytes) bytes)")

        return artifact
    }

    /// Import raw data as a file in the sandbox.
    ///
    /// - Parameters:
    ///   - data: The data to save.
    ///   - filename: The desired filename.
    /// - Returns: The created artifact metadata.
    func importData(_ data: Data, filename: String) async throws -> SandboxedArtifact {
        let datePrefix = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let uniqueFilename = "\(datePrefix)_\(filename)"
        let destinationURL = sandboxURL.appendingPathComponent(uniqueFilename)

        try data.write(to: destinationURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )

        let mimeType = detectMimeType(forFilename: filename)

        let artifact = SandboxedArtifact(
            id: UUID(),
            filename: filename,
            originalPath: nil,
            importedAt: Date(),
            sizeBytes: data.count,
            mimeType: mimeType,
            sandboxRelativePath: uniqueFilename
        )

        manifest.append(artifact)
        try await saveManifest()

        logger.info("Imported data as artifact: \(filename) (\(data.count) bytes)")

        return artifact
    }

    /// Import an entire folder into the sandbox, preserving structure.
    ///
    /// - Parameter folderURL: The folder to import.
    /// - Returns: Array of imported artifacts.
    func importFolder(from folderURL: URL) async throws -> [SandboxedArtifact] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ArtifactSandboxError.sourceNotFound(folderURL)
        }

        var importedArtifacts: [SandboxedArtifact] = []
        let folderName = folderURL.lastPathComponent
        let datePrefix = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let sandboxFolderName = "\(datePrefix)_\(folderName)"
        let sandboxFolderURL = sandboxURL.appendingPathComponent(
            sandboxFolderName, isDirectory: true)

        // Create folder in sandbox
        try fm.createDirectory(at: sandboxFolderURL, withIntermediateDirectories: true)

        // Enumerate and copy files - collect URLs first to avoid async context issues
        var fileURLs: [URL] = []
        if let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                    values.isRegularFile == true
                else {
                    continue
                }
                fileURLs.append(fileURL)
            }
        }

        // Process collected files
        for fileURL in fileURLs {
            // Calculate relative path
            let relativePath = fileURL.path.replacingOccurrences(
                of: folderURL.path + "/",
                with: ""
            )
            let sandboxPath = "\(sandboxFolderName)/\(relativePath)"
            let destinationURL = sandboxURL.appendingPathComponent(sandboxPath)

            // Create intermediate directories
            try fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Copy file
            try fm.copyItem(at: fileURL, to: destinationURL)

            let attrs = try fm.attributesOfItem(atPath: fileURL.path)
            let sizeBytes = (attrs[.size] as? Int) ?? 0

            let artifact = SandboxedArtifact(
                id: UUID(),
                filename: fileURL.lastPathComponent,
                originalPath: fileURL.path,
                importedAt: Date(),
                sizeBytes: sizeBytes,
                mimeType: detectMimeType(for: fileURL),
                sandboxRelativePath: sandboxPath
            )

            manifest.append(artifact)
            importedArtifacts.append(artifact)
        }

        try await saveManifest()
        logger.info("Imported folder with \(importedArtifacts.count) files")

        return importedArtifacts
    }

    /// List all artifacts in the sandbox.
    func listArtifacts() -> [SandboxedArtifact] {
        manifest.sorted { $0.importedAt > $1.importedAt }
    }

    /// Get a specific artifact by ID.
    func artifact(id: UUID) -> SandboxedArtifact? {
        manifest.first { $0.id == id }
    }

    /// Get the full path to an artifact's file.
    func artifactPath(for artifact: SandboxedArtifact) -> URL {
        sandboxURL.appendingPathComponent(artifact.sandboxRelativePath)
    }

    /// Delete an artifact from the sandbox.
    func deleteArtifact(id: UUID) async throws {
        guard let index = manifest.firstIndex(where: { $0.id == id }) else {
            throw ArtifactSandboxError.artifactNotFound(id)
        }

        let artifact = manifest[index]
        let fileURL = sandboxURL.appendingPathComponent(artifact.sandboxRelativePath)

        try FileManager.default.removeItem(at: fileURL)
        manifest.remove(at: index)
        try await saveManifest()

        logger.info("Deleted artifact: \(artifact.filename)")
    }

    /// Clear all artifacts from the sandbox.
    func clearAllArtifacts() async throws {
        let fm = FileManager.default

        // Remove all files except manifest
        if let contents = try? fm.contentsOfDirectory(
            at: sandboxURL, includingPropertiesForKeys: nil)
        {
            for url in contents where url.lastPathComponent != ".artifact_manifest.json" {
                try? fm.removeItem(at: url)
            }
        }

        manifest.removeAll()
        try await saveManifest()

        logger.info("Cleared all artifacts from sandbox")
    }

    /// Get total size of all artifacts.
    var totalSize: Int {
        manifest.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Get count of artifacts.
    var count: Int {
        manifest.count
    }

    // MARK: - Manifest Persistence

    private func loadManifest() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            manifest = []
            return
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode([SandboxedArtifact].self, from: data)
            logger.debug("Loaded \(self.manifest.count) artifacts from manifest")
        } catch {
            logger.error("Failed to load artifact manifest: \(error.localizedDescription)")
            manifest = []
        }
    }

    private func saveManifest() async throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
        logger.debug("Saved manifest with \(self.manifest.count) artifacts")
    }

    // MARK: - MIME Type Detection

    private func detectMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }

    private func detectMimeType(forFilename filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        if let type = UTType(filenameExtension: ext) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

// MARK: - Errors

enum ArtifactSandboxError: LocalizedError {
    case sourceNotFound(URL)
    case artifactNotFound(UUID)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let url):
            return "Source file not found: \(url.lastPathComponent)"
        case .artifactNotFound(let id):
            return "Artifact not found: \(id.uuidString)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}
