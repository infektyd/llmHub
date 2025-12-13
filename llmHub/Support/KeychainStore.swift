//  KeychainStore.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import LocalAuthentication

final class KeychainStore: Sendable {
    enum ProviderKey: String, CaseIterable {
        case openAI
        case anthropic
        case google
        case mistral
        case xai
        case openRouter
    }

    func updateKey(_ key: String?, for provider: ProviderKey) async throws {
        try await Task.detached {
            guard let data = key?.data(using: .utf8) else {
                try await self.deleteKey(for: provider)
                return
            }
            
            // First, try to delete existing item
            try? await self.deleteKey(for: provider)
            
            var query = self.baseQuery(for: provider)
            
            // Simplified security: Use standard attribute security instead of SecAccessControl
            // This is more robust across Simulators/macOS/iOS for basic API key storage.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            query[kSecValueData as String] = data

            let status = SecItemAdd(query as CFDictionary, nil)
            
            if status != errSecSuccess {
                throw KeychainError.operationFailed(status)
            }
        }.value
    }

    func apiKey(for provider: ProviderKey) async -> String? {
        await Task.detached {
            var query = self.baseQuery(for: provider)
            query[kSecReturnData as String] = kCFBooleanTrue
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }

    private func deleteKey(for provider: ProviderKey) async throws {
        try await Task.detached {
            let status = SecItemDelete(self.baseQuery(for: provider) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.operationFailed(status)
            }
        }.value
    }

    nonisolated private func baseQuery(for provider: ProviderKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrService as String: "com.llmhub.keys"
            // Removed kSecUseAuthenticationContext to let system handle UI prompt if needed
        ]
    }

    nonisolated private var authenticationContext: LAContext {
        let context = LAContext()
        context.localizedReason = "Access stored API key"
        return context
    }
}

enum KeychainError: LocalizedError {
    case operationFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            return "Keychain operation failed with status: \(status)"
        }
    }
}
