//
//  XPCExecutionBackend.swift
//  llmHub
//
//  XPC-based execution backend for macOS
//  Communicates with the non-sandboxed llmHubHelper XPC service
//

#if os(macOS)
import Foundation
import OSLog

/// XPC-based code execution backend for macOS
/// Connects to the llmHubHelper XPC service for code execution outside the sandbox
final class XPCExecutionBackend: ExecutionBackend, @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.llmhub", category: "XPCExecutionBackend")
    private let connectionQueue = DispatchQueue(label: "com.llmhub.xpc.connection")
    
    private var _connection: NSXPCConnection?
    private let connectionLock = NSLock()
    
    // MARK: - Connection Management
    
    /// Get or create the XPC connection
    private var connection: NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        if let existing = _connection {
            return existing
        }
        
        let newConnection = NSXPCConnection(serviceName: kCodeExecutionXPCServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: CodeExecutionXPCProtocol.self)
        
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.warning("XPC connection invalidated")
            self?.connectionLock.lock()
            self?._connection = nil
            self?.connectionLock.unlock()
        }
        
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
        }
        
        newConnection.resume()
        _connection = newConnection
        
        logger.info("XPC connection established to \(kCodeExecutionXPCServiceName)")
        
        return newConnection
    }
    
    /// Get the remote proxy object
    private func remoteProxy() throws -> CodeExecutionXPCProtocol {
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.logger.error("XPC remote object error: \(error.localizedDescription)")
        }) as? CodeExecutionXPCProtocol else {
            throw XPCExecutionError.connectionFailed
        }
        return proxy
    }
    
    // MARK: - ExecutionBackend
    
    var isAvailable: Bool {
        get async {
            do {
                let proxy = try remoteProxy()
                return await withCheckedContinuation { continuation in
                    proxy.ping { success in
                        continuation.resume(returning: success)
                    }
                }
            } catch {
                logger.error("XPC availability check failed: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        let proxy: CodeExecutionXPCProtocol
        do {
            proxy = try remoteProxy()
        } catch {
            throw CodeExecutionError.processLaunchFailed("Failed to connect to XPC service: \(error.localizedDescription)")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            proxy.executeCode(
                code,
                language: language.rawValue,
                timeout: timeout,
                workingDirectory: workingDirectory?.path
            ) { [weak self] data, error in
                if let error = error {
                    self?.logger.error("XPC execution failed: \(error.localizedDescription)")
                    continuation.resume(throwing: CodeExecutionError.processLaunchFailed(error.localizedDescription))
                    return
                }
                
                guard let data = data else {
                    continuation.resume(throwing: CodeExecutionError.processLaunchFailed("No response from XPC service"))
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let xpcResult = try decoder.decode(XPCExecutionResult.self, from: data)
                    
                    // Convert XPC result to CodeExecutionResult
                    let result = CodeExecutionResult(
                        id: UUID(uuidString: xpcResult.id) ?? UUID(),
                        language: language,
                        code: code,
                        stdout: xpcResult.stdout,
                        stderr: xpcResult.stderr,
                        exitCode: xpcResult.exitCode,
                        executionTimeMs: xpcResult.executionTimeMs,
                        timestamp: Date(),
                        sandboxPath: nil
                    )
                    
                    continuation.resume(returning: result)
                    
                } catch {
                    self?.logger.error("Failed to decode XPC result: \(error.localizedDescription)")
                    continuation.resume(throwing: CodeExecutionError.processLaunchFailed("Invalid response format"))
                }
            }
        }
    }
    
    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        do {
            let proxy = try remoteProxy()
            
            return await withCheckedContinuation { continuation in
                proxy.checkInterpreter(language.rawValue) { path, version, error in
                    if let path = path, !path.isEmpty {
                        continuation.resume(returning: InterpreterInfo(
                            language: language,
                            path: path,
                            version: version,
                            isAvailable: true
                        ))
                    } else {
                        continuation.resume(returning: InterpreterInfo.unavailable(language))
                    }
                }
            }
            
        } catch {
            logger.error("Failed to check interpreter: \(error.localizedDescription)")
            return InterpreterInfo.unavailable(language)
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
    
    // MARK: - Cleanup
    
    deinit {
        connectionLock.lock()
        _connection?.invalidate()
        _connection = nil
        connectionLock.unlock()
    }
}

#endif

