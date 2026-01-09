//
//  ToolAuthorizationSecurityTests.swift
//  llmHubTests
//
//  Security tests for tool authorization system.
//  Verifies that file access tools are properly gated by authorization.
//

import XCTest
import Foundation
@testable import llmHub

@MainActor
final class ToolAuthorizationSecurityTests: XCTestCase {

    var authService: ToolAuthorizationService!
    let conversationID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        authService = ToolAuthorizationService()
    }

    override func tearDown() async throws {
        authService = nil
        try await super.tearDown()
    }

    // MARK: - Default Behavior Tests

    func testDefaultPermissionIsDenied() async throws {
        // SECURITY: By default, all tools should be DENIED (not .notDetermined)
        let status = authService.checkAccess(for: "read_file")
        XCTAssertEqual(status, .denied, "Default permission should be .denied for security")
    }

    func testDefaultConversationPermissionIsDenied() async throws {
        // SECURITY: Conversation-scoped checks should also default to .denied
        let status = authService.checkAccess(for: "read_file", conversationID: conversationID)
        XCTAssertEqual(status, .denied, "Default conversation permission should be .denied")
    }

    func testMultipleToolsDefaultDenied() async throws {
        let fileTools = ["read_file", "write_file", "list_files", "workspace"]

        for toolName in fileTools {
            let status = authService.checkAccess(for: toolName)
            XCTAssertEqual(status, .denied, "\(toolName) should default to .denied")
        }
    }

    // MARK: - Global Authorization Tests

    func testGrantGlobalAccess() async throws {
        authService.grantAccess(for: "read_file")

        let status = authService.checkAccess(for: "read_file")
        XCTAssertEqual(status, .authorized, "Tool should be authorized after grant")
    }

    func testDenyGlobalAccess() async throws {
        authService.grantAccess(for: "read_file")
        authService.denyAccess(for: "read_file")

        let status = authService.checkAccess(for: "read_file")
        XCTAssertEqual(status, .denied, "Tool should be denied after explicit deny")
    }

    func testRevokeGlobalAccess() async throws {
        authService.grantAccess(for: "read_file")
        authService.revokeAccess(for: "read_file")

        let status = authService.checkAccess(for: "read_file")
        XCTAssertEqual(status, .denied, "Tool should return to default .denied after revoke")
    }

    // MARK: - Conversation-Scoped Authorization Tests

    func testGrantConversationAccess() async throws {
        authService.grantAccessForConversation(tool: "read_file", conversationID: conversationID)

        let status = authService.checkAccess(for: "read_file", conversationID: conversationID)
        XCTAssertEqual(status, .authorized, "Tool should be authorized for specific conversation")
    }

    func testConversationScopedAuthorizationDoesNotAffectOtherConversations() async throws {
        let otherConversationID = UUID()

        authService.grantAccessForConversation(tool: "read_file", conversationID: conversationID)

        let status1 = authService.checkAccess(for: "read_file", conversationID: conversationID)
        let status2 = authService.checkAccess(for: "read_file", conversationID: otherConversationID)

        XCTAssertEqual(status1, .authorized, "Tool should be authorized for conversation 1")
        XCTAssertEqual(status2, .denied, "Tool should remain denied for conversation 2")
    }

    func testDenyConversationAccess() async throws {
        authService.grantAccessForConversation(tool: "read_file", conversationID: conversationID)
        authService.denyAccessForConversation(tool: "read_file", conversationID: conversationID)

        let status = authService.checkAccess(for: "read_file", conversationID: conversationID)
        XCTAssertEqual(status, .denied, "Tool should be denied for conversation after deny")
    }

    func testClearConversationPermissions() async throws {
        authService.grantAccessForConversation(tool: "read_file", conversationID: conversationID)
        authService.grantAccessForConversation(tool: "write_file", conversationID: conversationID)

        authService.clearConversationPermissions(conversationID: conversationID)

        let status1 = authService.checkAccess(for: "read_file", conversationID: conversationID)
        let status2 = authService.checkAccess(for: "write_file", conversationID: conversationID)

        XCTAssertEqual(status1, .denied, "read_file should be denied after clear")
        XCTAssertEqual(status2, .denied, "write_file should be denied after clear")
    }

    // MARK: - Priority Tests (Conversation vs Global)

    func testConversationPermissionOverridesGlobal() async throws {
        // Grant global access
        authService.grantAccess(for: "read_file")

        // Deny for specific conversation
        authService.denyAccessForConversation(tool: "read_file", conversationID: conversationID)

        let globalStatus = authService.checkAccess(for: "read_file")
        let conversationStatus = authService.checkAccess(for: "read_file", conversationID: conversationID)

        XCTAssertEqual(globalStatus, .authorized, "Global access should be authorized")
        XCTAssertEqual(conversationStatus, .denied, "Conversation-scoped deny should override global")
    }

    func testConversationAuthorizationWithoutGlobal() async throws {
        // Do NOT grant global access (defaults to .denied)

        // Grant for specific conversation
        authService.grantAccessForConversation(tool: "read_file", conversationID: conversationID)

        let globalStatus = authService.checkAccess(for: "read_file")
        let conversationStatus = authService.checkAccess(for: "read_file", conversationID: conversationID)

        XCTAssertEqual(globalStatus, .denied, "Global access should remain denied")
        XCTAssertEqual(conversationStatus, .authorized, "Conversation should be authorized")
    }

    // MARK: - Persistence Tests

    func testPersistenceAfterSave() async throws {
        authService.grantAccess(for: "read_file")
        authService.grantAccessForConversation(tool: "write_file", conversationID: conversationID)

        authService.savePermissions()

        // Create new service instance (simulates app restart)
        let newAuthService = ToolAuthorizationService()

        let globalStatus = newAuthService.checkAccess(for: "read_file")
        let conversationStatus = newAuthService.checkAccess(for: "write_file", conversationID: conversationID)

        XCTAssertEqual(globalStatus, .authorized, "Global permission should persist")
        XCTAssertEqual(conversationStatus, .authorized, "Conversation permission should persist")
    }

    // MARK: - Security Boundary Tests

    func testFileToolsRequireAuthorization() async throws {
        let fileSensitiveTools = [
            "read_file",
            "write_file",
            "list_files",
            "workspace",
            "file_editor",
            "file_patch"
        ]

        for toolName in fileSensitiveTools {
            let status = authService.checkAccess(for: toolName)
            XCTAssertNotEqual(status, .authorized, "\(toolName) should NOT be authorized by default")
        }
    }

    func testNonFileToolsStillRequireAuthorization() async throws {
        // SECURITY: Even non-file tools should default to denied (principle of least privilege)
        let otherTools = ["calculator", "web_search", "http_request", "shell"]

        for toolName in otherTools {
            let status = authService.checkAccess(for: toolName)
            XCTAssertEqual(status, .denied, "\(toolName) should default to .denied")
        }
    }

    // MARK: - Edge Cases

    func testEmptyToolName() async throws {
        let status = authService.checkAccess(for: "")
        XCTAssertEqual(status, .denied, "Empty tool name should be denied")
    }

    func testUnknownToolName() async throws {
        let status = authService.checkAccess(for: "nonexistent_tool_xyz")
        XCTAssertEqual(status, .denied, "Unknown tool should be denied")
    }

    func testMultipleConversationsIndependence() async throws {
        let conv1 = UUID()
        let conv2 = UUID()
        let conv3 = UUID()

        authService.grantAccessForConversation(tool: "read_file", conversationID: conv1)
        authService.grantAccessForConversation(tool: "write_file", conversationID: conv2)

        XCTAssertEqual(
            authService.checkAccess(for: "read_file", conversationID: conv1),
            .authorized
        )
        XCTAssertEqual(
            authService.checkAccess(for: "write_file", conversationID: conv2),
            .authorized
        )
        XCTAssertEqual(
            authService.checkAccess(for: "read_file", conversationID: conv2),
            .denied
        )
        XCTAssertEqual(
            authService.checkAccess(for: "write_file", conversationID: conv1),
            .denied
        )
        XCTAssertEqual(
            authService.checkAccess(for: "read_file", conversationID: conv3),
            .denied
        )
    }
}
