//
//  MCPToolBridge.swift
//  llmHub
//
//  Bridge between MCP servers and the native Tool protocol
//  Discovers and wraps MCP tools for use in the ToolRegistry
//

import Foundation
import OSLog

/// Manages MCP server connections and bridges their tools to the native Tool protocol
actor MCPToolBridge {
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPToolBridge")

    private var clients: [UUID: MCPClient] = [:]
    private var discoveredTools: [String: MCPBridgedTool] = [:]

    // User Defaults key for storing server configurations
    private let configKey = "mcp.serverConfigs"

    // MARK: - Server Management

    /// Load saved server configurations
    func loadConfigurations() -> [MCPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: configKey),
            let configs = try? JSONDecoder().decode([MCPServerConfig].self, from: data)
        else {
            return []
        }
        return configs
    }

    /// Save server configurations
    func saveConfigurations(_ configs: [MCPServerConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    /// Add a new MCP server configuration
    func addServer(_ config: MCPServerConfig) {
        var configs = loadConfigurations()
        configs.append(config)
        saveConfigurations(configs)
    }

    /// Remove an MCP server configuration
    func removeServer(id: UUID) {
        var configs = loadConfigurations()
        configs.removeAll { $0.id == id }
        saveConfigurations(configs)

        // Disconnect if connected
        if let client = clients.removeValue(forKey: id) {
            Task { await client.disconnect() }
        }
    }

    /// Update an MCP server configuration
    func updateServer(_ config: MCPServerConfig) {
        var configs = loadConfigurations()
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            saveConfigurations(configs)
        }
    }

    // MARK: - Connection Management

    /// Connect to all enabled MCP servers
    func connectAll() async {
        let configs = loadConfigurations().filter { $0.isEnabled }

        for config in configs {
            await connect(to: config)
        }
    }

    /// Connect to a specific MCP server
    func connect(to config: MCPServerConfig) async {
        guard clients[config.id] == nil else {
            logger.debug("Already connected to: \(config.name)")
            return
        }

        let client = MCPClient(config: config)

        do {
            try await client.connect()
            clients[config.id] = client
            logger.info("Connected to MCP server: \(config.name)")

            // Discover tools
            await discoverTools(from: client, serverID: config.id)

        } catch {
            logger.error("Failed to connect to \(config.name): \(error)")
        }
    }

    /// Disconnect from a specific MCP server
    func disconnect(serverID: UUID) async {
        guard let client = clients.removeValue(forKey: serverID) else { return }

        await client.disconnect()

        // Remove tools from this server
        discoveredTools = discoveredTools.filter { $0.value.serverID != serverID }

        logger.info("Disconnected from MCP server: \(serverID)")
    }

    /// Disconnect from all MCP servers
    func disconnectAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
        discoveredTools.removeAll()
    }

    // MARK: - Tool Discovery

    /// Discover tools from a connected MCP server
    private func discoverTools(from client: MCPClient, serverID: UUID) async {
        do {
            let tools = try await client.listTools()

            for toolInfo in tools {
                let bridgedTool = MCPBridgedTool(
                    serverID: serverID,
                    client: client,
                    toolInfo: toolInfo
                )

                // Use qualified name to avoid conflicts
                let qualifiedName = "mcp_\(serverID.uuidString.prefix(8))_\(toolInfo.name)"
                discoveredTools[qualifiedName] = bridgedTool

                logger.info("Discovered MCP tool: \(toolInfo.name) -> \(qualifiedName)")
            }

        } catch {
            logger.error("Failed to discover tools: \(error)")
        }
    }

    // MARK: - Tool Access

    /// Get all bridged tools as an array
    var allTools: [any Tool] {
        Array(discoveredTools.values)
    }

    /// Get a specific bridged tool
    func tool(named name: String) -> (any Tool)? {
        discoveredTools[name]
    }

    /// Register all MCP tools into a ToolRegistry
    /// Returns the tools to be registered externally
    func getToolsForRegistration() -> [any Tool] {
        Array(discoveredTools.values)
    }

    // MARK: - Status

    /// Check if connected to any MCP servers
    var isConnected: Bool {
        !clients.isEmpty
    }

    /// Get connection status for all configured servers
    func connectionStatus() -> [(config: MCPServerConfig, isConnected: Bool)] {
        let configs = loadConfigurations()
        return configs.map { config in
            (config, clients[config.id] != nil)
        }
    }
}

// MARK: - MCPBridgedTool

/// A Tool implementation that bridges to an MCP server tool
/// Uses nonisolated(unsafe) to opt out of actor isolation since this is a thread-safe value type wrapper
/// A Tool implementation that bridges to an MCP server tool
/// Uses @unchecked Sendable because inputSchema is [String: Any] which is not Sendable,
/// but we know it's immutable and thread-safe in this context.
final class MCPBridgedTool: Tool, @unchecked Sendable {
    nonisolated let id: String
    nonisolated let name: String
    nonisolated let description: String
    nonisolated(unsafe) let inputSchema: [String: Any]

    nonisolated let serverID: UUID
    private let client: MCPClient
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPBridgedTool")

    nonisolated init(serverID: UUID, client: MCPClient, toolInfo: MCPToolInfo) {
        self.serverID = serverID
        self.client = client
        self.id = "mcp_\(serverID.uuidString.prefix(8))_\(toolInfo.name)"
        self.name = toolInfo.name
        self.description = toolInfo.description ?? "MCP tool: \(toolInfo.name)"

        // Convert MCP input schema to our format
        if let schema = toolInfo.inputSchema {
            var props: [String: Any] = [:]
            for (key, prop) in schema.properties ?? [:] {
                props[key] = [
                    "type": prop.type,
                    "description": prop.description ?? "",
                ]
            }
            self.inputSchema = [
                "type": schema.type,
                "properties": props,
                "required": schema.required ?? [],
            ]
        } else {
            self.inputSchema = [
                "type": "object",
                "properties": [:],
                "required": [],
            ]
        }
    }

    nonisolated func execute(input: [String: Any]) async throws -> String {
        logger.info("Calling MCP tool: \(self.name)")

        do {
            let result = try await client.callTool(name: name, arguments: input)

            // Format the result
            var output = ""
            for content in result.content {
                switch content.type {
                case "text":
                    output += content.text ?? ""
                case "image":
                    if let mimeType = content.mimeType, let data = content.data {
                        output += "[Image: \(mimeType), \(data.count) bytes]\n"
                    }
                case "resource":
                    output += "[Resource]\n"
                default:
                    output += "[Unknown content type: \(content.type)]\n"
                }
            }

            if result.isError == true {
                throw ToolError.executionFailed(output)
            }

            return output.isEmpty ? "(No output)" : output

        } catch let error as MCPError {
            logger.error("MCP tool call failed: \(error)")
            throw ToolError.executionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Default Server Configurations

extension MCPToolBridge {
    /// Get some example MCP server configurations
    static var exampleConfigurations: [MCPServerConfig] {
        [
            // Filesystem MCP server (Node.js)
            MCPServerConfig(
                name: "Filesystem",
                command: "/usr/local/bin/npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                env: nil,
                isEnabled: false
            ),
            // Git MCP server
            MCPServerConfig(
                name: "Git",
                command: "/usr/local/bin/npx",
                args: ["-y", "@modelcontextprotocol/server-git"],
                env: nil,
                isEnabled: false
            ),
            // Memory MCP server
            MCPServerConfig(
                name: "Memory",
                command: "/usr/local/bin/npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                env: nil,
                isEnabled: false
            ),
        ]
    }
}

// MARK: - MCPToolManager (Singleton)

/// Global manager for MCP tool bridge
/// Use this to access MCP tools throughout the app
final class MCPToolManager: @unchecked Sendable {
    static let shared = MCPToolManager()

    private let bridge = MCPToolBridge()
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPToolManager")

    private init() {}

    /// Initialize and connect to all enabled MCP servers
    func initialize() async {
        await bridge.connectAll()
        logger.info("MCP Tool Manager initialized")
    }

    /// Get all available MCP tools
    var tools: [any Tool] {
        get async {
            await bridge.allTools
        }
    }

    /// Register all MCP tools into a registry
    func registerTools(into registry: inout ToolRegistry) async {
        let tools = await bridge.getToolsForRegistration()
        for tool in tools {
            registry.register(tool)
        }
    }

    /// Add a new MCP server
    func addServer(_ config: MCPServerConfig) async {
        await bridge.addServer(config)
        if config.isEnabled {
            await bridge.connect(to: config)
        }
    }

    /// Remove an MCP server
    func removeServer(id: UUID) async {
        await bridge.removeServer(id: id)
    }

    /// Get connection status
    func connectionStatus() async -> [(config: MCPServerConfig, isConnected: Bool)] {
        await bridge.connectionStatus()
    }

    /// Disconnect from all servers
    func shutdown() async {
        await bridge.disconnectAll()
    }
}
