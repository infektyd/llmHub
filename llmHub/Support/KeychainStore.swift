//  KeychainStore.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import LocalAuthentication

final class KeychainStore: @unchecked Sendable {
    enum ProviderKey: String, CaseIterable {
        case openAI
        case anthropic
        case google
        case mistral
        case xai
        case openRouter
    }

    func updateKey(_ key: String?, for provider: ProviderKey) throws {
        guard let data = key?.data(using: .utf8) else {
            try deleteKey(for: provider)
            return
        }
        var query = baseQuery(for: provider)
        var access: SecAccessControl?
        #if os(iOS)
        access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet], nil)
        #else
        access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet], nil)
        #endif

        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = data
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery(for: provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.operationFailed(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.operationFailed(status)
        }
    }

    func apiKey(for provider: ProviderKey) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKey(for provider: ProviderKey) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }

    private func baseQuery(for provider: ProviderKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrService as String: "com.llmhub.keys",
            kSecUseAuthenticationContext as String: authenticationContext
        ]
    }

    private var authenticationContext: LAContext {
        let context = LAContext()
        context.localizedReason = "Access stored API key"
        return context
    }
}

enum KeychainError: Error {
    case operationFailed(OSStatus)
}
