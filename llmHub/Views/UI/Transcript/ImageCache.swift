//
//  RemoteImageSizeCache.swift
//  llmHub
//
//  Thread-safe, synchronous cache for remote image intrinsic sizes.
//

import Foundation

nonisolated final class RemoteImageSizeCache: @unchecked Sendable {
    nonisolated static let shared = RemoteImageSizeCache()
    nonisolated private init() {}

    private let lock = NSLock()
    private var sizes: [URL: CGSize] = [:]

    nonisolated func size(for url: URL) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        return sizes[url]
    }

    nonisolated func setSize(_ size: CGSize, for url: URL) {
        lock.lock()
        sizes[url] = size
        lock.unlock()
    }
}
