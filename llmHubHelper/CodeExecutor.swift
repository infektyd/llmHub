//
//  CodeExecutor.swift
//  llmHubHelper
//
//  Core code execution logic running outside the sandbox
//  Handles interpreter discovery and process management
//

import Foundation
import OSLog

/// Executes code in various languages using system interpreters
/// Runs in the XPC helper process, outside the app sandbox
actor CodeExecutor {
    
    private let logger = Logger(subsystem: "Syntra.llmHub.CodeExecutionHelper", category: "Executor")
    private let tempDirectory: URL
    private var interpreterCache: [String: (path: String, version: String?)] = [:]
    
    init() {
        // Use system temp directory for code files
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmHub-helper", isDirectory: true)
        
        // Ensure temp directory exists
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    // MARK: - Execution
    
    /// Execute code and return the result
    func execute(
        code: String,
        language: String,
        timeout: Int,
        workingDirectory: String?
    ) async throws -> XPCExecutionResult {
        let startTime = Date()
        let executionID = UUID().uuidString
        
        // Find interpreter
        let (interpreterPathOpt, _) = await findInterpreter(for: language)
        guard let interpreterPath = interpreterPathOpt, !interpreterPath.isEmpty else {
            throw XPCExecutionError.interpreterNotFound(language)
        }
        
        // Create execution directory
        let execDir = tempDirectory.appendingPathComponent(executionID, isDirectory: true)
        try FileManager.default.createDirectory(at: execDir, withIntermediateDirectories: true)
        
        defer {
            // Cleanup execution directory after a delay
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                try? FileManager.default.removeItem(at: execDir)
            }
        }
        
        // Write code file
        let fileExtension = Self.fileExtension(for: language)
        let codeFile = execDir.appendingPathComponent("main\(fileExtension)")
        
        do {
            try code.write(to: codeFile, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codeFile.path)
        } catch {
            throw XPCExecutionError.fileWriteFailed(error.localizedDescription)
        }
        
        // Execute
        let (stdout, stderr, exitCode) = try await runProcess(
            interpreterPath: interpreterPath,
            codeFile: codeFile,
            language: language,
            workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) } ?? execDir,
            timeout: timeout
        )
        
        let executionTime = Int(Date().timeIntervalSince(startTime) * 1000)
        
        return XPCExecutionResult(
            id: executionID,
            language: language,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            executionTimeMs: executionTime,
            interpreterPath: interpreterPath
        )
    }
    
    // MARK: - Interpreter Discovery
    
    /// Find the interpreter path and version for a language
    func findInterpreter(for language: String) async -> (path: String?, version: String?) {
        // Check cache
        if let cached = interpreterCache[language] {
            return cached
        }
        
        let commands = interpreterCommands(for: language)
        
        for command in commands {
            if let path = await which(command) {
                let version = await getVersion(path: path, language: language)
                interpreterCache[language] = (path, version)
                return (path, version)
            }
        }
        
        return (nil, nil)
    }
    
    /// Get possible interpreter commands for a language
    private func interpreterCommands(for language: String) -> [String] {
        switch language {
        case "swift":
            return ["swift"]
        case "python":
            return ["python3", "python"]
        case "typescript":
            return ["ts-node", "npx"]
        case "javascript":
            return ["node", "nodejs"]
        case "dart":
            return ["dart"]
        default:
            return []
        }
    }
    
    /// Get file extension for a language
    private static func fileExtension(for language: String) -> String {
        switch language {
        case "swift": return ".swift"
        case "python": return ".py"
        case "typescript": return ".ts"
        case "javascript": return ".js"
        case "dart": return ".dart"
        default: return ".txt"
        }
    }
    
    /// Run `which` to find binary path
    private func which(_ command: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return path?.isEmpty == false ? path : nil
            }
        } catch {
            logger.debug("which \(command) failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Get interpreter version
    private func getVersion(path: String, language: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    // MARK: - Process Execution
    
    private func runProcess(
        interpreterPath: String,
        codeFile: URL,
        language: String,
        workingDirectory: URL,
        timeout: Int
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        
        let process = Process()
        
        // Configure based on language
        switch language {
        case "swift":
            process.executableURL = URL(fileURLWithPath: interpreterPath)
            process.arguments = [codeFile.path]
            
        case "python":
            process.executableURL = URL(fileURLWithPath: interpreterPath)
            process.arguments = ["-u", codeFile.path]
            
        case "typescript":
            if interpreterPath.hasSuffix("npx") {
                process.executableURL = URL(fileURLWithPath: interpreterPath)
                process.arguments = ["--yes", "ts-node", codeFile.path]
            } else {
                process.executableURL = URL(fileURLWithPath: interpreterPath)
                process.arguments = [codeFile.path]
            }
            
        case "javascript":
            process.executableURL = URL(fileURLWithPath: interpreterPath)
            process.arguments = [codeFile.path]
            
        case "dart":
            process.executableURL = URL(fileURLWithPath: interpreterPath)
            process.arguments = ["run", codeFile.path]
            
        default:
            throw XPCExecutionError.invalidLanguage(language)
        }
        
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment
        
        // Setup pipes
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Launch process
        do {
            try process.run()
        } catch {
            throw XPCExecutionError.processLaunchFailed(error.localizedDescription)
        }
        
        // Handle timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                process.terminate()
                logger.warning("Process terminated due to timeout")
            }
        }
        
        // Wait for completion
        process.waitUntilExit()
        timeoutTask.cancel()
        
        // Read output
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        // Check if timed out
        if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGTERM {
            throw XPCExecutionError.timeout(timeout)
        }
        
        return (stdout, stderr, process.terminationStatus)
    }
}

