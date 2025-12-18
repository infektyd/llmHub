import Foundation

/// Centralized path resolution and sandbox allowlist enforcement for tool file operations.
///
/// llmHub security policy (sandbox-only):
/// - Tools must not access arbitrary absolute paths.
/// - All file paths must resolve within the configured `workspaceRoot`.
/// - Symlink escapes are prevented by resolving symlinks before containment checks.
struct ToolPathResolver {

    enum ResolutionKind {
        case file
        case directory
        case any
    }

    /// Resolves a tool-supplied path into a concrete URL within `workspaceRoot`.
    ///
    /// - Parameters:
    ///   - inputPath: User/model-provided path. Must be relative.
    ///   - workspaceRoot: The sandbox workspace root.
    ///   - kind: Expected kind (file/directory/any).
    /// - Throws: `ToolError.sandboxViolation` if the path escapes the workspace or is absolute.
    nonisolated static func resolve(
        inputPath: String,
        workspaceRoot: URL,
        kind: ResolutionKind = .any
    ) throws -> URL {
        let trimmed = inputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidArguments("path is required")
        }

        // Sandbox-only policy: absolute paths are never accepted.
        if trimmed.hasPrefix("/") {
            throw ToolError.sandboxViolation("Absolute paths are not permitted. Provide a path relative to the workspace.")
        }

        let root = workspaceRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL

        // Resolve symlinks (best-effort) before containment checks.
        // Important: the final file may not exist yet (create/edit operations). We therefore resolve
        // symlinks on the deepest existing ancestor, then re-append any remaining path components.
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = resolveSymlinksBestEffort(candidate: candidate, workspaceRoot: root)

        if !isContained(resolvedCandidate, within: resolvedRoot) {
            throw ToolError.sandboxViolation("Access denied: path must remain within the workspace.")
        }

        // Optional kind checks (existence-based).
        switch kind {
        case .any:
            break
        case .file, .directory:
            var isDir = ObjCBool(false)
            if FileManager.default.fileExists(atPath: resolvedCandidate.path, isDirectory: &isDir) {
                switch kind {
                case .file:
                    if isDir.boolValue {
                        throw ToolError.executionFailed("Path points to a directory, not a file.")
                    }
                case .directory:
                    if !isDir.boolValue {
                        throw ToolError.executionFailed("Path points to a file, not a directory.")
                    }
                case .any:
                    break
                }
            }
        }

        return resolvedCandidate
    }

    /// Resolves symlinks for the deepest existing ancestor of `candidate`, then re-appends any missing
    /// components. This prevents symlink escapes even when the leaf path doesn't exist yet.
    nonisolated private static func resolveSymlinksBestEffort(candidate: URL, workspaceRoot: URL) -> URL {
        let fm = FileManager.default
        var existing = candidate
        var remainder: [String] = []

        let rootPath = workspaceRoot.standardizedFileURL.path
        while !fm.fileExists(atPath: existing.path) && existing.standardizedFileURL.path != rootPath {
            remainder.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }

        let resolvedExisting = existing.resolvingSymlinksInPath().standardizedFileURL
        var rebuilt = resolvedExisting
        for comp in remainder {
            rebuilt.appendPathComponent(comp)
        }
        return rebuilt.standardizedFileURL
    }

    nonisolated private static func isContained(_ url: URL, within root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath == rootPath { return true }
        // Ensure we don't treat "/foo/bar2" as contained in "/foo/bar".
        let prefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")
        return urlPath.hasPrefix(prefix)
    }
}
