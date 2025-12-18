//
//  KeychainStoreTests.swift
//  llmHubTests
//
//  Created by AI Assistant on 12/20/25.
//

import Security
import XCTest

@testable import llmHub

@MainActor
final class KeychainStoreTests: XCTestCase {
    func testMigrationMovesLegacyAccountToCanonicalAccount() async {
        let backend = InMemoryKeychainBacking()
        let accessGroup = "TESTGROUP"
        let store = KeychainStore(backend: backend, accessGroups: [accessGroup])
        let legacyAccount = "openAI"
        let legacyData = Data("legacy-key".utf8)

        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.llmhub.keys",
            kSecAttrAccount as String: legacyAccount,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: legacyData,
        ]

        XCTAssertEqual(backend.add(legacyQuery as CFDictionary), errSecSuccess)

        let migrated = await store.apiKey(for: .openai)
        XCTAssertEqual(migrated, "legacy-key")
        XCTAssertEqual(
            backend.value(service: "com.llmhub.keys", account: "openai", accessGroup: accessGroup),
            legacyData
        )
        XCTAssertNil(
            backend.value(service: "com.llmhub.keys", account: legacyAccount, accessGroup: accessGroup)
        )
    }

    func testBaseQueryIncludesServiceAccountAndAccessGroup() {
        let backend = InMemoryKeychainBacking()
        let accessGroup = "TESTGROUP"
        let store = KeychainStore(backend: backend, accessGroups: [accessGroup])

        let query = store.baseQuery(for: .openai)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.llmhub.keys")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "openai")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, accessGroup)
    }
}
