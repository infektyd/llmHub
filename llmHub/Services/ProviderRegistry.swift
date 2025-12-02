//
//  ProviderRegistry.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

/// A registry for managing available LLM providers.
final class ProviderRegistry {
    /// Dictionary of registered providers, keyed by their ID.
    private let providers: [String: any LLMProvider]

    /// Initializes a new `ProviderRegistry`.
    /// - Parameter providerBuilders: Closures that create the provider instances.
    init(providerBuilders: [() -> any LLMProvider]) {
        let resolved = providerBuilders.map { $0() }
        self.providers = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
    }

    /// Retrieves a specific provider by its ID.
    /// - Parameter id: The unique identifier of the provider.
    /// - Returns: The requested `LLMProvider`.
    /// - Throws: `RegistryError.providerMissing` if the provider is not found.
    func provider(for id: String) throws -> any LLMProvider {
        guard let provider = providers[id] else {
            throw RegistryError.providerMissing
        }
        return provider
    }

    /// Returns a list of all registered providers.
    var availableProviders: [any LLMProvider] {
        Array(providers.values)
    }
}

/// Errors related to the provider registry.
enum RegistryError: Error {
    /// The requested provider could not be found.
    case providerMissing
}
