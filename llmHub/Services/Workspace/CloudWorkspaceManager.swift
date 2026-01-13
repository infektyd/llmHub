import Foundation
import OSLog

/// Manages workspaces stored in iCloud Documents for cross-platform sync.
actor CloudWorkspaceManager {

    static let shared = CloudWorkspaceManager()

    private let logger = Logger(subsystem: "com.llmhub", category: "CloudWorkspaceManager")
    private let containerIdentifier = "iCloud.Syntra.llmHub"
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    nonisolated private static let defaultWorkspaceIDKey = "llmhub.defaultWorkspaceID"

    // MARK: - Container Access

    /// Returns the iCloud container URL, or nil if iCloud unavailable.
    /// IMPORTANT: Call from background thread — can block.
    func containerURL() async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = FileManager.default.url(
                    forUbiquityContainerIdentifier: self.containerIdentifier
                )
                continuation.resume(returning: url)
            }
        }
    }

    /// Returns the Documents folder inside the iCloud container.
    /// This is where files must live to appear in Files.app/Finder.
    func documentsURL() async -> URL? {
        guard let container = await containerURL() else { return nil }
        return container.appendingPathComponent("Documents")
    }

    /// Returns the Workspaces folder, creating it if needed.
    func workspacesRootURL() async throws -> URL {
        guard let docs = await documentsURL() else {
            throw CloudWorkspaceError.iCloudUnavailable
        }
        let workspacesURL = docs.appendingPathComponent("Workspaces")
        try await ensureDirectoryExists(at: workspacesURL)
        return workspacesURL
    }

    // MARK: - Workspace Operations

    nonisolated func defaultWorkspaceID() -> UUID {
        let ubiq = NSUbiquitousKeyValueStore.default
        if let s = ubiq.string(forKey: Self.defaultWorkspaceIDKey),
           let id = UUID(uuidString: s) {
            return id
        }

        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: Self.defaultWorkspaceIDKey),
           let id = UUID(uuidString: s) {
            ubiq.set(id.uuidString, forKey: Self.defaultWorkspaceIDKey)
            ubiq.synchronize()
            return id
        }

        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.defaultWorkspaceIDKey)
        ubiq.set(id.uuidString, forKey: Self.defaultWorkspaceIDKey)
        ubiq.synchronize()
        return id
    }

    /// Creates a new workspace with the given ID, returns its URL.
    func createWorkspace(id: UUID) async throws -> URL {
        let root = try await bestAvailableWorkspacesRoot()
        let workspaceURL = root.appendingPathComponent(id.uuidString)
        try await ensureDirectoryExists(at: workspaceURL)

        let userFilesURL = workspaceURL.appendingPathComponent("user_files", isDirectory: true)
        try await ensureDirectoryExists(at: userFilesURL)

        // Create manifest
        let manifest = await MainActor.run {
            WorkspaceManifest(
                id: id,
                createdAt: Date(),
                modifiedAt: Date(),
                platform: currentPlatform()
            )
        }
        try await writeManifest(manifest, to: workspaceURL)

        logger.info("Created workspace: \(id.uuidString)")
        return workspaceURL
    }

    /// Returns URL for existing workspace, or nil if not found.
    func workspaceURL(for id: UUID) async throws -> URL? {
        for root in try await candidateWorkspaceRoots() {
            let url = root.appendingPathComponent(id.uuidString)

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return url
            }
        }
        return nil
    }

    /// Gets or creates workspace URL.
    func getOrCreateWorkspace(id: UUID) async throws -> URL {
        if let existing = try await workspaceURL(for: id) {
            return existing
        }
        return try await createWorkspace(id: id)
    }

    /// Lists all workspace IDs.
    func listWorkspaces() async throws -> [UUID] {
        var found: Set<UUID> = []

        for root in try await candidateWorkspaceRoots() {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }

            let contents = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                if let id = UUID(uuidString: url.lastPathComponent) {
                    found.insert(id)
                }
            }
        }

        return found.sorted { $0.uuidString < $1.uuidString }
    }

    /// Deletes a workspace.
    func deleteWorkspace(id: UUID) async throws {
        var deletedAny = false

        for root in try await candidateWorkspaceRoots() {
            let url = root.appendingPathComponent(id.uuidString)

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }

            try await coordinatedDelete(at: url)
            deletedAny = true
        }

        if deletedAny {
            logger.info("Deleted workspace: \(id.uuidString)")
        }
    }

    // MARK: - File Operations (Coordinated)

    /// Writes data to a file in the workspace using NSFileCoordinator.
    func writeFile(
        data: Data,
        named filename: String,
        inWorkspace workspaceID: UUID
    ) async throws {
        let workspaceURL = try await getOrCreateWorkspace(id: workspaceID)
        let fileURL = workspaceURL.appendingPathComponent(filename)
        try await ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
        try await coordinatedWrite(data: data, to: fileURL)
    }

    /// Reads data from a file in the workspace.
    func readFile(
        named filename: String,
        inWorkspace workspaceID: UUID
    ) async throws -> Data {
        guard let workspaceURL = try await workspaceURL(for: workspaceID) else {
            throw CloudWorkspaceError.workspaceNotFound(workspaceID)
        }
        let fileURL = workspaceURL.appendingPathComponent(filename)
        return try await coordinatedRead(from: fileURL)
    }

    /// Lists files in a workspace.
    func listFiles(inWorkspace workspaceID: UUID) async throws -> [String] {
        guard let workspaceURL = try await workspaceURL(for: workspaceID) else {
            throw CloudWorkspaceError.workspaceNotFound(workspaceID)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: workspaceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return contents.map { $0.lastPathComponent }
    }

    /// Saves common code execution outputs into the workspace.
    func saveExecutionOutput(
        result: CodeExecutionResult,
        toWorkspace workspaceID: UUID
    ) async throws {
        // Save stdout
        if !result.stdout.isEmpty {
            let data = result.stdout.data(using: .utf8) ?? Data()
            try await writeFile(
                data: data,
                named: "output_\(result.id.uuidString).txt",
                inWorkspace: workspaceID
            )
        }

        // Save stderr
        if !result.stderr.isEmpty {
            let data = result.stderr.data(using: .utf8) ?? Data()
            try await writeFile(
                data: data,
                named: "error_\(result.id.uuidString).txt",
                inWorkspace: workspaceID
            )
        }

        // Save the executed code
        let codeData = result.code.data(using: .utf8) ?? Data()
        try await writeFile(
            data: codeData,
            named: "code_\(result.id.uuidString)\(result.language.fileExtensionValue)",
            inWorkspace: workspaceID
        )

        // Save selected sandbox output files (best-effort)
        if let sandboxPath = result.sandboxPath {
            let sandboxURL = URL(fileURLWithPath: sandboxPath)
            let fm = FileManager.default
            let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "json", "txt"]

            let fileExtension = result.language.fileExtensionValue

            var candidateURLs: [URL] = []
            if let enumerator = fm.enumerator(
                at: sandboxURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                while let next = enumerator.nextObject() as? URL {
                    candidateURLs.append(next)
                }
            }

            for url in candidateURLs {
                let ext = url.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }

                if url.lastPathComponent == "main\(fileExtension)" {
                    continue
                }

                if let data = try? Data(contentsOf: url) {
                    try? await writeFile(
                        data: data,
                        named: url.lastPathComponent,
                        inWorkspace: workspaceID
                    )
                }
            }
        }
    }

    // MARK: - NSFileCoordinator Helpers

    private func coordinatedWrite(data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var coordinationError: NSError?
            var writeError: Error?

            fileCoordinator.coordinate(
                writingItemAt: url,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }

            if let error = writeError {
                continuation.resume(throwing: error)
            } else if let error = coordinationError {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    private func coordinatedRead(from url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var coordinationError: NSError?
            var readResult: Result<Data, Error>?

            fileCoordinator.coordinate(
                readingItemAt: url,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    let data = try Data(contentsOf: coordinatedURL)
                    readResult = .success(data)
                } catch {
                    readResult = .failure(error)
                }
            }

            if let error = coordinationError {
                continuation.resume(throwing: error)
            } else if let result = readResult {
                continuation.resume(with: result)
            } else {
                continuation.resume(throwing: CloudWorkspaceError.unknownError)
            }
        }
    }

    private func coordinatedDelete(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var coordinationError: NSError?
            var deleteError: Error?

            fileCoordinator.coordinate(
                writingItemAt: url,
                options: .forDeleting,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try FileManager.default.removeItem(at: coordinatedURL)
                } catch {
                    deleteError = error
                }
            }

            if let error = deleteError {
                continuation.resume(throwing: error)
            } else if let error = coordinationError {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    private func ensureDirectoryExists(at url: URL) async throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return }
            throw CloudWorkspaceError.notADirectory(url)
        }

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Manifest

    private func writeManifest(_ manifest: WorkspaceManifest, to workspaceURL: URL) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try await MainActor.run {
            try encoder.encode(manifest)
        }
        let manifestURL = workspaceURL.appendingPathComponent("manifest.json")
        try await coordinatedWrite(data: data, to: manifestURL)
    }

    nonisolated private func currentPlatform() -> String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "unknown"
        #endif
    }
}

// MARK: - Local Fallback

extension CloudWorkspaceManager {

    /// Returns local fallback URL when iCloud unavailable.
    func localFallbackURL() -> URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documents.appendingPathComponent("Workspaces")
    }

    /// Returns best available workspace root (iCloud preferred, local fallback).
    func bestAvailableWorkspacesRoot() async throws -> URL {
        if let iCloudURL = try? await workspacesRootURL() {
            return iCloudURL
        }

        // Fallback to local
        let localURL = localFallbackURL()
        try FileManager.default.createDirectory(
            at: localURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return localURL
    }

    private func candidateWorkspaceRoots() async throws -> [URL] {
        var roots: [URL] = []

        if let iCloudURL = try? await workspacesRootURL() {
            roots.append(iCloudURL)
        }

        let localURL = localFallbackURL()
        try FileManager.default.createDirectory(
            at: localURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        roots.append(localURL)

        // Prefer iCloud root first if available
        var seenPaths: Set<String> = []
        var uniqueRoots: [URL] = []
        for url in roots {
            let path = url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                uniqueRoots.append(url)
            }
        }
        return uniqueRoots
    }
}
