//
//  ModelsDevService.swift
//  llmHub
//
//  Fetches model metadata from models.dev API
//  API: https://models.dev/api.json
//

import Foundation
import OSLog

/// Service for fetching model metadata from models.dev API
/// Provides cached access to the model database with 1-hour expiration
actor ModelsDevService {

    static let shared = ModelsDevService()

    private let apiURL = URL(string: "https://models.dev/api.json")!
    private let logger = Logger(subsystem: "com.llmhub.app", category: "ModelsDevService")
    private var cache: ModelsDevCache?
    private let cacheExpiration: TimeInterval = 3600 // 1 hour

    struct ModelsDevCache {
        let data: [String: [ModelsDevModel]]  // provider -> models
        let fetchedAt: Date

        var isExpired: Bool {
            Date().timeIntervalSince(fetchedAt) > 3600
        }
    }

    // MARK: - Public API

    /// Fetch all models from models.dev API
    /// Returns a dictionary mapping provider names to their models
    /// Uses cached data if available and not expired
    func fetchAllModels() async throws -> [String: [ModelsDevModel]] {
        // Check cache first
        if let cache = cache, !cache.isExpired {
            logger.info("Using cached models.dev data (\(cache.data.count) providers)")
            return cache.data
        }

        logger.info("Fetching fresh data from models.dev API")

        do {
            let (data, response) = try await LLMURLSession.data(from: apiURL)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ModelsDevError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("models.dev API returned status \(httpResponse.statusCode)")
                throw ModelsDevError.httpError(httpResponse.statusCode)
            }

            // Decode the API response - structure is [String: ModelsDevProvider]
            let apiResponse = try JSONDecoder().decode([String: ModelsDevProvider].self, from: data)

            // Convert to [String: [ModelsDevModel]] by extracting models from each provider
            let providersData = apiResponse.mapValues { provider in
                Array(provider.models.values)
            }

            // Cache the results
            cache = ModelsDevCache(
                data: providersData,
                fetchedAt: Date()
            )

            let totalModels = providersData.values.reduce(0) { $0 + $1.count }
            logger.info("Fetched \(totalModels) models from \(providersData.count) providers via models.dev")

            return providersData

        } catch let error as DecodingError {
            logger.error("Failed to decode models.dev response: \(error.localizedDescription)")
            throw ModelsDevError.decodingFailed(error)
        } catch {
            logger.error("Failed to fetch from models.dev: \(error.localizedDescription)")
            throw ModelsDevError.networkError(error)
        }
    }

    /// Fetch models for a specific provider
    /// - Parameter provider: Provider name (e.g., "anthropic", "openai", "google")
    /// - Returns: Array of models for that provider
    func fetchModels(for provider: String) async throws -> [ModelsDevModel] {
        let allModels = try await fetchAllModels()

        // Try exact match first
        if let models = allModels[provider.lowercased()] {
            logger.info("Found \(models.count) models for '\(provider)' from models.dev")
            return models
        }

        // Try case-insensitive search
        for (key, models) in allModels {
            if key.lowercased() == provider.lowercased() {
                logger.info("Found \(models.count) models for '\(provider)' from models.dev (case-insensitive match)")
                return models
            }
        }

        logger.warning("No models found for provider '\(provider)' in models.dev")
        return []
    }

    /// Clear the cache
    /// Useful for forcing a refresh or when testing
    func clearCache() {
        logger.info("Clearing models.dev cache")
        cache = nil
    }
}

// MARK: - Errors

enum ModelsDevError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingFailed(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from models.dev API"
        case .httpError(let code):
            return "HTTP error \(code) from models.dev API"
        case .decodingFailed(let error):
            return "Failed to decode models.dev response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error fetching from models.dev: \(error.localizedDescription)"
        }
    }
}
