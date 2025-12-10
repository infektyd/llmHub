//
//  ModelRegistry.swift
//  llmHub
//
//  Created by AI Assistant on 12/07/25.
//

import Foundation
import Combine
import OSLog

/// Central service for managing and fetching available LLM models across all providers.
///
/// The ModelRegistry is responsible for:
/// - Fetching models from providers that have API keys configured
/// - Caching fetched models to avoid unnecessary API calls
/// - Providing curated model lists for providers without model endpoints
/// - Gracefully handling fetch failures with fallback to cached or default models
/// - Observing settings changes to refresh models when API keys change
@MainActor
final class ModelRegistry: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Dictionary mapping provider IDs to their available models
    @Published private(set) var modelsByProvider: [String: [LLMModel]] = [:]
    
    /// Indicates if models are currently being fetched
    @Published private(set) var isFetching: Bool = false
    
    /// The last time models were successfully fetched
    @Published private(set) var lastFetchDate: Date?
    
    /// Errors that occurred during the most recent fetch attempt
    @Published private(set) var fetchErrors: [String: Error] = [:]
    
    // MARK: - Private Properties
    
    private let keychainStore = KeychainStore()
    private let fetchService = ModelFetchService()
    private let logger = Logger(subsystem: "com.llmhub.app", category: "ModelRegistry")
    private var cancellables = Set<AnyCancellable>()
    
    /// Cache of fetched models with timestamps
    private var modelCache: [String: (models: [LLMModel], fetchedAt: Date)] = [:]
    
    /// Time interval after which cached models should be refreshed (24 hours)
    private let cacheExpiration: TimeInterval = 24 * 60 * 60
    
    // MARK: - Initialization
    
    init() {
        // Load cached models from UserDefaults on init
        loadCachedModels()
    }
    
    // MARK: - Public Methods
    
    /// Fetches models for all providers with configured API keys.
    /// - Parameter forceRefresh: If true, bypasses cache even if not expired
    func fetchAllModels(forceRefresh: Bool = false) async {
        guard !isFetching else {
            logger.info("Model fetch already in progress, skipping")
            return
        }
        
        isFetching = true
        fetchErrors = [:]
        
        logger.info("Starting model fetch for all configured providers")
        
        // Get all providers with API keys
        let configuredProviders = getConfiguredProviders()
        
        if configuredProviders.isEmpty {
            logger.warning("No providers configured with API keys")
            isFetching = false
            return
        }
        
        // Fetch models for each provider
        await withTaskGroup(of: (String, Result<[LLMModel], Error>).self) { group in
            for provider in configuredProviders {
                group.addTask {
                    do {
                        let models = try await self.fetchModelsForProvider(provider, forceRefresh: forceRefresh)
                        return (provider.rawValue, .success(models))
                    } catch {
                        return (provider.rawValue, .failure(error))
                    }
                }
            }
            
            // Collect results
            for await (providerID, result) in group {
                switch result {
                case .success(let models):
                    modelsByProvider[providerID] = models
                    modelCache[providerID] = (models, Date())
                    logger.info("Successfully fetched \(models.count) models for \(providerID)")
                    
                case .failure(let error):
                    fetchErrors[providerID] = error
                    logger.error("Failed to fetch models for \(providerID): \(error.localizedDescription)")
                    
                    // Use cached models if available
                    if let cached = modelCache[providerID] {
                        modelsByProvider[providerID] = cached.models
                        logger.info("Using cached models for \(providerID)")
                    }
                }
            }
        }
        
        lastFetchDate = Date()
        isFetching = false
        
        // Persist cache to UserDefaults
        saveCachedModels()
        
        logger.info("Model fetch complete. Providers loaded: \(modelsByProvider.keys.joined(separator: ", "))")
    }
    
    /// Fetches models for a specific provider.
    /// - Parameters:
    ///   - provider: The provider to fetch models for
    ///   - forceRefresh: If true, bypasses cache even if not expired
    /// - Returns: Array of available models
    func fetchModelsForProvider(_ provider: KeychainStore.ProviderKey, forceRefresh: Bool = false) async throws -> [LLMModel] {
        let providerID = provider.rawValue
        
        // Check if API key exists
        guard keychainStore.apiKey(for: provider) != nil else {
            logger.warning("No API key configured for \(providerID)")
            throw ModelRegistryError.noAPIKey
        }
        
        // Check cache if not forcing refresh
        if !forceRefresh, let cached = modelCache[providerID] {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if age < cacheExpiration {
                logger.info("Using cached models for \(providerID) (age: \(Int(age))s)")
                return cached.models
            }
        }
        
        // Fetch from service
        logger.info("Fetching fresh models for \(providerID)")
        let models = try await fetchService.fetchModels(for: provider)
        
        return models
    }
    
    /// Gets available models for a specific provider.
    /// - Parameter providerID: The provider identifier
    /// - Returns: Array of models, or empty array if none available
    func models(for providerID: String) -> [LLMModel] {
        return modelsByProvider[providerID] ?? []
    }
    
    /// Checks if a provider has models available.
    /// - Parameter providerID: The provider identifier
    /// - Returns: True if models are available
    func hasModels(for providerID: String) -> Bool {
        return !(modelsByProvider[providerID]?.isEmpty ?? true)
    }
    
    /// Gets all provider IDs that have models available.
    /// - Returns: Array of provider IDs
    func availableProviders() -> [String] {
        return Array(modelsByProvider.keys).sorted()
    }
    
    /// Clears cached models for a specific provider.
    /// - Parameter providerID: The provider identifier
    func clearCache(for providerID: String) {
        modelCache.removeValue(forKey: providerID)
        modelsByProvider.removeValue(forKey: providerID)
        saveCachedModels()
        logger.info("Cleared cache for \(providerID)")
    }
    
    /// Clears all cached models.
    func clearAllCaches() {
        modelCache.removeAll()
        modelsByProvider.removeAll()
        saveCachedModels()
        logger.info("Cleared all model caches")
    }
    
    // MARK: - Private Methods
    
    /// Gets all providers that have API keys configured.
    private func getConfiguredProviders() -> [KeychainStore.ProviderKey] {
        return KeychainStore.ProviderKey.allCases.filter { provider in
            keychainStore.apiKey(for: provider) != nil
        }
    }
    
    /// Loads cached models from UserDefaults.
    private func loadCachedModels() {
        guard let data = UserDefaults.standard.data(forKey: "ModelRegistryCache"),
              let cache = try? JSONDecoder().decode([String: CachedModels].self, from: data) else {
            logger.info("No cached models found in UserDefaults")
            return
        }
        
        for (providerID, cached) in cache {
            modelCache[providerID] = (cached.models, cached.fetchedAt)
            modelsByProvider[providerID] = cached.models
        }
        
        logger.info("Loaded cached models for \(cache.count) providers")
    }
    
    /// Saves cached models to UserDefaults.
    private func saveCachedModels() {
        let cache = modelCache.mapValues { CachedModels(models: $0.models, fetchedAt: $0.fetchedAt) }
        
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: "ModelRegistryCache")
            logger.info("Saved model cache to UserDefaults")
        }
    }
}

// MARK: - Supporting Types

/// Represents cached models with their fetch timestamp.
private struct CachedModels: Codable {
    let models: [LLMModel]
    let fetchedAt: Date
}

/// Errors specific to the ModelRegistry.
enum ModelRegistryError: LocalizedError {
    case noAPIKey
    case fetchFailed(underlying: Error)
    case providerNotSupported
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured for this provider"
        case .fetchFailed(let error):
            return "Failed to fetch models: \(error.localizedDescription)"
        case .providerNotSupported:
            return "Provider is not supported"
        }
    }
}

// MARK: - LLMModel Codable Extension

extension LLMModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id, displayName, contextWindow, supportsToolUse, maxOutputTokens
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        contextWindow = try container.decode(Int.self, forKey: .contextWindow)
        supportsToolUse = try container.decode(Bool.self, forKey: .supportsToolUse)
        maxOutputTokens = try container.decode(Int.self, forKey: .maxOutputTokens)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(contextWindow, forKey: .contextWindow)
        try container.encode(supportsToolUse, forKey: .supportsToolUse)
        try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
    }
}
