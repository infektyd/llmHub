//
//  ShellTool.swift
//  llmHub
//
//  Shell command execution tool (macOS only)
//

import Foundation
import OSLog

/// Shell Tool conforming to the unified Tool protocol.
nonisolated struct ShellTool: Tool {
    let name = "shell"
    let description = """
        Execute shell commands on macOS. \
        Use this tool when you need to run terminal commands, \
        manipulate files via command line, or access system utilities. \
        Avoid '/tmp' paths in sandboxed runs (use $TMPDIR instead). \
        Use '&&' or ';' for chaining; avoid ';&' which is case-only syntax. \
        Not available on iOS for security reasons.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "command": ToolProperty(type: .string, description: "The shell command to execute"),
                "working_directory": ToolProperty(
                    type: .string,
                    description:
                        "Optional working directory for the command (default: current directory)"
                ),
                "timeout": ToolProperty(
                    type: .integer, description: "Timeout in seconds (default: 30, max: 120)"),
                "environment_variables": ToolProperty(
                    type: .object,
                    description: "Optional environment variables to set for the command"
                ),
                "pipe_input": ToolProperty(type: .string, description: "Data to send to stdin"),
                "background": ToolProperty(
                    type: .boolean,
                    description: "Run without waiting for completion (default: false)"
                )
            ],
            required: ["command"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .dangerous
    let requiredCapabilities: [ToolCapability] = [.shellExecution]
    let weight: ToolWeight = .heavy
    let isCacheable = false

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        #if os(iOS)
            throw ToolError.unavailable(reason: "Shell access is not permitted on iOS.")
        #else
            guard let command = arguments.string("command"), !command.isEmpty else {
                throw ToolError.invalidArguments("command is required")
            }

            if containsInvalidShellToken(command) {
                throw ToolError.invalidArguments("Invalid shell token ';&'. Use ';' or '&&' instead.")
            }

            let workingDirectory = arguments.string("working_directory")
            let timeoutSeconds = max(1, min(arguments.int("timeout") ?? 30, 120))
            let envArgs =
                arguments.object("environment_variables")?.compactMapValues { $0.description }
                ?? [:]
            let stdinData = arguments.string("pipe_input")?.data(using: .utf8)
            let runInBackground = arguments.bool("background") ?? false

            let tempDir = context.workspacePath.appendingPathComponent(".tmp", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let (sanitizedCommand, didRewriteTmp) = rewriteTmpPaths(in: command, tmpPath: tempDir.path)

            context.logger.info("Executing shell command: \(sanitizedCommand)")

            let process = Process()
            process.launchPath = "/bin/zsh"
            process.arguments = ["-lc", sanitizedCommand]

            if let workingDir = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
            } else {
                // Use workspace path by default if not specified
                process.currentDirectoryURL = context.workspacePath
            }

            var fullEnv = ProcessInfo.processInfo.environment
            envArgs.forEach { fullEnv[$0.key] = $0.value }
            fullEnv["TMPDIR"] = tempDir.path
            fullEnv["TEMP"] = tempDir.path
            fullEnv["TMP"] = tempDir.path
            process.environment = fullEnv

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let stdinData {
                let stdinPipe = Pipe()
                try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                try? stdinPipe.fileHandleForWriting.close()
                process.standardInput = stdinPipe
            }

            let terminationStream = AsyncStream<Void> { continuation in
                process.terminationHandler = { _ in
                    continuation.yield(())
                    continuation.finish()
                }
            }

            try process.run()

            if runInBackground {
                return ToolResult.success(
                    "Process started (pid \(process.processIdentifier)). Running in background.",
                    metadata: ["pid": "\(process.processIdentifier)"]
                )
            }

            // Timeout Logic
            let didTimeout = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await _ in terminationStream { break }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    return true
                }
                return await group.next() ?? true
            }

            if didTimeout {
                process.terminate()
                throw ToolError.timeout(after: TimeInterval(timeoutSeconds))
            }

            let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()

            let exitCode = process.terminationStatus
            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

            var combined = """
                exit_code: \(exitCode)
                stdout:
                \(stdoutText)
                stderr:
                \(stderrText)
                """
            if didRewriteTmp {
                combined = """
                    Note: Rewrote /tmp to \(tempDir.path) due to sandbox restrictions.

                    \(combined)
                    """
            }

            if exitCode == 0 {
                return ToolResult.success(combined, metadata: ["exit_code": "\(exitCode)"])
            } else {
                return ToolResult.failure(combined, metadata: ["exit_code": "\(exitCode)"])
            }
        #endif
    }

    private func containsInvalidShellToken(_ command: String) -> Bool {
        command.range(of: #";\s*&"#, options: .regularExpression) != nil
    }

    private func rewriteTmpPaths(in command: String, tmpPath: String) -> (String, Bool) {
        let pattern = #"(^|[\s"\'=])/tmp(?=(/|\s|$))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (command, false)
        }
        let range = NSRange(command.startIndex..., in: command)
        let template = "$1" + NSRegularExpression.escapedTemplate(for: tmpPath)
        let updated = regex.stringByReplacingMatches(
            in: command, options: [], range: range, withTemplate: template)
        return (updated, updated != command)
    }
}
