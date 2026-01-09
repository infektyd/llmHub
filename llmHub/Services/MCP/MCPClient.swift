//
//  MCPClient.swift
//  llmHub
//
//  Model Context Protocol (MCP) client implementation
//  Supports JSON-RPC 2.0 communication with MCP servers
//

import Foundation
import OSLog

/// MCP Client for communicating with Model Context Protocol servers.
actor MCPClient {
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPClient")

    #if os(macOS)
    private var process: Process?
    #endif
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?

    private var requestID: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var isConnected = false

    let serverConfig: MCPServerConfig

    /// Initializes a new `MCPClient` with the given configuration.
    /// - Parameter config: The configuration for the MCP server.
    init(config: MCPServerConfig) {
        self.serverConfig = config
    }

    deinit {
        // Synchronously cleanup what we can in deinit
        // Note: We cannot await inside deinit, so we do synchronous cleanup only.
        // The process termination and file handle closure are safe synchronous operations.
        // Pending requests will fail naturally when the connection is closed.
        stdin?.closeFile()
        #if os(macOS)
        process?.terminate()
        #endif

        // Cancel pending requests synchronously
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPError.connectionClosed)
        }
    }

    // MARK: - Connection Management

    /// Connect to the MCP server.
    func connect() async throws {
        guard !isConnected else { return }

        logger.info("Connecting to MCP server: \(self.serverConfig.name)")

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverConfig.command)
        process.arguments = serverConfig.args
        process.environment = serverConfig.env ?? ProcessInfo.processInfo.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to start MCP server: \(error)")
            throw MCPError.connectionFailed(error.localizedDescription)
        }

        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading
        self.stderr = stderrPipe.fileHandleForReading
        self.isConnected = true

        // Start reading responses
        Task { await readResponses() }

        // Send initialize request
        let initResult = try await initialize()
        logger.info("MCP server initialized: \(initResult.serverInfo?.name ?? "unknown")")
        #else
        throw MCPError.connectionFailed("MCP Local Process execution is not supported on iOS")
        #endif
    }

    /// Disconnect from the MCP server.
    func disconnect() {
        guard isConnected else { return }

        logger.info("Disconnecting from MCP server: \(self.serverConfig.name)")

        stdin?.closeFile()
        #if os(macOS)
        process?.terminate()
        process = nil
        #endif

        stdin = nil
        stdout = nil
        stderr = nil
        isConnected = false

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPError.connectionClosed)
        }
        pendingRequests.removeAll()
    }

    // MARK: - MCP Protocol Methods

    /// Initialize the MCP session.
    private func initialize() async throws -> MCPInitializeResult {
        let params = MCPInitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: MCPClientCapabilities(),
            clientInfo: MCPClientInfo(name: "llmHub", version: "1.0.0")
        )

        let response = try await sendRequest(method: "initialize", params: params)

        guard let result = response.result?.value else {
            throw MCPError.invalidResponse("Initialize failed")
        }

        // Decode result
        let data = try JSONSerialization.data(withJSONObject: result)
        let initResult = try JSONDecoder().decode(MCPInitializeResult.self, from: data)

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: EmptyParams())

        return initResult
    }

    /// List available tools from the server.
    /// - Returns: A list of `MCPToolInfo`.
    func listTools() async throws -> [MCPToolInfo] {
        let response = try await sendRequest(method: "tools/list", params: EmptyParams())

        guard let result = response.result?.value as? [String: Any],
            let toolsArray = result["tools"] as? [[String: Any]]
        else {
            return []
        }

        let data = try JSONSerialization.data(withJSONObject: toolsArray)
        return try JSONDecoder().decode([MCPToolInfo].self, from: data)
    }

    /// Call a tool on the server.
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: The arguments for the tool.
    /// - Returns: The result of the tool execution.
    func callTool(name: String, arguments: MCPJSONValue) async throws -> MCPToolResult {
        let params = MCPToolCallParams(name: name, arguments: arguments)

        let response = try await sendRequest(method: "tools/call", params: params)

        if let error = response.error {
            throw MCPError.toolCallFailed(error.message)
        }

        guard let result = response.result?.value as? [String: Any] else {
            throw MCPError.invalidResponse("Tool call returned no result")
        }

        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(MCPToolResult.self, from: data)
    }

    /// List available resources from the server.
    /// - Returns: A list of `MCPResource`.
    func listResources() async throws -> [MCPResource] {
        let response = try await sendRequest(method: "resources/list", params: EmptyParams())

        guard let result = response.result?.value as? [String: Any],
            let resourcesArray = result["resources"] as? [[String: Any]]
        else {
            return []
        }

        let data = try JSONSerialization.data(withJSONObject: resourcesArray)
        return try JSONDecoder().decode([MCPResource].self, from: data)
    }

    /// Read a resource from the server.
    /// - Parameter uri: The URI of the resource to read.
    /// - Returns: The content of the resource.
    func readResource(uri: String) async throws -> MCPResourceContent {
        let params = MCPResourceReadParams(uri: uri)
        let response = try await sendRequest(method: "resources/read", params: params)

        guard let result = response.result?.value as? [String: Any] else {
            throw MCPError.invalidResponse("Resource read returned no result")
        }

        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(MCPResourceContent.self, from: data)
    }

    // MARK: - JSON-RPC Communication

    /// Sends a JSON-RPC request to the server.
    /// - Parameters:
    ///   - method: The method name.
    ///   - params: The method parameters.
    /// - Returns: The server's response.
    private func sendRequest<T: Encodable & Sendable>(method: String, params: T) async throws
        -> MCPResponse {
        guard isConnected, let stdin = stdin else {
            throw MCPError.notConnected
        }

        requestID += 1
        let currentID = requestID

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: currentID,
            method: method,
            params: params
        )

        let encoder = JSONEncoder()
        var data = try encoder.encode(request)
        data.append(contentsOf: "\n".utf8)

        // Send request
        try stdin.write(contentsOf: data)

        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[currentID] = continuation
        }
    }

    /// Sends a JSON-RPC notification to the server.
    /// - Parameters:
    ///   - method: The notification method name.
    ///   - params: The notification parameters.
    private func sendNotification<T: Encodable & Sendable>(method: String, params: T) async throws {
        guard isConnected, let stdin = stdin else {
            throw MCPError.notConnected
        }

        let notification = MCPNotification(
            jsonrpc: "2.0",
            method: method,
            params: params
        )

        let encoder = JSONEncoder()
        var data = try encoder.encode(notification)
        data.append(contentsOf: "\n".utf8)

        try stdin.write(contentsOf: data)
    }

    /// Continuously reads responses from the server's stdout.
    private func readResponses() async {
        guard let stdout = stdout else { return }

        var buffer = Data()

        while isConnected {
            do {
                let chunk = stdout.availableData
                if chunk.isEmpty {
                    // EOF
                    break
                }

                buffer.append(chunk)

                // Try to parse complete JSON-RPC messages (newline-delimited)
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let messageData = buffer[..<newlineIndex]
                    buffer = buffer[(newlineIndex + 1)...]

                    if let response = try? JSONDecoder().decode(MCPResponse.self, from: messageData) {
                        handleResponse(response)
                    }
                }

                // Small delay to prevent busy-waiting
                try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            } catch {
                logger.error("Error reading from MCP server: \(error)")
                break
            }
        }
    }

    /// Handles a received response, matching it to a pending request.
    /// - Parameter response: The received MCP response.
    private func handleResponse(_ response: MCPResponse) {
        guard let id = response.id,
            let continuation = pendingRequests.removeValue(forKey: id)
        else {
            // Could be a notification or unknown response
            return
        }

        continuation.resume(returning: response)
    }
}
