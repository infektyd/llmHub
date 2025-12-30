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
    
    /// Time interval after which cached models should be refreshed (1 hour)
    /// Reduced from 24 hours to ensure fresh model data, especially for curated lists
    private let cacheExpiration: TimeInterval = 1 * 60 * 60
    
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
        
        logger.info("Starting model fetch for all providers")
        let providers = KeychainStore.ProviderKey.allCases
        
        // Fetch models for each provider
        await withTaskGroup(of: (String, Result<[LLMModel], Error>).self) { group in
            for provider in providers {
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
        
        logger.info("Model fetch complete. Providers loaded: \(self.modelsByProvider.keys.joined(separator: ", "))")
    }
    
    /// Fetches models for a specific provider.
    /// - Parameters:
    ///   - provider: The provider to fetch models for
    ///   - forceRefresh: If true, bypasses cache even if not expired
    /// - Returns: Array of available models
    func fetchModelsForProvider(_ provider: KeychainStore.ProviderKey, forceRefresh: Bool = false) async throws -> [LLMModel] {
        let providerID = provider.rawValue
        let canonicalProviderID = ProviderID.canonicalID(from: providerID)

        let hasAPIKey = (await keychainStore.apiKey(for: provider) != nil)

        // Compute cache age (if any)
        let cachedEntry = modelCache[providerID]
        let cacheAgeSeconds: Int? = cachedEntry.map { Int(Date().timeIntervalSince($0.fetchedAt)) }

        // Check cache if not forcing refresh
        if !forceRefresh, let cached = cachedEntry {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if age < cacheExpiration {
                logger.info("Using cached models for \(providerID) (age: \(Int(age))s)")
                return overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: cached.models)
            }
        }

        logger.info(
            "Fetching models for provider=\(providerID) canonical=\(canonicalProviderID) forceRefresh=\(forceRefresh) cacheAgeSeconds=\(cacheAgeSeconds ?? -1)"
        )

        // Curated defaults (baseline contract)
        let curatedDefaults = curatedModels(forCanonicalProviderID: canonicalProviderID)

        // Special handling: Anthropic and xAI should be official-first, then models.dev, then cached, then curated.
        if canonicalProviderID == "anthropic" || canonicalProviderID == "xai" {
            // 1) Official provider endpoint
            if hasAPIKey {
                do {
                    logger.info("Attempting official /models fetch for \(canonicalProviderID)")
                    let fetched = try await fetchService.fetchModels(for: provider)

                    if fetched.isEmpty {
                        logger.warning("Official /models fetch returned empty for \(canonicalProviderID); will fall back")
                    } else {
                        let merged = overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: fetched)
                        logger.info(
                            "✅ Using official models for \(canonicalProviderID): fetched=\(fetched.count) merged=\(merged.count)"
                        )
                        return merged
                    }
                } catch {
                    logger.warning("Official /models fetch failed for \(canonicalProviderID): \(error.localizedDescription)")
                }
            } else {
                logger.info("No API key for \(canonicalProviderID); skipping official /models fetch")
            }

            // 2) models.dev fallback
            do {
                logger.info("Attempting models.dev fetch for \(canonicalProviderID)")
                let modelsDevModels = try await ModelsDevService.shared.fetchModels(for: canonicalProviderID)
                if !modelsDevModels.isEmpty {
                    let fetched = modelsDevModels.map { $0.toLLMModel() }
                    let merged = overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: fetched)
                    logger.info(
                        "✅ Using models.dev for \(canonicalProviderID): fetched=\(fetched.count) merged=\(merged.count)"
                    )
                    return merged
                }
            } catch {
                logger.warning("models.dev fetch failed for \(canonicalProviderID): \(error.localizedDescription)")
            }

            // 3) cached (even if expired)
            if let cached = cachedEntry, !cached.models.isEmpty {
                let merged = overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: cached.models)
                logger.info(
                    "✅ Using cached fallback for \(canonicalProviderID): cached=\(cached.models.count) merged=\(merged.count)"
                )
                return merged
            }

            // 4) curated
            logger.info("📚 Using curated fallback for \(canonicalProviderID): \(curatedDefaults.count) models")
            return curatedDefaults
        }

        // Default providers: models.dev first, then provider fetch, then cache, then curated.

        // 1) models.dev
        do {
            logger.info("Attempting to fetch models for \(providerID) from models.dev")
            let modelsDevModels = try await ModelsDevService.shared.fetchModels(for: canonicalProviderID)
            if !modelsDevModels.isEmpty {
                let models = modelsDevModels.map { $0.toLLMModel() }
                logger.info("✅ Fetched \(models.count) models for \(providerID) from models.dev")
                return overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: models)
            } else {
                logger.info("No models found for \(providerID) in models.dev, falling back")
            }
        } catch {
            logger.warning(
                "Failed to fetch from models.dev for \(providerID): \(error.localizedDescription). Falling back"
            )
        }

        // 2) provider API
        if hasAPIKey {
            do {
                logger.info("Attempting provider API fetch for \(providerID)")
                let fetched = try await fetchService.fetchModels(for: provider)
                if !fetched.isEmpty {
                    return overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: fetched)
                }
            } catch {
                logger.warning("Provider API fetch failed for \(providerID): \(error.localizedDescription)")
            }
        } else {
            logger.info("No API key for \(providerID); skipping provider API fetch")
        }

        // 3) cached
        if let cached = cachedEntry, !cached.models.isEmpty {
            let merged = overlayWithProvidersConfig(providerID: canonicalProviderID, fetchedModels: cached.models)
            logger.info("Using cached fallback for \(providerID)")
            return merged
        }

        // 4) curated
        logger.info("📚 Using curated fallback for \(providerID): \(curatedDefaults.count) models")
        return curatedDefaults
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

        // Also clear models.dev cache
        Task {
            await ModelsDevService.shared.clearCache()
        }

        logger.info("Cleared all model caches (including models.dev)")
    }

    // MARK: - Overlay merge

    /// Merge fetched models onto curated defaults. Defaults win for numeric capability fields;
    /// fetched models may contribute new IDs and (optionally) better display names.
    private func overlayWithProvidersConfig(providerID: String, fetchedModels: [LLMModel]) -> [LLMModel] {
        let canonicalProviderID = ProviderID.canonicalID(from: providerID)
        let defaults = curatedModels(forCanonicalProviderID: canonicalProviderID)

        guard !defaults.isEmpty else {
            return fetchedModels
        }

        // Baseline capability policy for new models (conservative).
        let defaultContextWindow = defaults.map { $0.contextWindow }.max() ?? 128_000
        let defaultMaxOutput = min(defaults.map { $0.maxOutputTokens }.max() ?? 8_192, 16_384)
        let defaultSupportsTools = defaults.contains(where: { $0.supportsToolUse })

        var mergedByID: [String: LLMModel] = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        var newIDs: [String] = []

        for model in fetchedModels {
            if let existing = mergedByID[model.id] {
                let incomingName = model.displayName
                let finalName: String
                if shouldAdoptDisplayName(incomingName, forModelID: model.id, currentDisplayName: existing.displayName) {
                    finalName = incomingName
                } else {
                    finalName = existing.displayName
                }

                mergedByID[model.id] = LLMModel(
                    id: existing.id,
                    name: finalName,
                    maxOutputTokens: existing.maxOutputTokens,
                    contextWindow: existing.contextWindow,
                    supportsToolUse: existing.supportsToolUse
                )
            } else {
                let name = model.displayName.isEmpty ? model.id : model.displayName
                mergedByID[model.id] = LLMModel(
                    id: model.id,
                    name: name,
                    maxOutputTokens: defaultMaxOutput,
                    contextWindow: defaultContextWindow,
                    supportsToolUse: defaultSupportsTools
                )
                newIDs.append(model.id)
            }
        }

        // Deterministic ordering: curated defaults first, then new IDs alphabetically.
        var ordered: [LLMModel] = []
        ordered.reserveCapacity(mergedByID.count)

        for model in defaults {
            if let merged = mergedByID[model.id] {
                ordered.append(merged)
            }
        }

        for id in newIDs.sorted() {
            if let merged = mergedByID[id] {
                ordered.append(merged)
            }
        }

        return ordered
    }

    private func shouldAdoptDisplayName(_ incoming: String, forModelID id: String, currentDisplayName: String) -> Bool {
        let trimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Avoid replacing a nice curated name with a raw id.
        if ProviderID.lookupKey(from: trimmed) == ProviderID.lookupKey(from: id) {
            return false
        }
        return trimmed != currentDisplayName
    }

    private func curatedModels(forCanonicalProviderID providerID: String) -> [LLMModel] {
        let config = makeDefaultConfig()
        switch providerID {
        case "openai":
            return config.openAI.models
        case "anthropic":
            return config.anthropic.models
        case "google":
            return config.googleAI.models
        case "mistral":
            return config.mistral.models
        case "xai":
            return config.xai.models
        case "openrouter":
            return config.openRouter.models
        default:
            return []
        }
    }

    // MARK: - Private Methods
    
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
    case fetchFailed(underlying: Error)
    case providerNotSupported
    
    var errorDescription: String? {
        switch self {
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
