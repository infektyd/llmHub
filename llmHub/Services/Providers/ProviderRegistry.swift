//
//  ProviderRegistry.swift
//  llmHub
//
//  Created by AI Assistant on 12/13/25.
//

import Foundation
import OSLog

/// A registry for managing available LLM providers.
final class ProviderRegistry {
    private let logger = Logger(subsystem: "com.llmhub", category: "ProviderRegistry")

    /// Dictionary of registered providers, keyed by their CANONICAL ID.
    private let providers: [String: any LLMProvider]

    /// Alias mapping for persisted/legacy IDs → canonical IDs.
    private let aliasToCanonicalID: [String: String]

    /// Initializes a new `ProviderRegistry`.
    init(providerBuilders: [() -> any LLMProvider]) {
        var canonicalProviders: [String: any LLMProvider] = [:]
        var aliases: [String: String] = [:]

        // 1. Register Built-in Legacy Aliases first
        for (aliasKey, canonical) in ProviderID.legacyAliasesByLookupKey {
            aliases[aliasKey] = canonical
        }

        // 2. Resolve and Register Providers
        for builder in providerBuilders {
            let provider = builder()
            let canonicalID = ProviderID.canonicalID(from: provider.id)

            // Register provider
            canonicalProviders[canonicalID] = provider

            // Register self-alias (canonical -> canonical)
            aliases[ProviderID.lookupKey(from: canonicalID)] = canonicalID

            // Register name alias (e.g. "OpenAI" -> "openai")
            let nameKey = ProviderID.lookupKey(from: provider.name)
            aliases[nameKey] = canonicalID

            // Register raw ID alias (e.g. "OpenAI" -> "openai")
            let rawKey = ProviderID.lookupKey(from: provider.id)
            aliases[rawKey] = canonicalID

            Logger(subsystem: "com.llmhub", category: "ProviderRegistry").info(
                "Registered provider: \(provider.name) (ID: \(provider.id)) -> Canonical: \(canonicalID)"
            )
        }

        self.providers = canonicalProviders
        self.aliasToCanonicalID = aliases

        self.logger.info("Registry initialized with \(canonicalProviders.count) providers.")
    }

    /// Retrieves a specific provider by its ID with robust fallback.
    func provider(for id: String) throws -> any LLMProvider {
        let requestedKey = ProviderID.lookupKey(from: id)

        // 1. Try Fast Lookup via Alias Map
        if let canonicalID = aliasToCanonicalID[requestedKey],
            let provider = providers[canonicalID]
        {
            return provider
        }

        // 2. Try Direct Canonical Lookup
        let canonicalFromRaw = ProviderID.canonicalID(from: id)
        if let provider = providers[canonicalFromRaw] {
            return provider
        }

        // 3. Fail-Safe Scan (O(N) fallback for weird edge cases)
        for (key, provider) in providers {
            if key.caseInsensitiveCompare(id) == .orderedSame {
                return provider
            }
            if provider.name.caseInsensitiveCompare(id) == .orderedSame {
                return provider
            }
        }

        // 4. Failure
        let available = providers.keys.sorted()
        logger.error(
            "Provider lookup failed for id='\(id)'. Available: \(available.joined(separator: ", "))"
        )
        throw RegistryError.providerMissing(requestedID: id, availableIDs: available)
    }

    /// Resolves a raw/persisted provider ID to a canonical ID.
    func canonicalProviderID(for rawID: String) -> String? {
        let key = ProviderID.lookupKey(from: rawID)
        if let mapped = aliasToCanonicalID[key] { return mapped }

        // Fallback: Check if rawID matches any canonical key directly
        let canonical = ProviderID.canonicalID(from: rawID)
        return providers.keys.contains(canonical) ? canonical : nil
    }

    var availableProviders: [any LLMProvider] {
        Array(providers.values).sorted { $0.name < $1.name }
    }
}

enum RegistryError: LocalizedError {
    case providerMissing(requestedID: String, availableIDs: [String])

    var errorDescription: String? {
        switch self {
        case .providerMissing(let requestedID, let availableIDs):
            return
                "Provider '\(requestedID)' not found. Installed: \(availableIDs.joined(separator: ", "))"
        }
    }
}

// MARK: - Provider ID Canonicalization

enum ProviderID {
    static let legacyAliasesByLookupKey: [String: String] = [
        "openai": "openai",
        "anthropic": "anthropic",
        "claude": "anthropic",
        "google": "google",
        "googleai": "google",
        "gemini": "google",
        "mistral": "mistral",
        "xai": "xai",
        "grok": "xai",
        "openrouter": "openrouter",
    ]

    static func lookupKey(from raw: String) -> String {
        raw.lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func canonicalID(from raw: String) -> String {
        let key = lookupKey(from: raw)
        return legacyAliasesByLookupKey[key] ?? key
    }
}
