//
//  ImageLoader.swift
//  llmHub
//
//  Cancellation-safe remote image loader with memory+disk caching and request de-duplication.
//

import CryptoKit
import Foundation
import OSLog

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

/// Loads and caches remote images for inline Markdown rendering.
///
/// Design goals:
/// - De-duplicate requests by URL (shared in-flight Task).
/// - Cache decoded images in memory (NSCache).
/// - Cache raw bytes on disk (Caches directory).
/// - Cancellation-safe: canceling an awaiter should not kill the shared download unless no consumers remain.
actor ImageLoader {
    static let shared = ImageLoader()

    struct Configuration: Sendable {
        var maxBytes: Int = 20 * 1024 * 1024
        var cacheSubdirectory: String = "llmHub/ImageCache"
    }

    enum ImageLoaderError: LocalizedError, Sendable {
        case invalidResponse
        case nonHTTPURL
        case unsupportedContentType(String?)
        case exceededSizeLimit(maxBytes: Int)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid image response"
            case .nonHTTPURL:
                return "Unsupported image URL"
            case .unsupportedContentType(let contentType):
                return "Unsupported content type \(contentType ?? "unknown")"
            case .exceededSizeLimit(let maxBytes):
                return "Image exceeded size limit (\(maxBytes) bytes)"
            case .decodeFailed:
                return "Failed to decode image"
            }
        }
    }

    private struct InFlight {
        let task: Task<(image: PlatformImage, data: Data), Error>
        var consumerTokens: [UUID: UUID?]  // token -> generationID
    }

    private let logger = Logger(subsystem: "com.llmhub", category: "ImageLoader")
    private let config: Configuration
    private let urlSession: URLSession

    private let memoryCache: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        cache.countLimit = 256
        return cache
    }()

    private var inFlight: [URL: InFlight] = [:]

    init(configuration: Configuration = .init(), urlSession: URLSession = .shared) {
        self.config = configuration
        self.urlSession = urlSession
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func load(url: URL, generationID: UUID?) async throws -> PlatformImage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ImageLoaderError.nonHTTPURL
        }

        if let cached = memoryCache.object(forKey: url as NSURL) {
#if DEBUG
            logger.debug("MEM hit: \(url.absoluteString, privacy: .public)")
#endif
            return cached
        }

        if let diskData = (try? loadFromDisk(url: url)) ?? nil,
            let decoded = decodeImage(data: diskData) {
            memoryCache.setObject(decoded, forKey: url as NSURL)
#if DEBUG
            logger.debug("DISK hit: \(url.absoluteString, privacy: .public)")
#endif
            return decoded
        }

        let token = UUID()

        if var existing = inFlight[url] {
            existing.consumerTokens[token] = generationID
            inFlight[url] = existing
#if DEBUG
            logger.debug("INFLIGHT reuse: \(url.absoluteString, privacy: .public)")
#endif
            defer { unregister(url: url, token: token) }
            let (image, _) = try await existing.task.value
            return image
        }

        let downloadTask = Task.detached(priority: .utility) { [config, urlSession] in
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (bytes, response) = try await urlSession.bytes(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw ImageLoaderError.invalidResponse
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type")
            if let lowercasedContentType = contentType?.lowercased(), !lowercasedContentType.hasPrefix("image/") {
                throw ImageLoaderError.unsupportedContentType(contentType)
            }

            var data = Data()
            data.reserveCapacity(min(256 * 1024, config.maxBytes))

            for try await byte in bytes {
                if Task.isCancelled { throw CancellationError() }
                data.append(byte)
                if data.count > config.maxBytes {
                    throw ImageLoaderError.exceededSizeLimit(maxBytes: config.maxBytes)
                }
            }

            guard let decoded = ImageLoader.decodeImageStatic(data: data) else {
                throw ImageLoaderError.decodeFailed
            }

            return (image: decoded, data: data)
        }

        inFlight[url] = InFlight(task: downloadTask, consumerTokens: [token: generationID])
        defer { unregister(url: url, token: token) }

        do {
            let (image, data) = try await downloadTask.value
            memoryCache.setObject(image, forKey: url as NSURL)
            try? saveToDisk(url: url, data: data)
#if DEBUG
            logger.debug("NET fetch ok: \(url.absoluteString, privacy: .public) bytes=\(data.count)")
#endif
            return image
        } catch {
            // Ensure we don't keep failed tasks around.
            clearInFlight(url: url)
            throw error
        }
    }

    /// Cancels in-flight downloads associated with a given generation ID when no other consumers remain.
    func cancelLoads(for generationID: UUID) {
        let toCancel: [URL] = inFlight.compactMap { (url, inflight) in
            let stillNeeded =
                inflight.consumerTokens.values.contains { $0 != nil && $0 != generationID }
            let thisGenerationConsumers =
                inflight.consumerTokens.values.contains { $0 == generationID }
            return (thisGenerationConsumers && !stillNeeded) ? url : nil
        }

        for url in toCancel {
            guard let inflight = inFlight[url] else { continue }
#if DEBUG
            logger.debug(
                "Cancel in-flight for gen \(generationID, privacy: .public): \(url.absoluteString, privacy: .public)"
            )
#endif
            inflight.task.cancel()
            inFlight[url] = nil
        }
    }

    // MARK: - Internals

    private func unregister(url: URL, token: UUID) {
        guard var inflight = inFlight[url] else { return }
        inflight.consumerTokens.removeValue(forKey: token)
        if inflight.consumerTokens.isEmpty {
            inflight.task.cancel()
            inFlight[url] = nil
        } else {
            inFlight[url] = inflight
        }
    }

    private func clearInFlight(url: URL) {
        inFlight[url] = nil
    }

    private func decodeImage(data: Data) -> PlatformImage? {
        Self.decodeImageStatic(data: data)
    }

    private static func decodeImageStatic(data: Data) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    private func cacheDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(config.cacheSubdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheFileURL(for url: URL) throws -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return try cacheDirectoryURL().appendingPathComponent(hex).appendingPathExtension("bin")
    }

    private func loadFromDisk(url: URL) throws -> Data? {
        let fileURL = try cacheFileURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    private func saveToDisk(url: URL, data: Data) throws {
        let fileURL = try cacheFileURL(for: url)
        try data.write(to: fileURL, options: [.atomic])
    }
}
