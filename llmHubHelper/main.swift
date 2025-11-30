//
//  main.swift
//  llmHubHelper
//
//  Entry point for the XPC code execution helper service
//

import Foundation

// Create the delegate for the XPC service
let delegate = CodeExecutionServiceDelegate()

// Create the listener with the service delegate
let listener = NSXPCListener.service()
listener.delegate = delegate

// Resume the listener to start accepting connections
// This never returns while the service is running
listener.resume()

// Run the main run loop (required for XPC service)
RunLoop.main.run()

