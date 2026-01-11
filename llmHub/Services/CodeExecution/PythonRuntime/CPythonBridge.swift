//
//  CPythonBridge.swift
//  llmHub
//
//  Swift wrapper around the ObjC++ CPython bridge.
//  This keeps Python C-API imports out of Swift and makes it easier to
//  reason about Swift 6 concurrency.
//

import Foundation

enum CPythonBridge {

    /// Initialize the embedded interpreter.
    ///
    /// - Parameters:
    ///   - pythonHome: Path to embedded python root folder (e.g. <App>/python)
    ///   - pythonPath: Extra entries for sys.path (colon separated)
    nonisolated static func initialize(pythonHome: String, pythonPath: String) -> Bool {
        pythonHome.withCString { homePtr in
            pythonPath.withCString { pathPtr in
                llmhub_python_initialize(homePtr, pathPtr)
            }
        }
    }

    /// Execute a Python source string. Returns 0 for success.
    nonisolated static func runSimpleString(_ code: String) -> Int32 {
        code.withCString { ptr in
            Int32(llmhub_python_run_simple_string(ptr))
        }
    }

    nonisolated static func runAndCapture(_ code: String) -> (stdout: String, stderr: String, exitCode: Int32)? {
        var outPtr: UnsafeMutablePointer<CChar>?
        var errPtr: UnsafeMutablePointer<CChar>?
        var exitCode: Int32 = -1

        let ok: Bool = code.withCString { cstr in
            llmhub_python_run_and_capture(cstr, &outPtr, &errPtr, &exitCode)
        }

        guard ok else { return nil }

        let stdout = outPtr.map { String(cString: $0) } ?? ""
        let stderr = errPtr.map { String(cString: $0) } ?? ""

        if let outPtr { free(outPtr) }
        if let errPtr { free(errPtr) }

        return (stdout, stderr, exitCode)
    }

    static func finalize() {
        llmhub_python_finalize()
    }
}
