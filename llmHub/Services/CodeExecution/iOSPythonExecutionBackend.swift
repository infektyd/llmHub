//
//  iOSPythonExecutionBackend.swift
//  llmHub
//
//  Native Python execution backend for iOS using embedded Python.xcframework
//

import Foundation
import OSLog

#if os(iOS)
import Python

/// iOS backend that executes Python code in-process via the Python C API.
final class iOSPythonExecutionBackend: ExecutionBackend, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.llmhub", category: "iOSPythonExecutionBackend")
    private let initQueue = DispatchQueue(label: "com.llmhub.python.init")
    private let executionQueue = DispatchQueue(label: "com.llmhub.python.execute")
    private var isPythonInitialized = false
    private var pythonHomeWString: UnsafeMutablePointer<wchar_t>?

    // MARK: - ExecutionBackend

    var isAvailable: Bool {
        get async {
            await withCheckedContinuation { continuation in
                executionQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }
                    self.ensurePythonInitialized()
                    continuation.resume(returning: self.isPythonInitialized)
                }
            }
        }
    }

    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        guard language == .python else {
            throw CodeExecutionError.interpreterNotFound(language)
        }

        let startTime = Date()
        let timeoutSeconds = clampTimeout(timeout)

        let output = try await withTimeout(seconds: timeoutSeconds) { [weak self] in
            guard let self else {
                throw CodeExecutionError.executionCancelled
            }
            return try await self.runOnExecutionQueue {
                self.ensurePythonInitialized()
                guard self.isPythonInitialized else {
                    throw CodeExecutionError.processLaunchFailed("Python runtime is not available.")
                }
                return try self.executePythonCode(code, workingDirectory: workingDirectory)
            }
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

    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        guard language == .python else {
            return InterpreterInfo.unavailable(language)
        }

        return await withCheckedContinuation { continuation in
            executionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: InterpreterInfo.unavailable(language))
                    return
                }
                guard self.isPythonFrameworkAvailable() else {
                    continuation.resume(returning: InterpreterInfo.unavailable(language))
                    return
                }
                self.ensurePythonInitialized()
                guard self.isPythonInitialized else {
                    continuation.resume(returning: InterpreterInfo.unavailable(language))
                    return
                }

                let version = self.readPythonVersion()
                let path = self.pythonFrameworkPath() ?? "Python.framework"
                continuation.resume(
                    returning: InterpreterInfo(
                        language: language,
                        path: path,
                        version: version,
                        isAvailable: true
                    )
                )
            }
        }
    }

    func checkAllInterpreters() async -> [InterpreterInfo] {
        var results: [InterpreterInfo] = []
        for language in SupportedLanguage.allCases {
            let info = await checkInterpreter(for: language)
            results.append(info)
        }
        return results
    }

    // MARK: - Initialization

    private func ensurePythonInitialized() {
        initQueue.sync {
            guard !isPythonInitialized else { return }
            guard isPythonFrameworkAvailable() else { return }

            let pythonHome = resolvePythonHome()
            if let pythonHome {
                setPythonHome(pythonHome)
            }

            Py_Initialize()
            isPythonInitialized = Py_IsInitialized() != 0

            if isPythonInitialized {
                configurePythonEnvironment(pythonHome: pythonHome)
            } else {
                logger.error("Python runtime failed to initialize")
            }
        }
    }

    private func setPythonHome(_ url: URL) {
        guard pythonHomeWString == nil else { return }
        let path = url.path
        path.withCString { cString in
            pythonHomeWString = Py_DecodeLocale(cString, nil)
        }
        if let pythonHomeWString {
            Py_SetPythonHome(pythonHomeWString)
        }
    }

    private func configurePythonEnvironment(pythonHome: URL?) {
        let gstate = PyGILState_Ensure()
        defer { PyGILState_Release(gstate) }

        PyRun_SimpleString("import sys; sys.dont_write_bytecode = True")

        if let pythonHome {
            let stdlibPath = pythonHome.appendingPathComponent("lib/python3.14")
            let sitePackagesPath = stdlibPath.appendingPathComponent("site-packages")
            _ = addSysPathIfNeeded(stdlibPath.path)
            _ = addSysPathIfNeeded(sitePackagesPath.path)
        }

        if let resources = Bundle.main.resourceURL {
            let appPackages = resources.appendingPathComponent("app_packages")
            _ = addSysPathIfNeeded(appPackages.path)
        }

        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            _ = addSysPathIfNeeded(documents.path)
        }
    }

    private func resolvePythonHome() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("python"),
            Bundle.main.resourceURL?.appendingPathComponent("Python"),
            Bundle.main.resourceURL?.appendingPathComponent("Python.framework/Resources"),
            Bundle.main.privateFrameworksURL?.appendingPathComponent("Python.framework/Resources"),
            Bundle.main.bundleURL.appendingPathComponent("Frameworks/Python.framework/Resources"),
            Bundle.main.bundleURL.appendingPathComponent("Frameworks"),
            Bundle.main.privateFrameworksURL
        ].compactMap { $0 }

        for candidate in candidates {
            let stdlib = candidate.appendingPathComponent("lib/python3.14")
            if fileManager.fileExists(atPath: stdlib.path) {
                return candidate
            }
        }

        return nil
    }

    private func pythonFrameworkPath() -> String? {
        let fileManager = FileManager.default
        if let frameworksURL = Bundle.main.privateFrameworksURL {
            let path = frameworksURL.appendingPathComponent("Python.framework")
            if fileManager.fileExists(atPath: path.path) {
                return path.path
            }
        }

        let fallback = Bundle.main.bundleURL.appendingPathComponent("Frameworks/Python.framework")
        if fileManager.fileExists(atPath: fallback.path) {
            return fallback.path
        }

        return nil
    }

    private func isPythonFrameworkAvailable() -> Bool {
        pythonFrameworkPath() != nil
    }

    private func readPythonVersion() -> String? {
        let gstate = PyGILState_Ensure()
        defer { PyGILState_Release(gstate) }

        let versionCString = Py_GetVersion()
        return String(cString: versionCString)
    }

    // MARK: - Execution

    private func executePythonCode(
        _ code: String,
        workingDirectory: URL?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard Py_IsInitialized() != 0 else {
            throw CodeExecutionError.processLaunchFailed("Python runtime is not initialized.")
        }

        let gstate = PyGILState_Ensure()
        defer { PyGILState_Release(gstate) }

        guard let sysModule = PyImport_ImportModule("sys"),
              let ioModule = PyImport_ImportModule("io") else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to import Python modules.")
        }
        defer {
            Py_XDECREF(sysModule)
            Py_XDECREF(ioModule)
        }

        guard let stringIOClass = PyObject_GetAttrString(ioModule, "StringIO"),
              PyCallable_Check(stringIOClass) != 0 else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to load io.StringIO.")
        }
        defer { Py_XDECREF(stringIOClass) }

        guard let stdoutIO = PyObject_CallObject(stringIOClass, nil),
              let stderrIO = PyObject_CallObject(stringIOClass, nil) else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to create stdout/stderr buffers.")
        }
        defer {
            Py_XDECREF(stdoutIO)
            Py_XDECREF(stderrIO)
        }

        let originalStdout = PyObject_GetAttrString(sysModule, "stdout")
        let originalStderr = PyObject_GetAttrString(sysModule, "stderr")
        defer {
            if let originalStdout {
                PyObject_SetAttrString(sysModule, "stdout", originalStdout)
                Py_XDECREF(originalStdout)
            }
            if let originalStderr {
                PyObject_SetAttrString(sysModule, "stderr", originalStderr)
                Py_XDECREF(originalStderr)
            }
        }

        guard PyObject_SetAttrString(sysModule, "stdout", stdoutIO) == 0,
              PyObject_SetAttrString(sysModule, "stderr", stderrIO) == 0 else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to redirect stdout/stderr.")
        }

        let didInsertWorkingDirectory = workingDirectory.map { addSysPathIfNeeded($0.path) } ?? false
        defer {
            if didInsertWorkingDirectory, let workingDirectory {
                removeSysPath(workingDirectory.path)
            }
        }

        let previousWorkingDirectory = try setWorkingDirectory(workingDirectory)
        defer {
            if let previousWorkingDirectory {
                try? setWorkingDirectory(URL(fileURLWithPath: previousWorkingDirectory))
            }
        }

        let globals = PyDict_New()
        guard let globals else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to create Python execution context.")
        }
        PyDict_SetItemString(globals, "__builtins__", PyEval_GetBuiltins())
        if let mainName = PyUnicode_FromString("__main__") {
            PyDict_SetItemString(globals, "__name__", mainName)
            Py_XDECREF(mainName)
        }

        defer {
            Py_XDECREF(globals)
        }

        let result = code.withCString { cString in
            PyRun_StringFlags(cString, Int32(Py_file_input), globals, globals, nil)
        }

        var exitCode: Int32 = 0
        if let result {
            Py_DECREF(result)
        } else {
            exitCode = 1
            PyErr_Print()
        }

        let stdout = captureString(from: stdoutIO)
        let stderr = captureString(from: stderrIO)

        return (stdout: stdout, stderr: stderr, exitCode: exitCode)
    }

    private func setWorkingDirectory(_ workingDirectory: URL?) throws -> String? {
        guard let workingDirectory else { return nil }

        guard let osModule = PyImport_ImportModule("os") else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to import os module.")
        }
        defer { Py_XDECREF(osModule) }

        let currentDirObject = PyObject_CallMethod(osModule, "getcwd", "")
        let currentDir = pythonString(from: currentDirObject)
        Py_XDECREF(currentDirObject)

        let didChange: Int32 = workingDirectory.path.withCString { cString in
            let result = PyObject_CallMethod(osModule, "chdir", "s", cString)
            if let result {
                Py_XDECREF(result)
                return 0
            }
            return 1
        }
        if didChange != 0 {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to change working directory.")
        }

        return currentDir.isEmpty ? nil : currentDir
    }

    private func captureString(from object: UnsafeMutablePointer<PyObject>?) -> String {
        guard let object else { return "" }
        guard let value = PyObject_CallMethod(object, "getvalue", "") else {
            PyErr_Clear()
            return ""
        }
        defer { Py_XDECREF(value) }
        return pythonString(from: value)
    }

    private func pythonString(from object: UnsafeMutablePointer<PyObject>?) -> String {
        guard let object, let cString = PyUnicode_AsUTF8(object) else {
            PyErr_Clear()
            return ""
        }
        return String(cString: cString)
    }

    @discardableResult
    private func addSysPathIfNeeded(_ path: String) -> Bool {
        guard let sysModule = PyImport_ImportModule("sys") else {
            PyErr_Clear()
            return false
        }
        defer { Py_XDECREF(sysModule) }

        guard let sysPath = PyObject_GetAttrString(sysModule, "path") else {
            PyErr_Clear()
            return false
        }
        defer { Py_XDECREF(sysPath) }

        guard let pyPath = PyUnicode_FromString(path) else {
            PyErr_Clear()
            return false
        }
        defer { Py_XDECREF(pyPath) }

        let contains = PySequence_Contains(sysPath, pyPath)
        if contains == 0 {
            _ = PyList_Insert(sysPath, 0, pyPath)
            return true
        }
        return false
    }

    private func removeSysPath(_ path: String) {
        guard let sysModule = PyImport_ImportModule("sys") else {
            PyErr_Clear()
            return
        }
        defer { Py_XDECREF(sysModule) }

        guard let sysPath = PyObject_GetAttrString(sysModule, "path") else {
            PyErr_Clear()
            return
        }
        defer { Py_XDECREF(sysPath) }

        guard let pyPath = PyUnicode_FromString(path) else {
            PyErr_Clear()
            return
        }
        defer { Py_XDECREF(pyPath) }

        let index = PySequence_Index(sysPath, pyPath)
        if index >= 0 {
            _ = PySequence_DelItem(sysPath, index)
        } else {
            PyErr_Clear()
        }
    }

    // MARK: - Helpers

    private func runOnExecutionQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw CodeExecutionError.timeout(seconds: seconds)
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw CodeExecutionError.processLaunchFailed("Execution failed without result.")
            }

            group.cancelAll()
            return result
        }
    }

    private func clampTimeout(_ timeout: Int) -> Int {
        min(max(timeout, 5), 30)
    }
}

#else

/// Stub to keep macOS tests compiling without iOS Python runtime.
final class iOSPythonExecutionBackend: ExecutionBackend {
    var isAvailable: Bool {
        get async { false }
    }

    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        throw CodeExecutionError.processLaunchFailed(
            "Python execution backend is only available on iOS."
        )
    }

    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        InterpreterInfo.unavailable(language)
    }

    func checkAllInterpreters() async -> [InterpreterInfo] {
        SupportedLanguage.allCases.map { InterpreterInfo.unavailable($0) }
    }
}

#endif
