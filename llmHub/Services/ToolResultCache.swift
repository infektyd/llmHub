//
//  ToolResultCache.swift
//  llmHub
//
//  Session-scoped LRU cache for idempotent tool results.
//  Implemented as an actor for proper Swift 6 concurrency.
//

import Foundation

/// Actor-based, session-scoped cache for tool execution results.
/// Each ToolSession owns one ToolResultCache instance.
actor ToolResultCache {

    /// Internal cache entry wrapper.
    private struct CacheEntry: Sendable {
        let result: ToolResult
        let timestamp: Date
    }

    /// Maximum number of entries before eviction.
    private let maxCount: Int

    /// In-memory cache storage (actor provides thread safety).
    private var storage: [String: CacheEntry] = [:]

    /// Keys in insertion order for LRU tracking.
    private var keyOrder: [String] = []

    init(maxCount: Int = 100) {
        self.maxCount = maxCount
    }

    /// Retrieves a cached result for the given key.
    func get(key: String) -> ToolResult? {
        guard let entry = storage[key] else {
            return nil
        }

        // Move key to end of order (most recently used)
        if let index = keyOrder.firstIndex(of: key) {
            keyOrder.remove(at: index)
            keyOrder.append(key)
        }

        return entry.result
    }

    /// Stores a result in the cache.
    func set(key: String, value: ToolResult) {
        // Remove existing key from order if present
        if let index = keyOrder.firstIndex(of: key) {
            keyOrder.remove(at: index)
        }

        // Evict oldest if at capacity
        if keyOrder.count >= maxCount, let oldest = keyOrder.first {
            storage.removeValue(forKey: oldest)
            keyOrder.removeFirst()
        }

        // Store new entry
        let entry = CacheEntry(result: value, timestamp: Date())
        storage[key] = entry
        keyOrder.append(key)
    }

    /// Removes a specific key from the cache.
    func remove(key: String) {
        storage.removeValue(forKey: key)
        if let index = keyOrder.firstIndex(of: key) {
            keyOrder.remove(at: index)
        }
    }

    /// Clears all cached entries.
    func clear() {
        storage.removeAll()
        keyOrder.removeAll()
    }

    /// Returns the current number of cached entries.
    var count: Int {
        keyOrder.count
    }
}
