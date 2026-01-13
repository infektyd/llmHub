import Foundation
import JavaScriptCore
@preconcurrency import Dispatch

#if os(iOS)

final class iOSJavaScriptExecutionBackend: ExecutionBackend, @unchecked Sendable {
    private final class OutputCapture: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var _stdout: String = ""
        nonisolated(unsafe) private var _stderr: String = ""

        nonisolated var stdout: String {
            lock.lock()
            defer { lock.unlock() }
            return _stdout
        }

        nonisolated var stderr: String {
            lock.lock()
            defer { lock.unlock() }
            return _stderr
        }

        nonisolated func appendStdout(_ message: String) {
            lock.lock()
            if !_stdout.isEmpty { _stdout += "\n" }
            _stdout += message
            lock.unlock()
        }

        nonisolated func appendStderr(_ message: String) {
            lock.lock()
            if !_stderr.isEmpty { _stderr += "\n" }
            _stderr += message
            lock.unlock()
        }
    }

    private final class ExecutionCompletionState: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var finished = false

        nonisolated func tryFinish() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return false }
            finished = true
            return true
        }

        nonisolated func isFinished() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished
        }
    }

    private final class ExecutionContinuationBox<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var continuation: CheckedContinuation<T, Error>?
        nonisolated(unsafe) private var pendingError: Error?
        nonisolated(unsafe) private var shouldClearContinuation = false

        nonisolated func set(_ continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            self.continuation = continuation
            let error = pendingError
            pendingError = nil
            if error != nil {
                self.continuation = nil
            }
            lock.unlock()

            if let error {
                continuation.resume(throwing: error)
            }
        }

        nonisolated func resume(throwing error: Error) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            if continuation == nil {
                pendingError = error
            }
            lock.unlock()

            continuation?.resume(throwing: error)
        }

        nonisolated func resume(returning value: T) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            lock.unlock()

            continuation?.resume(returning: value)
        }

        nonisolated func clearContinuation() {
            lock.lock()
            if continuation == nil {
                shouldClearContinuation = true
            } else {
                continuation = nil
            }
            lock.unlock()
        }

        nonisolated func clearContinuationIfRequested() {
            lock.lock()
            let shouldClear = shouldClearContinuation
            shouldClearContinuation = false
            if shouldClear {
                continuation = nil
            }
            lock.unlock()
        }
    }

    private let executionQueue = DispatchQueue(label: "com.llmhub.javascript.execute", attributes: .concurrent)
    private let timeoutQueue = DispatchQueue(label: "com.llmhub.javascript.timeout")

    nonisolated var isAvailable: Bool {
        get async { true }
    }

    nonisolated func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        guard language == .javascript else {
            throw CodeExecutionError.processLaunchFailed(
                "Only JavaScript is supported for code execution on iOS. Python/Swift/TypeScript/Dart require macOS."
            )
        }

        let startTime = Date()
        let timeoutSeconds = max(1, timeout)

        let output = try await withTaskCancellationHandler {
            try await runOnExecutionQueueWithTimeout(seconds: timeoutSeconds) {
                try self.executeJavaScriptCode(code, workingDirectory: workingDirectory)
            }
        } onCancel: {
        }

        let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return CodeExecutionResult(
            id: UUID(),
            language: language,
            code: code,
            stdout: output.stdout,
            stderr: output.stderr,
            exitCode: output.exitCode,
            executionTimeMs: executionTimeMs,
            timestamp: Date(),
            sandboxPath: nil
        )
    }

    nonisolated func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        guard language == .javascript else {
            return InterpreterInfo.unavailable(language)
        }

        return InterpreterInfo(
            language: language,
            path: "JavaScriptCore",
            version: nil,
            isAvailable: true
        )
    }

    nonisolated func checkAllInterpreters() async -> [InterpreterInfo] {
        SupportedLanguage.allCases.map { language in
            if language == .javascript {
                return InterpreterInfo(language: language, path: "JavaScriptCore", version: nil, isAvailable: true)
            }
            return InterpreterInfo.unavailable(language)
        }
    }

    nonisolated private func runOnExecutionQueueWithTimeout<T: Sendable>(
        seconds: Int,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let state = ExecutionCompletionState()
        let box = ExecutionContinuationBox<T>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.set(continuation)

                if state.isFinished() {
                    return
                }

                if Task.isCancelled, state.tryFinish() {
                    box.resume(throwing: CodeExecutionError.executionCancelled)
                    return
                }

                let timeoutItem = DispatchWorkItem { [weak box] in
                    guard let box else { return }
                    guard state.tryFinish() else { return }
                    box.resume(throwing: CodeExecutionError.timeout(seconds: seconds))
                }

                timeoutQueue.asyncAfter(deadline: .now() + .seconds(seconds), execute: timeoutItem)

                executionQueue.async {
                    guard !state.isFinished() else {
                        return
                    }

                    do {
                        let value = try work()
                        guard state.tryFinish() else { return }
                        box.resume(returning: value)
                    } catch {
                        guard state.tryFinish() else { return }
                        box.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            if state.tryFinish() {
                box.resume(throwing: CodeExecutionError.executionCancelled)
            }
        }
    }

    nonisolated private func executeJavaScriptCode(
        _ code: String,
        workingDirectory: URL?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        _ = workingDirectory
        let output = OutputCapture()

        let context = JSContext()
        guard let context else {
            throw CodeExecutionError.processLaunchFailed("Failed to create JavaScript execution context")
        }

        installPolyfills(in: context, output: output)

        var didThrow = false

        context.exceptionHandler = { _, exception in
            guard let exception else { return }
            didThrow = true

            let message = exception.toString() ?? "Unknown error"
            output.appendStderr(message)

            let stack = exception.objectForKeyedSubscript("stack")
            if let stack, !stack.isUndefined {
                let stackStr = stack.toString() ?? ""
                if !stackStr.isEmpty {
                    output.appendStderr(stackStr)
                }
            }
        }

        let result = context.evaluateScript(code)

        if !didThrow, let result, !result.isUndefined, !result.isNull {
            let resultStr = result.toString() ?? ""
            if !resultStr.isEmpty, resultStr != "undefined" {
                output.appendStdout("→ \(resultStr)")
            }
        }

        let exitCode: Int32 = didThrow ? 1 : 0
        return (stdout: output.stdout, stderr: output.stderr, exitCode: exitCode)
    }

    nonisolated private func installPolyfills(in context: JSContext, output: OutputCapture) {
        let consoleLog: @convention(block) (String) -> Void = { message in
            output.appendStdout(message)
        }

        let consoleError: @convention(block) (String) -> Void = { message in
            output.appendStderr(message)
        }

        context.setObject(consoleLog, forKeyedSubscript: "__llmhub_stdout" as NSString)
        context.setObject(consoleError, forKeyedSubscript: "__llmhub_stderr" as NSString)

        context.evaluateScript(
            """
            var console = {
                log: function(...args) { __llmhub_stdout(args.map(String).join(' ')); },
                error: function(...args) { __llmhub_stderr(args.map(String).join(' ')); },
                warn: function(...args) { __llmhub_stdout('[WARN] ' + args.map(String).join(' ')); }
            };

            function setTimeout() {
                throw new Error('setTimeout is not supported by llmHub iOS JavaScript execution');
            }

            function setInterval() {
                throw new Error('setInterval is not supported by llmHub iOS JavaScript execution');
            }

            function clearTimeout() {}
            function clearInterval() {}
            """
        )
    }
}

#else

final class iOSJavaScriptExecutionBackend: ExecutionBackend {
    var isAvailable: Bool {
        get async { false }
    }

    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        throw CodeExecutionError.processLaunchFailed("JavaScript execution backend is only available on iOS.")
    }

    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        InterpreterInfo.unavailable(language)
    }

    func checkAllInterpreters() async -> [InterpreterInfo] {
        SupportedLanguage.allCases.map { InterpreterInfo.unavailable($0) }
    }
}

#endif
