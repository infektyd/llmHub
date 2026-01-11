//
//  IOSLocalExecutionBackend.swift
//  llmHub
//
//  Local in-app execution backend for iOS/iPadOS.
//

#if os(iOS)

import Foundation
@preconcurrency import JavaScriptCore

// MARK: - Backend

struct IOSLocalExecutionBackend: ExecutionBackend {

    private let jsExecutor = JavaScriptSandboxExecutor()
    private let pythonExecutor = PythonSandboxExecutor()

    var isAvailable: Bool {
        get async { true }
    }

    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        let startedAt = Date()
        let execID = UUID()

        // Enforce per-execution sandbox directory for all iOS-local execution.
        guard let workingDirectory else {
            throw CodeExecutionError.sandboxCreationFailed("Missing sandbox working directory")
        }

        switch language {
        case .javascript:
            let (stdout, stderr, exitCode) = try await jsExecutor.execute(
                code: code,
                timeoutSeconds: timeout,
                workingDirectory: workingDirectory
            )

            return CodeExecutionResult(
                id: execID,
                language: language,
                code: code,
                stdout: stdout,
                stderr: stderr,
                exitCode: exitCode,
                executionTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                timestamp: Date(),
                sandboxPath: workingDirectory.path
            )

        case .python:
            let (stdout, stderr, exitCode) = try await pythonExecutor.execute(
                code: code,
                timeoutSeconds: timeout,
                workingDirectory: workingDirectory
            )

            return CodeExecutionResult(
                id: execID,
                language: language,
                code: code,
                stdout: stdout,
                stderr: stderr,
                exitCode: exitCode,
                executionTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                timestamp: Date(),
                sandboxPath: workingDirectory.path
            )

        case .swift, .typescript, .dart:
            throw CodeExecutionError.interpreterNotFound(language)
        }
    }

    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        switch language {
        case .javascript:
            return InterpreterInfo(language: language, path: "JavaScriptCore", version: nil, isAvailable: true)
        case .python:
            let ok = await pythonExecutor.isPythonAvailable
            return InterpreterInfo(
                language: language,
                path: ok ? "Embedded CPython" : "",
                version: ok ? "3.14" : nil,
                isAvailable: ok
            )
        case .swift, .typescript, .dart:
            return InterpreterInfo.unavailable(language)
        }
    }

    func checkAllInterpreters() async -> [InterpreterInfo] {
        await SupportedLanguage.allCases.asyncMap { lang in
            await checkInterpreter(for: lang)
        }
    }
}

// MARK: - JavaScript

actor JavaScriptSandboxExecutor {

    func execute(
        code: String,
        timeoutSeconds: Int,
        workingDirectory: URL
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withTimeout(seconds: timeoutSeconds) {
            try await MainActor.run {
                try self.executeOnMain(code: code, workingDirectory: workingDirectory)
            }
        }
    }

    @MainActor
    private func executeOnMain(
        code: String,
        workingDirectory: URL
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let stdoutCollector = OutputCollector()
        var stderr = ""

        guard let ctx = JSContext() else {
            throw CodeExecutionError.processLaunchFailed("Failed to create JSContext")
        }

        ctx.exceptionHandler = { _, exception in
            stderr = exception?.toString() ?? "Unknown JavaScript error"
        }

        let log: @convention(block) (JSValue) -> Void = { value in
            stdoutCollector.append(value.toString())
        }

        ctx.setObject(
            unsafeBitCast(log, to: AnyObject.self),
            forKeyedSubscript: "_llmhub_log" as NSString
        )

        ctx.evaluateScript("var console = { log: function(...args) { _llmhub_log(args.map(a => String(a)).join(' ')); } };")

        injectFileSystem(ctx: ctx, workingDirectory: workingDirectory)

        let result = ctx.evaluateScript(code)

        if !stderr.isEmpty {
            return (stdoutCollector.stringValue, stderr, 1)
        }

        if let result, !result.isUndefined, !result.isNull {
            stdoutCollector.append(result.toString())
        }

        return (stdoutCollector.stringValue, "", 0)
    }

    @MainActor
    private func injectFileSystem(ctx: JSContext, workingDirectory: URL) {
        let readFile: @convention(block) (String) -> String? = { relativePath in
            guard let safeURL = Self.safeSandboxURL(base: workingDirectory, relativePath: relativePath) else {
                return nil
            }
            return try? String(contentsOf: safeURL, encoding: .utf8)
        }

        let writeFile: @convention(block) (String, String) -> Bool = { relativePath, content in
            guard let safeURL = Self.safeSandboxURL(base: workingDirectory, relativePath: relativePath) else {
                return false
            }
            do {
                let parent = safeURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try content.write(to: safeURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }

        ctx.evaluateScript("var fs = {};")
        let fs = ctx.objectForKeyedSubscript("fs")
        fs?.setObject(unsafeBitCast(readFile, to: AnyObject.self), forKeyedSubscript: "readFile" as NSString)
        fs?.setObject(unsafeBitCast(writeFile, to: AnyObject.self), forKeyedSubscript: "writeFile" as NSString)
    }

    private static func safeSandboxURL(base: URL, relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("/") else { return nil }
        guard !trimmed.hasPrefix("~") else { return nil }

        let candidate = base.appendingPathComponent(trimmed)
        let standardizedCandidate = candidate.standardizedFileURL
        let standardizedBase = base.standardizedFileURL

        let basePath = standardizedBase.path.hasSuffix("/") ? standardizedBase.path : standardizedBase.path + "/"
        guard standardizedCandidate.path.hasPrefix(basePath) else { return nil }

        return standardizedCandidate
    }

    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw CodeExecutionError.timeout(seconds: seconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Python

actor PythonSandboxExecutor {

    private var initialized = false

    var isPythonAvailable: Bool {
        get async {
            if initialized { return true }
            return await initializeIfNeeded()
        }
    }

    func execute(
        code: String,
        timeoutSeconds: Int,
        workingDirectory: URL
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard await initializeIfNeeded() else {
            throw CodeExecutionError.interpreterNotFound(.python)
        }

        return try await withTimeout(seconds: timeoutSeconds) {
            let escapedUserCode = Self.pythonTripleQuoted(code)
            let escapedCwd = Self.pythonStringLiteral(workingDirectory.path)

            let wrapper = """
import os
os.chdir(\(escapedCwd))
__code = \(escapedUserCode)
exec(compile(__code, '<llmhub>', 'exec'), {})
"""

            guard let captured = CPythonBridge.runAndCapture(wrapper) else {
                return ("", "Python bridge not available", 1)
            }

            return (captured.stdout, captured.stderr, captured.exitCode)
        }
    }

    private func initializeIfNeeded() async -> Bool {
        if initialized { return true }

        // Confirm Python.framework is embedded.
        guard let pythonFrameworkURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("Python.framework"),
              FileManager.default.fileExists(atPath: pythonFrameworkURL.path)
        else {
            return false
        }

        // BeeWare install script copies stdlib into <App>/python/lib/python3.14.
        let pythonHomeURL = Bundle.main.bundleURL.appendingPathComponent("python", isDirectory: true)
        let stdlibURL = pythonHomeURL
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("python3.14", isDirectory: true)
        let sitePackagesURL = stdlibURL.appendingPathComponent("site-packages", isDirectory: true)

        let pythonHome = pythonHomeURL.path
        let pythonPath = [stdlibURL.path, sitePackagesURL.path].joined(separator: ":")

        let ok = CPythonBridge.initialize(pythonHome: pythonHome, pythonPath: pythonPath)
        if ok {
            // Headless plotting backend.
            _ = CPythonBridge.runSimpleString("import os\nos.environ.setdefault('MPLBACKEND','Agg')\n")
            initialized = true
        }

        return ok
    }

    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw CodeExecutionError.timeout(seconds: seconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func pythonStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "\"", with: "\\\\\"")
            .replacingOccurrences(of: "\n", with: "\\\\n")
        return "\"\(escaped)\""
    }

    private static func pythonTripleQuoted(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "\"\"\"", with: "\\\\\"\\\\\"\\\\\"")
        return "\"\"\"\(escaped)\"\"\""
    }
}

// MARK: - Helpers

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func append(_ s: String) {
        lock.lock()
        items.append(s)
        lock.unlock()
    }

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return items.joined(separator: "\n")
    }
}

private extension Array {
    func asyncMap<T>(_ transform: @escaping (Element) async -> T) async -> [T] {
        var out: [T] = []
        out.reserveCapacity(count)
        for e in self {
            out.append(await transform(e))
        }
        return out
    }
}

#endif
