//
//  ProviderRegistry.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

final class ProviderRegistry {
    private let providers: [String: any LLMProvider]

    init(providerBuilders: [() -> any LLMProvider]) {
        let resolved = providerBuilders.map { $0() }
        self.providers = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
    }

    func provider(for id: String) throws -> any LLMProvider {
        guard let provider = providers[id] else {
            throw RegistryError.providerMissing
        }
        return provider
    }

    var availableProviders: [any LLMProvider] {
        Array(providers.values)
    }
}

enum RegistryError: Error {
    case providerMissing
}
