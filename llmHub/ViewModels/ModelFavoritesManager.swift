//
//  ModelFavoritesManager.swift
//  llmHub
//
//  Created by AI Assistant on 12/09/25.
//

import Foundation
import SwiftUI

/// Manages user's favorite models with persistence using UserDefaults.
@Observable
final class ModelFavoritesManager {

    // MARK: - Properties

    /// Set of favorite model IDs
    private(set) var favoriteModelIDs: Set<String> = []

    private let userDefaultsKey = "favoriteModels"

    // MARK: - Initialization

    init() {
        loadFavorites()
    }

    // MARK: - Public Methods

    /// Checks if a model is marked as favorite.
    /// - Parameter modelID: The model ID to check
    /// - Returns: True if the model is a favorite
    func isFavorite(modelID: String) -> Bool {
        return favoriteModelIDs.contains(modelID)
    }

    /// Adds a model to favorites.
    /// - Parameter modelID: The model ID to add
    func addFavorite(modelID: String) {
        favoriteModelIDs.insert(modelID)
        saveFavorites()
    }

    /// Removes a model from favorites.
    /// - Parameter modelID: The model ID to remove
    func removeFavorite(modelID: String) {
        favoriteModelIDs.remove(modelID)
        saveFavorites()
    }

    /// Toggles favorite status for a model.
    /// - Parameter modelID: The model ID to toggle
    func toggleFavorite(modelID: String) {
        if isFavorite(modelID: modelID) {
            removeFavorite(modelID: modelID)
        } else {
            addFavorite(modelID: modelID)
        }
    }

    /// Clears all favorites.
    func clearAllFavorites() {
        favoriteModelIDs.removeAll()
        saveFavorites()
    }

    // MARK: - Private Methods

    /// Loads favorites from UserDefaults.
    private func loadFavorites() {
        if let data = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            favoriteModelIDs = Set(data)
        }
    }

    /// Saves favorites to UserDefaults.
    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteModelIDs), forKey: userDefaultsKey)
    }
}
