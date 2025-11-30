//
//  CodeExecutionHandler.swift
//  llmHubHelper
//
//  Implements the XPC protocol for code execution
//  This runs outside the app sandbox, allowing access to xcrun and interpreters
//

import Foundation
import OSLog

/// Handler that implements the XPC protocol for code execution
/// Runs in the non-sandboxed XPC helper process
final class CodeExecutionHandler: NSObject, CodeExecutionXPCProtocol {
    
    private let logger = Logger(subsystem: "Syntra.llmHub.CodeExecutionHelper", category: "Handler")
    private let executor = CodeExecutor()
    
    // MARK: - CodeExecutionXPCProtocol
    
    func executeCode(
        _ code: String,
        language: String,
        timeout: Int,
        workingDirectory: String?,
        reply: @escaping (Data?, Error?) -> Void
    ) {
        logger.info("Executing \(language) code (\(code.count) chars)")
        
        Task {
            do {
                let result = try await executor.execute(
                    code: code,
                    language: language,
                    timeout: timeout,
                    workingDirectory: workingDirectory
                )
                
                let encoder = JSONEncoder()
                let data = try encoder.encode(result)
                
                logger.info("Execution completed: exit=\(result.exitCode), time=\(result.executionTimeMs)ms")
                reply(data, nil)
                
            } catch {
                logger.error("Execution failed: \(error.localizedDescription)")
                reply(nil, error)
            }
        }
    }
    
    func checkInterpreter(
        _ language: String,
        reply: @escaping (String?, String?, Error?) -> Void
    ) {
        logger.debug("Checking interpreter for \(language)")
        
        Task {
            let (path, version) = await executor.findInterpreter(for: language)
            
            if let path = path {
                logger.debug("Found \(language) at \(path)")
                reply(path, version, nil)
            } else {
                logger.debug("Interpreter for \(language) not found")
                reply(nil, nil, XPCExecutionError.interpreterNotFound(language))
            }
        }
    }
    
    func getVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        reply("\(version) (\(build))")
    }
    
    func ping(reply: @escaping (Bool) -> Void) {
        logger.debug("Ping received")
        reply(true)
    }
}

