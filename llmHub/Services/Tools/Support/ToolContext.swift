// Services/ToolContext.swift
// Execution context for tools

import Foundation
import OSLog

/// Context passed to every tool execution.
struct ToolContext: Sendable {
    let sessionID: UUID
    let workspacePath: URL
    let logger: Logger
    let session: ToolSession
    let authorization: ToolAuthorizationService?

    init(
        sessionID: UUID,
        workspacePath: URL,
        session: ToolSession,
        authorization: ToolAuthorizationService? = nil,
        subsystem: String = "com.llmhub"
    ) {
        self.sessionID = sessionID
        self.workspacePath = workspacePath
        self.session = session
        self.authorization = authorization
        self.logger = Logger(subsystem: subsystem, category: "Tool")
    }
}

/// Actor managing session-scoped state.
actor ToolSession {
    let id: UUID
    private let cache: ToolResultCache
    private var shellSessions: [String: ShellSessionHandle] = [:]
    let settings: SessionSettings

    init(id: UUID = UUID(), settings: SessionSettings = .default) {
        self.id = id
        self.settings = settings
        self.cache = ToolResultCache(maxCount: settings.cacheMaxCount)
    }

    // Cache operations
    func getCached(key: String) async -> ToolResult? {
        await cache.get(key: key)
    }

    func cache(_ result: ToolResult, key: String) async {
        await cache.set(key: key, value: result)
    }

    func clearCache() async {
        await cache.clear()
    }

    // Shell session management
    func shellSession(id: String = "default", cwd: URL) -> ShellSessionHandle {
        if let existing = shellSessions[id] { return existing }
        let session = ShellSessionHandle(id: id, initialCwd: cwd)
        shellSessions[id] = session
        return session
    }

    func terminateShell(id: String) {
        shellSessions.removeValue(forKey: id)
    }

    func terminateAllShells() {
        shellSessions.removeAll()
    }
}

/// Session configuration.
struct SessionSettings: Sendable {
    let cacheMaxCount: Int
    let defaultTimeout: TimeInterval
    let maxConcurrentHeavyTools: Int

    nonisolated static let `default` = SessionSettings(
        cacheMaxCount: 100,
        defaultTimeout: 30,
        maxConcurrentHeavyTools: 3
    )
}

/// Handle for persistent shell sessions.
struct ShellSessionHandle: Sendable {
    let id: String
    let initialCwd: URL
}
