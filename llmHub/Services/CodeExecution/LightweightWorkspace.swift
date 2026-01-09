//
//  LightweightWorkspace.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import Foundation
import OSLog

enum WorkspaceError: Error, LocalizedError {
    case writeFailed(String)
    case readFailed(String)
    case notFound
    case listingFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let reason): return "Failed to write item: \(reason)"
        case .readFailed(let reason): return "Failed to read item: \(reason)"
        case .notFound: return "Item not found in workspace."
        case .listingFailed(let reason): return "Failed to list items: \(reason)"
        }
    }
}

/// A thread-safe, multi-tier storage engine to prevent memory crashes when tools return large datasets.
/// - Tier 1 (Hot): Dictionary [UUID: WorkspaceItem] (In-Memory)
/// - Tier 2 (Warm): NSCache (wraps NSData) (Auto-evictable memory)
/// - Tier 3 (Cold): Disk storage (Persistence)
actor LightweightWorkspace {
    private let logger = Logger(subsystem: "com.llmhub", category: "LightweightWorkspace")

    // Tier 1: Hot Cache (Immediate Memory)
    private var hotCache: [UUID: WorkspaceItem] = [:]

    // Tier 2: Warm Cache (NSCache)
    // NSCache keys must be objects (NSString), values must be objects (NSData).
    private let warmCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 50 // Keep ~50 items in "warm" memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB limit
        return cache
    }()

    // Tier 3: Cold Storage (Disk)
    private let fileManager = FileManager.default
    private let customStorageDirectory: URL?

    init(storageDirectory: URL? = nil) {
        self.customStorageDirectory = storageDirectory
    }

    // MARK: - Public API

    /// Stores an item in the workspace.
    /// Writes to Hot Cache and persists to Disk immediately.
    func store(_ item: WorkspaceItem) throws {
        // 1. Write to Hot Cache
        hotCache[item.id] = item

        // 2. Write to Disk (Cold Storage)
        try persistToDisk(item)

        // Note: We skip Warm cache on write because Hot covers immediate usage.
        // Warm is populated on retrieval/eviction flows if needed, but here we prioritize consistency.
    }

    /// Retrieves an item by ID, checking Hot -> Warm -> Cold tiers.
    func retrieve(id: UUID) -> WorkspaceItem? {
        // 1. Check Hot Cache
        if let item = hotCache[id] {
            return item
        }

        // 2. Check Warm Cache
        if let data = warmCache.object(forKey: id.uuidString as NSString),
           let item = try? JSONDecoder().decode(WorkspaceItem.self, from: data as Data) {
            // Promote to Hot Cache
            hotCache[id] = item
            return item
        }

        // 3. Check Cold Storage
        if let item = loadFromDisk(id: id) {
            // Promote to Hot Cache
            hotCache[id] = item
            // Also add to Warm Cache for future fallback
            if let data = try? JSONEncoder().encode(item) {
                warmCache.setObject(data as NSData, forKey: id.uuidString as NSString)
            }
            return item
        }

        return nil
    }

    /// Lists all items in the workspace.
    /// Combines Hot Cache with Disk scan (naive implementation for lightweight usage).
    func listAll() -> [WorkspaceItem] {
        var itemsMap: [UUID: WorkspaceItem] = hotCache

        guard let dir = storageDirectory else { return Array(itemsMap.values) }

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for url in fileURLs where url.pathExtension == "json" {
                let uuidString = url.deletingPathExtension().lastPathComponent
                guard let uuid = UUID(uuidString: uuidString) else { continue }

                // If not already in map (from hot cache), load it
                if itemsMap[uuid] == nil {
                    // Try to load metadata only if possible? For now, load full item to be safe.
                    // Optimization: In a real app, use a separate index file.
                    if let data = try? Data(contentsOf: url),
                       let item = try? JSONDecoder().decode(WorkspaceItem.self, from: data) {
                        itemsMap[uuid] = item
                    }
                }
            }
        } catch {
            logger.error("Failed to list files: \(error.localizedDescription)")
        }

        return Array(itemsMap.values).sorted { $0.createdAt > $1.createdAt }
    }

    /// Deletes an item from all tiers.
    func delete(id: UUID) throws {
        // 1. Remove from Hot Cache
        hotCache.removeValue(forKey: id)

        // 2. Remove from Warm Cache
        warmCache.removeObject(forKey: id.uuidString as NSString)

        // 3. Remove from Disk
        guard let dir = storageDirectory else { return }
        let fileURL = dir.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Clears the entire workspace (Memory only, or Memory+Disk based on parameter).
    /// Default clears memory caches only.
    func clearCache() {
        hotCache.removeAll()
        warmCache.removeAllObjects()
    }

    func clearAllData() throws {
        clearCache()
        guard let dir = storageDirectory else { return }
        let fileURLs = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        for url in fileURLs {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Private Helpers

    private func persistToDisk(_ item: WorkspaceItem) throws {
        guard let dir = storageDirectory else {
            throw WorkspaceError.writeFailed("Storage directory unavailable")
        }

        let fileURL = dir.appendingPathComponent(item.id.uuidString).appendingPathExtension("json")

        do {
            let data = try JSONEncoder().encode(item)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist item \(item.id): \(error.localizedDescription)")
            throw WorkspaceError.writeFailed(error.localizedDescription)
        }
    }

    private func loadFromDisk(id: UUID) -> WorkspaceItem? {
        guard let dir = storageDirectory else { return nil }
        let fileURL = dir.appendingPathComponent(id.uuidString).appendingPathExtension("json")

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let item = try JSONDecoder().decode(WorkspaceItem.self, from: data)
            return item
        } catch {
            logger.error("Failed to load item \(id): \(error.localizedDescription)")
            return nil
        }
    }
    private var storageDirectory: URL? {
        if let custom = customStorageDirectory { return custom }
        do {
            let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let dir = urls[0].appendingPathComponent("llmhub/workspace", isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
            return dir
        } catch {
            logger.error("Failed to resolve storage directory: \(error.localizedDescription)")
            return nil
        }
    }
    /// Read file content as Data (sandboxed).
    func readFile(path: String) async throws -> Data? {
        guard let item = retrieve(id: UUID(uuidString: path) ?? UUID()) else { return nil }
        return item.data
    }

    /// Write file content (returns WorkspaceItem ID).
    func writeFile(path: String, data: Data, contentType: String = "application/octet-stream", metadata: [String: String] = [:]) async throws -> UUID {
        let item = WorkspaceItem(
            id: UUID(),
            filename: (path as NSString).lastPathComponent,
            data: data,
            contentType: contentType,
            createdAt: Date(),
            metadata: metadata
        )
        try store(item)
        return item.id
    }

    /// List files matching pattern.
    func listFiles(matching pattern: String? = nil) async -> [WorkspaceItem] {
        let all = listAll()
        if let pattern {
            return all.filter { $0.filename.range(of: pattern, options: .caseInsensitive) != nil }
        }
        return all
    }
}
