//
//  iOSPythonExecutionBackend.swift
//  llmHub
//
//  Native Python execution backend for iOS using embedded Python.xcframework
//

import Foundation
import OSLog

#if os(iOS) && canImport(Python)
import Python

/// iOS backend that executes Python code in-process via the Python C API.
final class iOSPythonExecutionBackend: ExecutionBackend, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.llmhub", category: "iOSPythonExecutionBackend")
    private let initQueue = DispatchQueue(label: "com.llmhub.python.init")
    private let executionQueue = DispatchQueue(label: "com.llmhub.python.execute")
    nonisolated(unsafe) private var isPythonInitialized = false

    // MARK: - ExecutionBackend

    nonisolated var isAvailable: Bool {
        get async {
            print("\n🔍 [iOSBackend] ========== isAvailable CHECK ==========")
            
            let result = await withCheckedContinuation { continuation in
                executionQueue.async { [weak self] in
                    print("🔍 [iOSBackend] On executionQueue thread")
                    
                    guard let self else {
                        print("❌ [iOSBackend] self is nil")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    // Check if Python.framework is available
                    if self.isPythonInitialized {
                        print("✅ [iOSBackend] Python already initialized")
                        continuation.resume(returning: true)
                        return
                    }
                    
                    print("🔍 [iOSBackend] Python not initialized, attempting init...")
                    
                    // Try to initialize Python
                    do {
                        try self.ensurePythonInitialized()
                    } catch {
                        print("❌ [iOSBackend] Python initialization error: \(error)")
                    }
                    
                    if self.isPythonInitialized {
                        print("✅ [iOSBackend] Python initialized successfully")
                        continuation.resume(returning: true)
                    } else {
                        print("❌ [iOSBackend] Python initialization failed")
                        continuation.resume(returning: false)
                    }
                }
            }
            
            print("🔍 [iOSBackend] isAvailable result: \(result)")
            print("🔍 [iOSBackend] ========================================\n")
            return result
        }
    }

    nonisolated func execute(
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
                try self.ensurePythonInitialized()
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

    nonisolated func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
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
                _ = try? self.ensurePythonInitialized()
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

    nonisolated func checkAllInterpreters() async -> [InterpreterInfo] {
        var results: [InterpreterInfo] = []
        for language in SupportedLanguage.allCases {
            let info = await checkInterpreter(for: language)
            results.append(info)
        }
        return results
    }

    // MARK: - Initialization

    nonisolated private func ensurePythonInitialized() throws {
        var thrownError: Error?

        initQueue.sync {
            do {
                try ensurePythonInitializedSync()
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
    }

    nonisolated private func ensurePythonInitializedSync() throws {
        print("\n🔍 [iOSBackend.init] ========== PYTHON INITIALIZATION ==========")
        defer {
            print("🔍 [iOSBackend.init] ============================================\n")
        }

        guard !isPythonInitialized else {
            print("✅ [iOSBackend.init] Already initialized, skipping")
            return
        }

        guard let frameworksPath = Bundle.main.privateFrameworksPath else {
            throw CodeExecutionError.processLaunchFailed("Cannot locate Frameworks directory")
        }

        print("✅ [iOSBackend.init] Frameworks path: \(frameworksPath)")

        let pythonFramework = (frameworksPath as NSString)
            .appendingPathComponent("Python.framework")
        let pythonStdlib = (pythonFramework as NSString)
            .appendingPathComponent("lib/python3.14")
        let pythonSitePackages = (pythonStdlib as NSString)
            .appendingPathComponent("site-packages")
        let pythonLibDynload = (pythonStdlib as NSString)
            .appendingPathComponent("lib-dynload")

        print("🔍 [iOSBackend.init] Python.framework: \(pythonFramework)")
        print("🔍 [iOSBackend.init] Python stdlib: \(pythonStdlib)")
        print("🔍 [iOSBackend.init] Python site-packages: \(pythonSitePackages)")
        print("🔍 [iOSBackend.init] Python lib-dynload: \(pythonLibDynload)")

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pythonFramework, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodeExecutionError.processLaunchFailed("Python.framework not found at expected path")
        }

        isDirectory = false
        guard FileManager.default.fileExists(atPath: pythonStdlib, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodeExecutionError.processLaunchFailed("Python standard library not accessible")
        }

        isDirectory = false
        guard FileManager.default.fileExists(atPath: pythonSitePackages, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodeExecutionError.processLaunchFailed("Python standard library not accessible")
        }

        let hasLibDynload: Bool = {
            var dynloadIsDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: pythonLibDynload, isDirectory: &dynloadIsDirectory) && dynloadIsDirectory.boolValue
        }()

        print("✅ [iOSBackend.init] Framework paths verified")

        var config = PyConfig()
        PyConfig_InitPythonConfig(&config)
        defer { PyConfig_Clear(&config) }

        let setHomeStatus: PyStatus = pythonFramework.withCString { cString in
            var homePointer = config.home
            let status = PyConfig_SetBytesString(&config, &homePointer, cString)
            config.home = homePointer
            return status
        }
        guard PyStatus_Exception(setHomeStatus) == 0 else {
            throw CodeExecutionError.processLaunchFailed("Failed to set PYTHONHOME")
        }
        print("✅ [iOSBackend.init] PYTHONHOME set to: \(pythonFramework)")

        config.module_search_paths_set = 1

        func appendModuleSearchPath(_ path: String) throws {
            var appendStatus: PyStatus?
            path.withCString { cString in
                guard let wideString = Py_DecodeLocale(cString, nil) else {
                    return
                }
                defer { PyMem_RawFree(wideString) }
                appendStatus = PyWideStringList_Append(&config.module_search_paths, wideString)
            }
            guard let appendStatus else {
                throw CodeExecutionError.processLaunchFailed("Python initialization failed - stdlib paths may be incorrect")
            }
            guard PyStatus_Exception(appendStatus) == 0 else {
                throw CodeExecutionError.processLaunchFailed("Python initialization failed - stdlib paths may be incorrect")
            }
        }

        try appendModuleSearchPath(pythonStdlib)
        if hasLibDynload {
            try appendModuleSearchPath(pythonLibDynload)
        }
        try appendModuleSearchPath(pythonSitePackages)

        print("✅ [iOSBackend.init] Module search paths configured (\(config.module_search_paths.length) paths)")

        let initStatus = Py_InitializeFromConfig(&config)
        guard PyStatus_Exception(initStatus) == 0 else {
            throw CodeExecutionError.processLaunchFailed("Py_InitializeFromConfig failed")
        }

        let isInitialized = Py_IsInitialized()
        print("✅ [iOSBackend.init] Py_InitializeFromConfig succeeded")
        print("🔍 [iOSBackend.init] Py_IsInitialized() = \(isInitialized)")

        guard isInitialized != 0 else {
            throw CodeExecutionError.processLaunchFailed("Python initialization failed - stdlib paths may be incorrect")
        }

        isPythonInitialized = true

        print("✅ [iOSBackend.init] Python runtime fully initialized")
        print("🔍 [iOSBackend.init] Configuring Python environment...")
        configurePythonEnvironment(pythonHome: URL(fileURLWithPath: pythonFramework))
        print("✅ [iOSBackend.init] Python environment configured")
    }

    nonisolated private func configurePythonEnvironment(pythonHome: URL?) {
        let gstate = PyGILState_Ensure()
        defer { PyGILState_Release(gstate) }

        PyRun_SimpleString("import sys; sys.dont_write_bytecode = True")

        if let pythonHome {
            let stdlibPath = pythonHome.appendingPathComponent("lib/python3.14")
            let sitePackagesPath = stdlibPath.appendingPathComponent("site-packages")
            let dynloadPath = stdlibPath.appendingPathComponent("lib-dynload")
            _ = addSysPathIfNeeded(stdlibPath.path)
            _ = addSysPathIfNeeded(dynloadPath.path)
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

    nonisolated private func pythonFrameworkPath() -> String? {
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

    nonisolated private func isPythonFrameworkAvailable() -> Bool {
        pythonFrameworkPath() != nil
    }

    nonisolated private func readPythonVersion() -> String? {
        let gstate = PyGILState_Ensure()
        defer { PyGILState_Release(gstate) }

        guard let versionCString = Py_GetVersion() else {
            PyErr_Clear()
            return nil
        }
        return String(cString: versionCString)
    }

    /// Build security preamble based on CodeSecurityMode.
    /// This is passed via workingDirectory presence/absence as a signal.
    nonisolated private func buildSecurityPreamble(workingDirectory: URL?) -> String {
        guard let workDir = workingDirectory else {
            return """
            import builtins
            import os

            # UNRESTRICTED MODE: Full iOS sandbox access
            try:
                if hasattr(builtins, "_llmhub_original_open"):
                    builtins.open = builtins._llmhub_original_open
            except Exception:
                pass

            try:
                if hasattr(os, "_llmhub_original_remove"):
                    os.remove = os._llmhub_original_remove
            except Exception:
                pass
            """
        }

        let allowedPath = workDir.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        import builtins
        import os
        from pathlib import Path

        # SANDBOX MODE: Restrict file operations
        _llmhub_allowed_path = "\(allowedPath)"
        _llmhub_allowed_root = Path(_llmhub_allowed_path).resolve()

        if not hasattr(builtins, "_llmhub_original_open"):
            builtins._llmhub_original_open = builtins.open

        if not hasattr(os, "_llmhub_original_remove"):
            os._llmhub_original_remove = os.remove

        def _llmhub_is_allowed(_path) -> bool:
            resolved = Path(os.fspath(_path)).expanduser().resolve()
            if resolved == _llmhub_allowed_root:
                return True
            try:
                resolved.relative_to(_llmhub_allowed_root)
                return True
            except Exception:
                return False

        def _llmhub_safe_open(file, mode='r', *args, **kwargs):
            if not _llmhub_is_allowed(file):
                raise PermissionError(f"Access denied: {file} is outside sandbox")
            return builtins._llmhub_original_open(file, mode, *args, **kwargs)

        def _llmhub_safe_remove(path, *args, **kwargs):
            if not _llmhub_is_allowed(path):
                raise PermissionError(f"Cannot delete: {path}")
            return os._llmhub_original_remove(path, *args, **kwargs)

        builtins.open = _llmhub_safe_open
        os.remove = _llmhub_safe_remove

        # Note: Network access still allowed (needed for API calls, web requests)
        # Note: Approval mode handled by CodeInterpreterTool.approvalHandler
        """
    }

    // MARK: - Execution

    nonisolated private func executePythonCode(
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

        let securityPreamble = buildSecurityPreamble(workingDirectory: workingDirectory)
        let combinedCode: String
        if securityPreamble.isEmpty {
            combinedCode = code
        } else {
            combinedCode = securityPreamble + "\n" + code
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
                _ = try? setWorkingDirectory(URL(fileURLWithPath: previousWorkingDirectory))
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

        let result = combinedCode.withCString { cString in
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

    nonisolated private func setWorkingDirectory(_ workingDirectory: URL?) throws -> String? {
        guard let workingDirectory else { return nil }

        guard let osModule = PyImport_ImportModule("os") else {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to import os module.")
        }
        defer { Py_XDECREF(osModule) }

        let currentDirObject = callNoArgMethod(on: osModule, name: "getcwd")
        let currentDir = pythonString(from: currentDirObject)
        Py_XDECREF(currentDirObject)

        let didChange: Int32 = {
            guard let result = callOneStringArgMethod(on: osModule, name: "chdir", arg: workingDirectory.path) else {
                return 1
            }
            Py_XDECREF(result)
            return 0
        }()
        if didChange != 0 {
            PyErr_Clear()
            throw CodeExecutionError.processLaunchFailed("Failed to change working directory.")
        }

        return currentDir.isEmpty ? nil : currentDir
    }

    nonisolated private func captureString(from object: UnsafeMutablePointer<PyObject>?) -> String {
        guard let object else { return "" }
        guard let value = callNoArgMethod(on: object, name: "getvalue") else {
            PyErr_Clear()
            return ""
        }
        defer { Py_XDECREF(value) }
        return pythonString(from: value)
    }

    nonisolated private func pythonString(from object: UnsafeMutablePointer<PyObject>?) -> String {
        guard let object, let cString = PyUnicode_AsUTF8(object) else {
            PyErr_Clear()
            return ""
        }
        return String(cString: cString)
    }

    @discardableResult
    nonisolated private func addSysPathIfNeeded(_ path: String) -> Bool {
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

    nonisolated private func removeSysPath(_ path: String) {
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

    nonisolated private func runOnExecutionQueue<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
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

    nonisolated private func withTimeout<T: Sendable>(
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

    nonisolated private func clampTimeout(_ timeout: Int) -> Int {
        min(max(timeout, 5), 30)
    }

    nonisolated private func callNoArgMethod(
        on object: UnsafeMutablePointer<PyObject>?,
        name: String
    ) -> UnsafeMutablePointer<PyObject>? {
        guard let object else { return nil }
        guard let method = PyObject_GetAttrString(object, name) else {
            PyErr_Clear()
            return nil
        }
        defer { Py_XDECREF(method) }
        return PyObject_CallObject(method, nil)
    }

    nonisolated private func callOneStringArgMethod(
        on object: UnsafeMutablePointer<PyObject>?,
        name: String,
        arg: String
    ) -> UnsafeMutablePointer<PyObject>? {
        guard let object else { return nil }
        guard let method = PyObject_GetAttrString(object, name) else {
            PyErr_Clear()
            return nil
        }
        defer { Py_XDECREF(method) }

        guard let args = PyTuple_New(1) else {
            PyErr_Clear()
            return nil
        }
        defer { Py_XDECREF(args) }

        guard let pyArg = arg.withCString({ PyUnicode_FromString($0) }) else {
            PyErr_Clear()
            return nil
        }

        // PyTuple_SetItem steals a reference to pyArg on success.
        if PyTuple_SetItem(args, 0, pyArg) != 0 {
            Py_XDECREF(pyArg)
            PyErr_Clear()
            return nil
        }

        return PyObject_CallObject(method, args)
    }
}

#else

/// Stub to keep macOS tests compiling without iOS Python runtime.
final class iOSPythonExecutionBackend: ExecutionBackend {
    var isAvailable: Bool {
        get async {
            print("❌ [iOSPythonExecutionBackend] Python module not available (canImport(Python) == false)")
            return false
        }
    }

    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        throw CodeExecutionError.processLaunchFailed(
            "Python execution backend is not available in this build (canImport(Python) == false)."
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
