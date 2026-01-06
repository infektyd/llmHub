//
//  ShellSession.swift
//  llmHub
//
//  Persistent shell session actor that maintains cwd across calls.
//  Used by ShellTool to provide stateful command execution.
//

import Foundation
import OSLog

#if os(macOS)

    /// Output from a shell command execution.
    struct ShellOutput: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let duration: TimeInterval

        var combined: String {
            """
            exit_code: \(exitCode)
            stdout:
            \(stdout)
            stderr:
            \(stderr)
            """
        }

        var succeeded: Bool { exitCode == 0 }
    }

    /// Persistent shell session that maintains working directory and environment across calls.
    actor ShellSession {
        /// Unique identifier for this shell session.
        let id: String

        /// Current working directory, persisted between commands.
        private(set) var currentWorkingDirectory: URL

        /// Workspace-scoped temp directory for sandbox-safe temp usage.
        private let tmpDirectory: URL

        /// Environment variables for this session.
        private var environment: [String: String]

        /// Command history for this session.
        private var commandHistory: [String] = []

        /// Logger for shell operations.
        private let logger = Logger(subsystem: "com.llmhub", category: "ShellSession")

        /// Maximum history entries to retain.
        private let maxHistorySize = 100

        init(id: String, initialCwd: URL, environment: [String: String]? = nil) {
            self.id = id
            self.currentWorkingDirectory = initialCwd.standardizedFileURL
            self.tmpDirectory = initialCwd.appendingPathComponent(".tmp", isDirectory: true)
                .standardizedFileURL
            self.environment = environment ?? ProcessInfo.processInfo.environment
            try? FileManager.default.createDirectory(
                at: tmpDirectory, withIntermediateDirectories: true, attributes: nil)
            self.environment["TMPDIR"] = tmpDirectory.path
            self.environment["TEMP"] = tmpDirectory.path
            self.environment["TMP"] = tmpDirectory.path
        }

        // MARK: - Directory Management

        /// Changes the current working directory.
        /// - Parameter path: Absolute or relative path to change to.
        /// - Throws: If the path doesn't exist or isn't a directory.
        func cd(_ path: String) throws {
            let targetURL: URL

            if path.hasPrefix("/") {
                // Absolute path
                targetURL = URL(fileURLWithPath: path).standardizedFileURL
            } else if path.hasPrefix("~") {
                // Home directory expansion
                let expandedPath = (path as NSString).expandingTildeInPath
                targetURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
            } else {
                // Relative path
                targetURL = currentWorkingDirectory.appendingPathComponent(path).standardizedFileURL
            }

            // Verify it exists and is a directory
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw ShellSessionError.directoryNotFound(targetURL.path)
            }

            currentWorkingDirectory = targetURL
            logger.info("Changed directory to: \(targetURL.path)")
        }

        /// Returns the current working directory path.
        func pwd() -> String {
            currentWorkingDirectory.path
        }

        // MARK: - Environment Management

        /// Sets an environment variable for this session.
        func setEnv(_ key: String, value: String) {
            environment[key] = value
        }

        /// Gets an environment variable.
        func getEnv(_ key: String) -> String? {
            environment[key]
        }

        /// Removes an environment variable.
        func unsetEnv(_ key: String) {
            environment.removeValue(forKey: key)
        }

        // MARK: - Command Execution

        /// Executes a shell command in the current working directory.
        /// - Parameters:
        ///   - command: The shell command to execute.
        ///   - timeout: Maximum execution time in seconds.
        ///   - stdin: Optional data to send to stdin.
        /// - Returns: The command output including exit code, stdout, and stderr.
        func execute(
            command: String,
            timeout: TimeInterval = 30,
            stdin: Data? = nil
        ) async throws -> ShellOutput {
            let startTime = Date()

            if containsInvalidShellToken(command) {
                throw ShellSessionError.executionFailed(
                    "Invalid shell token ';&'. Use ';' or '&&' instead.")
            }

            // Record in history
            addToHistory(command)

            let process = Process()
            process.launchPath = "/bin/zsh"
            let (sanitizedCommand, didRewriteTmp) = rewriteTmpPaths(in: command)
            // Avoid login shell startup file overhead/hangs; run without rc files.
            process.arguments = ["-f", "-c", sanitizedCommand]
            process.currentDirectoryURL = currentWorkingDirectory
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let stdinData = stdin {
                let stdinPipe = Pipe()
                stdinPipe.fileHandleForWriting.write(stdinData)
                try? stdinPipe.fileHandleForWriting.close()
                process.standardInput = stdinPipe
            }

            try process.run()

            // Close parent-side write handles so reads can observe EOF when the child exits.
            // Without this, readToEnd() may block because this process still holds a writer.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()

            // Drain stdout/stderr concurrently while the process runs.
            // Waiting for termination before reading can deadlock if pipe buffers fill.
            let stdoutReadTask = Task.detached(priority: nil) {
                (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            }
            let stderrReadTask = Task.detached(priority: nil) {
                (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            }
            if didRewriteTmp {
                logger.info("Rewrote /tmp to \(self.tmpDirectory.path)")
            }
            logger.debug("Executing: \(command)")

            // Wait for completion or timeout
            let didTimeout = await withTaskGroup(of: Bool.self) { group in
                let waitTask = Task.detached(priority: nil) {
                    process.waitUntilExit()
                }
                group.addTask {
                    await waitTask.value
                    return false
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                    return true
                }

                let first = await group.next() ?? true
                group.cancelAll()
                return first
            }

            if didTimeout {
                process.terminate()
                stdoutReadTask.cancel()
                stderrReadTask.cancel()
                throw ShellSessionError.timeout(command: command, seconds: timeout)
            }

            let stdoutData = await stdoutReadTask.value
            let stderrData = await stderrReadTask.value

            let duration = Date().timeIntervalSince(startTime)

            return ShellOutput(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                duration: duration
            )
        }

        // MARK: - History

        /// Returns recent command history.
        func history(limit: Int = 10) -> [String] {
            Array(commandHistory.suffix(limit))
        }

        private func addToHistory(_ command: String) {
            commandHistory.append(command)
            if commandHistory.count > maxHistorySize {
                commandHistory.removeFirst(commandHistory.count - maxHistorySize)
            }
        }

        private func containsInvalidShellToken(_ command: String) -> Bool {
            command.range(of: #";\s*&"#, options: .regularExpression) != nil
        }

        private func rewriteTmpPaths(in command: String) -> (String, Bool) {
            let pattern = #"(^|[\s"\'=])/tmp(?=(/|\s|$))"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return (command, false)
            }
            let range = NSRange(command.startIndex..., in: command)
            let template = "$1" + NSRegularExpression.escapedTemplate(for: tmpDirectory.path)
            let updated = regex.stringByReplacingMatches(
                in: command, options: [], range: range, withTemplate: template)
            return (updated, updated != command)
        }
    }

    // MARK: - Shell Session Errors

    enum ShellSessionError: LocalizedError, Sendable {
        case directoryNotFound(String)
        case timeout(command: String, seconds: TimeInterval)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .directoryNotFound(let path):
                return "Directory not found: \(path)"
            case .timeout(let command, let seconds):
                return "Command timed out after \(Int(seconds))s: \(command)"
            case .executionFailed(let reason):
                return "Shell execution failed: \(reason)"
            }
        }
    }

#else

    // Stub for non-macOS platforms
    struct ShellOutput: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let duration: TimeInterval

        var combined: String { "Shell not available on this platform" }
        var succeeded: Bool { false }
    }

    actor ShellSession {
        let id: String
        private(set) var currentWorkingDirectory: URL

        init(id: String, initialCwd: URL, environment: [String: String]? = nil) {
            self.id = id
            self.currentWorkingDirectory = initialCwd
        }

        func cd(_ path: String) throws {
            throw ToolError.platformNotSupported("Shell access")
        }

        func pwd() -> String { currentWorkingDirectory.path }

        func execute(command: String, timeout: TimeInterval = 30, stdin: Data? = nil) async throws
            -> ShellOutput
        {
            throw ToolError.platformNotSupported("Shell access")
        }
    }

    enum ShellSessionError: LocalizedError, Sendable {
        case platformNotSupported
        var errorDescription: String? { "Shell sessions are only available on macOS" }
    }

#endif
