//
//  MCPClient.swift
//  llmHub
//
//  Model Context Protocol (MCP) client implementation
//  Supports JSON-RPC 2.0 communication with MCP servers
//

import Foundation
import OSLog

/// MCP Client for communicating with Model Context Protocol servers
actor MCPClient {
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPClient")
    
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    
    private var requestID: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var isConnected = false
    
    let serverConfig: MCPServerConfig
    
    init(config: MCPServerConfig) {
        self.serverConfig = config
    }
    
    deinit {
        // Synchronously cleanup what we can in deinit
        // Note: We cannot await inside deinit, so we do synchronous cleanup only.
        // The process termination and file handle closure are safe synchronous operations.
        // Pending requests will fail naturally when the connection is closed.
        stdin?.closeFile()
        process?.terminate()
        
        // Cancel pending requests synchronously
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPError.connectionClosed)
        }
    }
    
    // MARK: - Connection Management
    
    /// Connect to the MCP server
    func connect() async throws {
        guard !isConnected else { return }
        
        logger.info("Connecting to MCP server: \(self.serverConfig.name)")
        
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
    }
    
    /// Disconnect from the MCP server
    func disconnect() {
        guard isConnected else { return }
        
        logger.info("Disconnecting from MCP server: \(self.serverConfig.name)")
        
        stdin?.closeFile()
        process?.terminate()
        
        process = nil
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
    
    /// Initialize the MCP session
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
    
    /// List available tools from the server
    func listTools() async throws -> [MCPToolInfo] {
        let response = try await sendRequest(method: "tools/list", params: EmptyParams())
        
        guard let result = response.result?.value as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        
        let data = try JSONSerialization.data(withJSONObject: toolsArray)
        return try JSONDecoder().decode([MCPToolInfo].self, from: data)
    }
    
    /// Call a tool on the server
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        let params = MCPToolCallParams(name: name, arguments: MCPJSONValue.from(arguments))
        
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
    
    /// List available resources from the server
    func listResources() async throws -> [MCPResource] {
        let response = try await sendRequest(method: "resources/list", params: EmptyParams())
        
        guard let result = response.result?.value as? [String: Any],
              let resourcesArray = result["resources"] as? [[String: Any]] else {
            return []
        }
        
        let data = try JSONSerialization.data(withJSONObject: resourcesArray)
        return try JSONDecoder().decode([MCPResource].self, from: data)
    }
    
    /// Read a resource from the server
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
    
    private func sendRequest<T: Encodable & Sendable>(method: String, params: T) async throws -> MCPResponse {
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
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            } catch {
                logger.error("Error reading from MCP server: \(error)")
                break
            }
        }
    }
    
    private func handleResponse(_ response: MCPResponse) {
        guard let id = response.id,
              let continuation = pendingRequests.removeValue(forKey: id) else {
            // Could be a notification or unknown response
            return
        }
        
        continuation.resume(returning: response)
    }
}

// MARK: - MCP Data Types

struct MCPServerConfig: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]?
    var isEnabled: Bool = true
}

// Empty params struct for requests that don't need params
// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct EmptyParams: Encodable, Sendable {}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPToolCallParams: Encodable, Sendable {
    let name: String
    let arguments: MCPJSONValue
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPResourceReadParams: Encodable, Sendable {
    let uri: String
}

// JSON value wrapper for MCP API (handles Any -> Encodable conversion)
// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) enum MCPJSONValue: Encodable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])
    
    static func from(_ value: Any) -> MCPJSONValue {
        switch value {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let d as Double:
            return .double(d)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        default:
            return .null
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let dict):
            try container.encode(dict)
        }
    }
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPRequest<T: Encodable & Sendable>: Encodable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: T
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPNotification<T: Encodable & Sendable>: Encodable, Sendable {
    let jsonrpc: String
    let method: String
    let params: T
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPResponse: Decodable, Sendable {
    let jsonrpc: String
    let id: Int?
    let result: AnySendable?
    let error: MCPErrorInfo?
    
    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(MCPErrorInfo.self, forKey: .error)
        
        // Decode result as AnySendable
        if let dict = try? container.decode([String: AnyCodable].self, forKey: .result) {
            result = AnySendable(dict.mapValues { $0.value })
        } else if let array = try? container.decode([AnyCodable].self, forKey: .result) {
            result = AnySendable(array.map { $0.value })
        } else {
            result = nil
        }
    }
}

/// Thread-safe wrapper for Any values
struct AnySendable: @unchecked Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
}

struct MCPErrorInfo: Decodable, Sendable {
    let code: Int
    let message: String
    let data: String?
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPInitializeParams: Encodable, Sendable {
    let protocolVersion: String
    let capabilities: MCPClientCapabilities
    let clientInfo: MCPClientInfo
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPClientCapabilities: Encodable, Sendable {
    // Empty for now - add capabilities as needed
}

// Marked nonisolated to allow cross-actor usage without isolation requirements
nonisolated(unsafe) struct MCPClientInfo: Encodable, Sendable {
    let name: String
    let version: String
}

struct MCPInitializeResult: Decodable, Sendable {
    let protocolVersion: String?
    let capabilities: MCPServerCapabilities?
    let serverInfo: MCPServerInfo?
}

struct MCPServerCapabilities: Decodable, Sendable {
    let tools: [String: Bool]?
    let resources: [String: Bool]?
    let prompts: [String: Bool]?
}

struct MCPServerInfo: Decodable, Sendable {
    let name: String
    let version: String?
}

struct MCPToolInfo: Decodable, Sendable {
    let name: String
    let description: String?
    let inputSchema: MCPInputSchema?
}

struct MCPInputSchema: Decodable, Sendable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}

struct MCPPropertySchema: Decodable, Sendable {
    let type: String
    let description: String?
}

struct MCPToolResult: Decodable, Sendable {
    let content: [MCPContent]
    let isError: Bool?
}

struct MCPContent: Decodable, Sendable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?
}

struct MCPResource: Decodable, Sendable {
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?
}

struct MCPResourceContent: Decodable, Sendable {
    let contents: [MCPResourceItem]
}

struct MCPResourceItem: Decodable, Sendable {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String?
}

// MARK: - Errors

enum MCPError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case connectionClosed
    case invalidResponse(String)
    case toolCallFailed(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to MCP server"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .connectionClosed: return "Connection closed"
        case .invalidResponse(let reason): return "Invalid response: \(reason)"
        case .toolCallFailed(let reason): return "Tool call failed: \(reason)"
        case .timeout: return "Request timed out"
        }
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}

