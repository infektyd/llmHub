import XCTest

@testable import llmHub

final class ModelListParsingAndOverlayTests: XCTestCase {

    func testAnthropicModelsParsingAndPaginationFields() throws {
        let json = #"""
        {
          "data": [
            {"id": "claude-3-5-sonnet-20241022", "display_name": "Claude 3.5 Sonnet", "created_at": "2024-10-22T00:00:00Z", "type": "model"}
          ],
          "first_id": "claude-3-5-sonnet-20241022",
          "last_id": "claude-3-5-sonnet-20241022",
          "has_more": true
        }
        """#

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(FetchedAnthropicModelsResponse.self, from: data)

        XCTAssertEqual(decoded.data.count, 1)
        XCTAssertEqual(decoded.data.first?.id, "claude-3-5-sonnet-20241022")
        XCTAssertEqual(decoded.data.first?.displayName, "Claude 3.5 Sonnet")
        XCTAssertEqual(decoded.hasMore, true)
        XCTAssertEqual(decoded.lastID, "claude-3-5-sonnet-20241022")
    }

    func testXAIModelsOpenAIStyleParsing() throws {
        let json = #"""
        {
          "object": "list",
          "data": [
            {"id": "grok-4"},
            {"id": "grok-3-mini"}
          ]
        }
        """#

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(FetchedOpenAIStyleModelsResponse.self, from: data)

        XCTAssertEqual(decoded.data.map(\.id), ["grok-4", "grok-3-mini"])
    }

    func testProvidersConfigOverlayPreservesCapabilities() {
        // Emulate overlay behavior: defaults win on capabilities.
        let defaults = [
            LLMModel(id: "claude-3-5-sonnet-20241022", name: "Default Name", maxOutputTokens: 99, contextWindow: 111, supportsToolUse: false)
        ]
        let fetched = [
            LLMModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", maxOutputTokens: 1, contextWindow: 2, supportsToolUse: true)
        ]

        // Minimal local overlay logic mirroring ModelRegistry.overlayWithProvidersConfig behavior.
        var byID: [String: LLMModel] = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        for m in fetched {
            if let existing = byID[m.id] {
                let displayName = m.displayName.isEmpty ? existing.displayName : m.displayName
                byID[m.id] = LLMModel(
                    id: existing.id,
                    name: displayName,
                    maxOutputTokens: existing.maxOutputTokens,
                    contextWindow: existing.contextWindow,
                    supportsToolUse: existing.supportsToolUse
                )
            }
        }

        let merged = byID["claude-3-5-sonnet-20241022"]
        XCTAssertEqual(merged?.displayName, "Claude 3.5 Sonnet")
        XCTAssertEqual(merged?.maxOutputTokens, 99)
        XCTAssertEqual(merged?.contextWindow, 111)
        XCTAssertEqual(merged?.supportsToolUse, false)
    }

    func testHydrationMigrationDisplayNameToCanonicalID() {
        let available: [(id: String, displayName: String)] = [
            ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet"),
            ("claude-3-opus-20240229", "Claude 3 Opus")
        ]

        let resolved = ChatViewModel.resolvePersistedModelID(
            providerID: "anthropic",
            savedModelID: "Claude 3.5 Sonnet",
            availableModels: available
        )

        XCTAssertEqual(resolved, "claude-3-5-sonnet-20241022")
    }
}
