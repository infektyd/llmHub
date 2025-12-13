//
//  CodeExecutionServiceDelegate.swift
//  llmHubHelper
//
//  XPC Service delegate that handles incoming connections
//

#if os(macOS)
import Foundation
import OSLog

/// Delegate for the XPC listener that creates connection handlers.
final class CodeExecutionServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    private let logger = Logger(subsystem: "Syntra.llmHub.CodeExecutionHelper", category: "ServiceDelegate")
    
    /// Called when a new connection is received.
    /// - Parameters:
    ///   - listener: The listener receiving the connection.
    ///   - newConnection: The new XPC connection.
    /// - Returns: True if the connection should be accepted.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("Accepting new XPC connection")
        
        // Configure the connection
        // The exported interface is what we implement (the protocol)
        newConnection.exportedInterface = NSXPCInterface(with: CodeExecutionXPCProtocol.self)
        
        // Create the handler object that implements the protocol
        let exportedObject = CodeExecutionHandler()
        newConnection.exportedObject = exportedObject
        
        // Handle connection invalidation
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection invalidated")
        }
        
        // Handle connection interruption
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
        }
        
        // Resume the connection
        newConnection.resume()
        
        return true
    }
}
#endif
