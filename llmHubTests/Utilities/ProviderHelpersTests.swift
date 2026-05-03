import XCTest
import Foundation
@testable import llmHub

final class ProviderHelpersTests: XCTestCase {

    // MARK: - stableUUID(for:) Tests

    func testStableUUIDIsDeterministic() {
        let inputString = "openai-gpt-4o"

        let uuid1 = stableUUID(for: inputString)
        let uuid2 = stableUUID(for: inputString)
        let uuid3 = stableUUID(for: inputString)

        XCTAssertEqual(uuid1, uuid2, "Multiple calls with the same input should produce identical UUIDs")
        XCTAssertEqual(uuid1, uuid3, "Multiple calls with the same input should produce identical UUIDs")
        XCTAssertEqual(uuid1.uuidString, "E21A4AE2-921C-5FEA-BA8B-56D2DE380489", "Should match expected MD5-derived UUID string")
    }

    func testStableUUIDProducesDifferentUUIDsForDifferentInputs() {
        let uuid1 = stableUUID(for: "provider-A")
        let uuid2 = stableUUID(for: "provider-B")

        XCTAssertNotEqual(uuid1, uuid2, "Different input strings should produce different UUIDs")
    }

    func testStableUUIDWithEmptyString() {
        let uuid1 = stableUUID(for: "")
        let uuid2 = stableUUID(for: "")

        XCTAssertEqual(uuid1, uuid2, "Empty string should produce deterministic UUID")
        XCTAssertEqual(uuid1.uuidString, "D41D8CD9-8F00-B204-E980-0998ECF8427E", "Empty string should match expected MD5 empty string hash")
    }

    // MARK: - providerDisplayName(for:) Tests

    func testProviderDisplayName() {
        XCTAssertEqual(providerDisplayName(for: "openai"), "OpenAI")
        XCTAssertEqual(providerDisplayName(for: "anthropic"), "Anthropic")
        XCTAssertEqual(providerDisplayName(for: "google"), "Google AI")
        XCTAssertEqual(providerDisplayName(for: "mistral"), "Mistral AI")
        XCTAssertEqual(providerDisplayName(for: "xai"), "xAI")
        XCTAssertEqual(providerDisplayName(for: "openrouter"), "OpenRouter")

        // Case insensitivity check
        XCTAssertEqual(providerDisplayName(for: "OPENAI"), "OpenAI")
        XCTAssertEqual(providerDisplayName(for: "Anthropic"), "Anthropic")

        // Unknown provider check
        XCTAssertEqual(providerDisplayName(for: "unknown"), "Unknown")
        XCTAssertEqual(providerDisplayName(for: "custom-provider"), "Custom-Provider")
    }

    // MARK: - providerIcon(for:) Tests

    func testProviderIcon() {
        XCTAssertEqual(providerIcon(for: "openai"), "sparkles")
        XCTAssertEqual(providerIcon(for: "anthropic"), "brain.head.profile")
        XCTAssertEqual(providerIcon(for: "google"), "cloud.fill")
        XCTAssertEqual(providerIcon(for: "mistral"), "wind")
        XCTAssertEqual(providerIcon(for: "xai"), "bolt.circle.fill")
        XCTAssertEqual(providerIcon(for: "openrouter"), "arrow.triangle.branch")

        // Case insensitivity check
        XCTAssertEqual(providerIcon(for: "OPENAI"), "sparkles")

        // Unknown provider check
        XCTAssertEqual(providerIcon(for: "unknown"), "cpu")
    }
}
