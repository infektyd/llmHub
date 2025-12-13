import XCTest

@testable import llmHub

@MainActor
final class ToolSchemaValidationTests: XCTestCase {
    func testWorkspaceToolSchema_fileExtensionsHasStringItems() throws {
        let schema = WorkspaceTool().parameters.toDictionary()
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        let fileExtensions = try XCTUnwrap(props["file_extensions"] as? [String: Any])
        XCTAssertEqual(fileExtensions["type"] as? String, "array")

        let items = try XCTUnwrap(fileExtensions["items"] as? [String: Any])
        XCTAssertEqual(items["type"] as? String, "string")

        let jsonData = try JSONSerialization.data(
            withJSONObject: fileExtensions,
            options: [.prettyPrinted, .sortedKeys]
        )
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        let attachment = XCTAttachment(string: json)
        attachment.name = "workspace.file_extensions.schema.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
