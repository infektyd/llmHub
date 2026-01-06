import XCTest

@testable import llmHub

final class GoogleAIProviderRequestConstructionTests: XCTestCase {

    private func containsKey(_ key: String, in object: Any) -> Bool {
        if let dict = object as? [String: Any] {
            if dict.keys.contains(key) { return true }
            return dict.values.contains { containsKey(key, in: $0) }
        }
        if let array = object as? [Any] {
            return array.contains { containsKey(key, in: $0) }
        }
        return false
    }

    @MainActor
    func testBuildRequestPreservesInlineImages() async throws {
        let providersConfig = makeDefaultConfig()
        let keychain = KeychainStore(backend: InMemoryKeychainBacking(), accessGroups: [])
        try await keychain.updateKey("test", for: .google)

        let provider = GoogleAIProvider(keychain: keychain, config: providersConfig.googleAI)

        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Describe this image",
            thoughtProcess: nil,
            parts: [.text("Describe this image"), .image(pngHeader, mimeType: "image/png")],
            createdAt: Date(),
            codeBlocks: []
        )

        let request = try await provider.buildRequest(messages: [message], model: "gemini-2.0-flash")
        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body, options: [])

        XCTAssertTrue(containsKey("inlineData", in: json))
    }

    @MainActor
    func testBuildRequestIncludesToolDeclarations() async throws {
        let providersConfig = makeDefaultConfig()
        let keychain = KeychainStore(backend: InMemoryKeychainBacking(), accessGroups: [])
        try await keychain.updateKey("test", for: .google)

        let provider = GoogleAIProvider(keychain: keychain, config: providersConfig.googleAI)

        let tool = ToolDefinition(
            name: "workspace",
            description: "List workspace files",
            inputSchema: [
                "type": "object",
                "properties": [
                    "operation": ["type": "string"],
                    "path": ["type": "string"],
                ],
                "required": ["operation"],
            ]
        )

        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: "List files",
            thoughtProcess: nil,
            parts: [.text("List files")],
            createdAt: Date(),
            codeBlocks: []
        )

        let request = try await provider.buildRequest(
            messages: [message],
            model: "gemini-2.0-flash",
            tools: [tool],
            options: .default
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body, options: [])

        XCTAssertTrue(containsKey("functionDeclarations", in: json))
    }
}
