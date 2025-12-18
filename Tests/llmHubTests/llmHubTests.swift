//
//  llmHubTests.swift
//  llmHubTests
//
//  Created by Hans Axelsson on 11/27/25.
//

import XCTest

@testable import llmHub

@MainActor
final class llmHubTests: XCTestCase {

    func testJSONValueEncodingDecoding() throws {
        let jsonString = """
            {
                "key": "value",
                "number": 123.45,
                "bool": true,
                "null": null,
                "array": [1, 2, 3]
            }
            """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let value = try decoder.decode(JSONValue.self, from: data)

        if case .object(let dict) = value {
            XCTAssertEqual(dict["key"], .string("value"))
            XCTAssertEqual(dict["number"], .number(123.45))
            XCTAssertEqual(dict["bool"], .bool(true))
            XCTAssertEqual(dict["null"], .null)

            if case .array(let arr) = dict["array"] {
                XCTAssertEqual(arr.count, 3)
            } else {
                XCTFail("Array not decoded correctly")
            }
        } else {
            XCTFail("Root object not decoded correctly")
        }
    }

    func testWorkspaceStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspace = LightweightWorkspace(storageDirectory: tempDir)
        let item = WorkspaceItem(
            id: UUID(),
            filename: "test.txt",
            content: "Hello World"
        )

        try await workspace.store(item)
        let retrieved = await workspace.retrieve(id: item.id)

        XCTAssertEqual(retrieved?.id, item.id)
        XCTAssertEqual(retrieved?.filename, "test.txt")
        XCTAssertEqual(retrieved?.content, "Hello World")
    }

    /*
    func testToolAuthorization() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
    
        let authService = ToolAuthorizationService(persistenceURL: tempURL)
        let toolID = "test_tool"
    
        let initialStatus = await authService.checkAccess(for: toolID)
        XCTAssertEqual(initialStatus, .notDetermined)
    
        let requestedStatus = await authService.requestAccess(for: toolID)
        XCTAssertEqual(requestedStatus, .authorized)
    
        let checkAgain = await authService.checkAccess(for: toolID)
        XCTAssertEqual(checkAgain, .authorized)
    
        await authService.grantAccess(for: toolID)
        let granted = await authService.checkAccess(for: toolID)
        XCTAssertEqual(granted, .authorized)
    
        await authService.revokeAccess(for: toolID)
        let revokedStatus = await authService.checkAccess(for: toolID)
        XCTAssertEqual(revokedStatus, .denied)
    }
    */

    // MARK: - OpenAI Responses API Content Type Tests

    func testOpenAIResponsesPayloadFormat() throws {
        // Test all roles map to correct content types for Responses API
        let roleTypeMapping: [(MessageRole, String)] = [
            (.user, "input_text"),
            (.system, "input_text"),
            (.tool, "input_text"),
            (.assistant, "output_text"),
        ]

        for (role, expectedType) in roleTypeMapping {
            let content = OpenAIResponseContent.Text(text: "test", role: role)
            XCTAssertEqual(
                content.type, expectedType,
                "Role \(role.rawValue) should produce type '\(expectedType)', got '\(content.type)'"
            )
        }
    }

    func testOpenAIResponsesJSONEncoding() throws {
        // Verify JSON encoding produces correct structure
        let userText = OpenAIResponseContent.Text(text: "Hello", role: .user)
        let encoder = JSONEncoder()
        let data = try encoder.encode(userText)
        let json = String(data: data, encoding: .utf8)!

        // Must contain "input_text", must NOT contain bare "text" as type
        XCTAssertTrue(json.contains("\"input_text\""), "JSON should contain 'input_text' type")
        XCTAssertFalse(
            json.replacingOccurrences(of: "\"text\":", with: "").contains("\"text\""),
            "JSON should not contain bare 'text' type value (excluding the text field name)"
        )

        // Verify assistant role produces output_text
        let assistantText = OpenAIResponseContent.Text(text: "Response", role: .assistant)
        let assistantData = try encoder.encode(assistantText)
        let assistantJson = String(data: assistantData, encoding: .utf8)!
        XCTAssertTrue(
            assistantJson.contains("\"output_text\""),
            "Assistant role should produce 'output_text' type")
    }

    func testGoogleLegacyGemini3FlashPreviewDisplayNameMigratesToModelID() throws {
        let available: [(id: String, displayName: String)] = [
            ("gemini-3-flash-preview", "Gemini 3 Flash Preview"),
            ("gemini-2.5-flash", "Gemini 2.5 Flash"),
        ]

        let resolved = ChatViewModel.resolvePersistedModelID(
            providerID: "google",
            savedModelID: "Gemini 3 Flash Preview",
            availableModels: available
        )

        XCTAssertEqual(resolved, "gemini-3-flash-preview")
    }

    func testGoogleLegacyGemini3ProPreviewDisplayNameMigratesToModelID() throws {
        let available: [(id: String, displayName: String)] = [
            ("gemini-3-pro-preview", "Gemini 3 Pro Preview"),
            ("gemini-3-flash-preview", "Gemini 3 Flash Preview"),
        ]

        let resolved = ChatViewModel.resolvePersistedModelID(
            providerID: "google",
            savedModelID: "Gemini 3 Pro Preview",
            availableModels: available
        )

        XCTAssertEqual(resolved, "gemini-3-pro-preview")
    }

    #if os(macOS)
    func testWorkspaceRootIsNotHomeDirectoryOnMacOS() throws {
        let root = WorkspaceResolver.resolve(platform: .macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        XCTAssertNotEqual(root.standardizedFileURL.path, home.path)
        XCTAssertTrue(root.path.contains("Library") || root.path.contains("Containers"))
    }
    #endif

    func testToolPathResolverRejectsAbsolutePaths() throws {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }

        XCTAssertThrowsError(
            try ToolPathResolver.resolve(inputPath: "/etc/passwd", workspaceRoot: workspace)
        ) { error in
            guard case ToolError.sandboxViolation = error else {
                return XCTFail("Expected sandboxViolation, got: \(error)")
            }
        }
    }

    func testToolPathResolverRejectsDirectoryTraversal() throws {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }

        XCTAssertThrowsError(
            try ToolPathResolver.resolve(inputPath: "../outside.txt", workspaceRoot: workspace)
        ) { error in
            guard case ToolError.sandboxViolation = error else {
                return XCTFail("Expected sandboxViolation, got: \(error)")
            }
        }
    }

    func testToolPathResolverRejectsSymlinkEscape() throws {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }

        let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        let link = workspace.appendingPathComponent("escape", isDirectory: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertThrowsError(
            try ToolPathResolver.resolve(inputPath: "escape/secret.txt", workspaceRoot: workspace)
        ) { error in
            guard case ToolError.sandboxViolation = error else {
                return XCTFail("Expected sandboxViolation, got: \(error)")
            }
        }
    }

    func testProviderIDCanonicalizationForAnthropicAliases() throws {
        XCTAssertEqual(ProviderID.canonicalID(from: "anthropic"), "anthropic")
        XCTAssertEqual(ProviderID.canonicalID(from: "Claude"), "anthropic")
    }
}
