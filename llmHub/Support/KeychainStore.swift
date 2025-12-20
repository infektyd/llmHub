//  KeychainStore.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import LocalAuthentication
import OSLog
import Security

final class KeychainStore: Sendable {
    enum ProviderKey: String, CaseIterable {
        case openai
        case anthropic
        case google
        case mistral
        case xai
        case openrouter
    }

    private static let service = "com.llmhub.keys"
    private nonisolated let logger = Logger(subsystem: "com.llmhub", category: "KeychainStore")
    private let backend: KeychainBacking
    private let accessGroupsOverride: [String]?

    init(backend: KeychainBacking = SystemKeychainBacking(), accessGroups: [String]? = nil) {
        self.backend = backend
        self.accessGroupsOverride = accessGroups
    }

    func updateKey(_ key: String?, for provider: ProviderKey) async throws {
        logDiagnosticsOnce(for: provider)
        guard let data = key?.data(using: .utf8) else {
            try await deleteKeys(for: provider, includeLegacy: true)
            return
        }
        
        // Delete existing items first to keep storage deterministic.
        try? await deleteKeys(for: provider, includeLegacy: true)
        
        let status = addOrUpdateKey(
            data: data,
            account: provider.rawValue,
            accessGroup: primaryAccessGroup
        )
        
        if status != errSecSuccess {
            logKeychainError(
                status,
                operation: "add",
                service: Self.service,
                account: provider.rawValue,
                accessGroup: primaryAccessGroup
            )
            throw KeychainError.operationFailed(status)
        }
    }

    func apiKey(for provider: ProviderKey) async -> String? {
        logDiagnosticsOnce(for: provider)
        if let key = readKey(
            service: Self.service,
            account: provider.rawValue,
            accessGroup: primaryAccessGroup
        ) {
            return key
        }

        return migrateKeyIfNeeded(for: provider)
    }

    private func deleteKeys(for provider: ProviderKey, includeLegacy: Bool) async throws {
        let accounts = includeLegacy
            ? [provider.rawValue] + provider.legacyAccounts
            : [provider.rawValue]
        for account in accounts.uniquePreservingOrder() {
            for accessGroup in accessGroupCandidates(includeNilFallback: true) {
                var query = baseQuery(
                    service: Self.service,
                    account: account,
                    accessGroup: accessGroup
                )
                let context = LAContext()
                context.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = context

                let status = backend.delete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    logKeychainError(
                        status,
                        operation: "delete",
                        service: Self.service,
                        account: account,
                        accessGroup: accessGroup
                    )
                    throw KeychainError.operationFailed(status)
                }
            }
        }
    }

    func baseQuery(for provider: ProviderKey, accessGroup: String? = nil) -> [String: Any] {
        baseQuery(
            service: Self.service,
            account: provider.rawValue,
            accessGroup: accessGroup ?? primaryAccessGroup
        )
    }

    private func baseQuery(service: String, account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func readKey(service: String, account: String, accessGroup: String?) -> String? {
        var query = baseQuery(service: service, account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        var item: CFTypeRef?
        let status = backend.copyMatching(query as CFDictionary, result: &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logKeychainError(
                    status,
                    operation: "read",
                    service: service,
                    account: account,
                    accessGroup: accessGroup
                )
            }
            return nil
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func addOrUpdateKey(data: Data, account: String, accessGroup: String?) -> OSStatus {
        var query = baseQuery(service: Self.service, account: account, accessGroup: accessGroup)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data

        let status = backend.add(query as CFDictionary)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            return backend.update(query as CFDictionary, attributes: attributes as CFDictionary)
        }

        return status
    }

    private func migrateKeyIfNeeded(for provider: ProviderKey) -> String? {
        let legacyAccounts = provider.legacyAccounts.filter { $0 != provider.rawValue }
        guard !legacyAccounts.isEmpty else { return nil }

        for account in legacyAccounts {
            for accessGroup in accessGroupCandidates(includeNilFallback: true) {
                if let legacyKey = readKey(
                    service: Self.service,
                    account: account,
                    accessGroup: accessGroup
                ) {
                    let status = addOrUpdateKey(
                        data: Data(legacyKey.utf8),
                        account: provider.rawValue,
                        accessGroup: primaryAccessGroup
                    )
                    if status != errSecSuccess {
                        logKeychainError(
                            status,
                            operation: "migrate",
                            service: Self.service,
                            account: provider.rawValue,
                            accessGroup: primaryAccessGroup
                        )
                        return legacyKey
                    }

                    _ = try? deleteLegacyKey(
                        service: Self.service,
                        account: account,
                        accessGroup: accessGroup
                    )
#if DEBUG
                    logger.debug(
                        "Keychain migration: moved legacy account=\(account, privacy: .public) to account=\(provider.rawValue, privacy: .public)"
                    )
#endif
                    return legacyKey
                }
            }
        }

        return nil
    }

    private func deleteLegacyKey(service: String, account: String, accessGroup: String?) throws {
        var query = baseQuery(service: service, account: account, accessGroup: accessGroup)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = backend.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }

    private var accessGroups: [String] {
        if let accessGroupsOverride = accessGroupsOverride {
            return accessGroupsOverride
        }
        return configuredAccessGroups()
    }

    private var primaryAccessGroup: String? {
        accessGroups.first
    }

    private func accessGroupCandidates(includeNilFallback: Bool) -> [String?] {
        var candidates = accessGroups.map { Optional($0) }
        if includeNilFallback || candidates.isEmpty {
            candidates.append(nil)
        }
        return candidates.uniquePreservingOrder()
    }

    private func configuredAccessGroups() -> [String] {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil as CFAllocator?) else { return [] }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "keychain-access-groups" as CFString,
            nil
        )
        return entitlement as? [String] ?? []
        #else
        // On iOS, tvOS, watchOS, visionOS - read from entitlements via Bundle
        guard let entitlements = Bundle.main.object(forInfoDictionaryKey: "keychain-access-groups") as? [String] else {
            return []
        }
        return entitlements
        #endif
    }

    private func logDiagnosticsOnce(for provider: ProviderKey) {
#if DEBUG
        Self.diagnosticsLock.lock()
        defer { Self.diagnosticsLock.unlock() }
        guard !Self.didLogDiagnostics else { return }
        Self.didLogDiagnostics = true

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let isHelper = bundleID.localizedCaseInsensitiveContains("llmhubhelper")
        let groups = accessGroups
        let groupsSummary = groups.isEmpty ? "(none)" : groups.joined(separator: ",")
        logger.debug(
            "Keychain diagnostics: bundleID=\(bundleID, privacy: .public) isHelper=\(isHelper, privacy: .public) accessGroups=\(groupsSummary, privacy: .public) service=\(Self.service, privacy: .public) account=\(provider.rawValue, privacy: .public)"
        )
#endif
    }

    private func logKeychainError(
        _ status: OSStatus,
        operation: String,
        service: String,
        account: String,
        accessGroup: String?
    ) {
        let message = KeychainError.operationFailed(status).errorDescription ?? "Unknown error"
        logger.error(
            "Keychain \(operation, privacy: .public) failed service=\(service, privacy: .public) account=\(account, privacy: .public) accessGroup=\(accessGroup ?? "(none)", privacy: .public) status=\(status, privacy: .public) message=\(message, privacy: .public)"
        )
    }

    private static var didLogDiagnostics = false
    private static let diagnosticsLock = NSLock()
}

private extension KeychainStore.ProviderKey {
    var legacyAccounts: [String] {
        switch self {
        case .openai:
            return ["openAI", "OpenAI"]
        case .openrouter:
            return ["openRouter", "OpenRouter"]
        case .anthropic:
            return ["Anthropic"]
        case .google:
            return ["Google", "googleAI", "GoogleAI"]
        case .mistral:
            return ["Mistral"]
        case .xai:
            return ["XAI", "xAI"]
        }
    }
}

enum KeychainError: LocalizedError {
    case operationFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            let hint: String
            switch status {
            case errSecMissingEntitlement:
                hint = "Missing keychain entitlement or access-group mismatch."
            case errSecAuthFailed:
                hint = "Authentication failed or keychain requires user interaction."
            case errSecInteractionNotAllowed:
                hint = "Interaction not allowed; keychain may be locked or UI disallowed."
            default:
                hint = ""
            }
            return hint.isEmpty
                ? "Keychain operation failed (\(status)): \(message)"
                : "Keychain operation failed (\(status)): \(message). \(hint)"
        }
    }
}

protocol KeychainBacking: Sendable {
    func add(_ query: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
}

struct SystemKeychainBacking: KeychainBacking {
    func add(_ query: CFDictionary) -> OSStatus {
        SecItemAdd(query, nil as UnsafeMutablePointer<CFTypeRef?>?)
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }
}

final class InMemoryKeychainBacking: KeychainBacking, @unchecked Sendable {
    struct Key: Hashable {
        let service: String
        let account: String
        let accessGroup: String?
    }

    private var storage: [Key: Data] = [:]

    func add(_ query: CFDictionary) -> OSStatus {
        let dict = query as NSDictionary
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String,
            let data = dict[kSecValueData as String] as? Data
        else {
            return errSecParam
        }
        let accessGroup = dict[kSecAttrAccessGroup as String] as? String
        let key = Key(service: service, account: account, accessGroup: accessGroup)
        if storage[key] != nil {
            return errSecDuplicateItem
        }
        storage[key] = data
        return errSecSuccess
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let dict = query as NSDictionary
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String
        else {
            return errSecParam
        }
        let accessGroup = dict[kSecAttrAccessGroup as String] as? String
        let key = Key(service: service, account: account, accessGroup: accessGroup)
        guard let data = storage[key] else {
            return errSecItemNotFound
        }
        result?.pointee = data as CFTypeRef
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        let dict = query as NSDictionary
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String
        else {
            return errSecParam
        }
        let accessGroup = dict[kSecAttrAccessGroup as String] as? String
        let key = Key(service: service, account: account, accessGroup: accessGroup)
        if storage.removeValue(forKey: key) != nil {
            return errSecSuccess
        }
        return errSecItemNotFound
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let queryDict = query as NSDictionary
        let attributesDict = attributes as NSDictionary
        guard
            let service = queryDict[kSecAttrService as String] as? String,
            let account = queryDict[kSecAttrAccount as String] as? String,
            let data = attributesDict[kSecValueData as String] as? Data
        else {
            return errSecParam
        }
        let accessGroup = queryDict[kSecAttrAccessGroup as String] as? String
        let key = Key(service: service, account: account, accessGroup: accessGroup)
        guard storage[key] != nil else {
            return errSecItemNotFound
        }
        storage[key] = data
        return errSecSuccess
    }

    func value(service: String, account: String, accessGroup: String?) -> Data? {
        storage[Key(service: service, account: account, accessGroup: accessGroup)]
    }
}

private extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
