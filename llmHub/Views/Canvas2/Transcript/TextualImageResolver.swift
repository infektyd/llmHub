//
//  TextualImageResolver.swift
//  llmHub
//
//  Textual attachment loader for Markdown images, backed by llmHub's ImageLoader.
//

import SwiftUI
import Textual

/// Image attachment loader that resolves Markdown image URLs into an attachment that loads
/// asynchronously with an inline spinner and uses llmHub's ImageLoader caching pipeline.
struct LLMHubImageAttachmentLoader: AttachmentLoader {
    typealias Attachment = RemoteImageAttachment

    let generationID: UUID?

    func attachment(
        for url: URL,
        text: String,
        environment: ColorEnvironmentValues
    ) async throws -> RemoteImageAttachment {
#if DEBUG
        print("DEBUG: Resolve markdown image attachment url=\(url.absoluteString)")
#endif
        // Return immediately; the attachment view handles async loading so Textual can lay it out
        // and render an inline progress indicator in-place.
        return RemoteImageAttachment(url: url, altText: text, generationID: generationID)
    }
}

// MARK: - Attachment + View

/// Attachment that renders an inline remote image.
struct RemoteImageAttachment: Textual.Attachment {
    var description: String { altText }

    let url: URL
    let altText: String
    let generationID: UUID?

    var selectionStyle: AttachmentSelectionStyle { .object }

    @MainActor
    var body: some View {
        RemoteImageAttachmentView(url: url, altText: altText, generationID: generationID)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        let fallback = CGSize(width: 22, height: 22)
        guard let cachedSize = RemoteImageSizeCache.shared.size(for: url) else {
            // Before load, reserve a small square so the spinner has an inline slot.
            return fallback
        }

        guard let proposedWidth = proposal.width else { return cachedSize }

        let aspect = cachedSize.width / max(1, cachedSize.height)
        let width = min(proposedWidth, cachedSize.width)
        let height = width / max(0.01, aspect)
        return CGSize(width: width, height: height)
    }
}

private struct RemoteImageAttachmentView: View {
    enum Phase: Equatable {
        case loading
        case success(PlatformImage)
        case failure
    }

    let url: URL
    let altText: String
    let generationID: UUID?

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.mini)
            case .success(let image):
                platformImage(image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(altText.isEmpty ? "Image" : altText)
            case .failure:
                Text("image failed to load")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        phase = .loading
        guard !PreviewMode.isRunning else {
            // Canvas previews must be deterministic and must not trigger network/disk caches.
            // Keep a stable failure UI rather than attempting to fetch.
            phase = .failure
            return
        }
        do {
            let image = try await ImageLoader.shared.load(url: url, generationID: generationID)
            let size = image.size
            RemoteImageSizeCache.shared.setSize(size, for: url)
            phase = .success(image)
        } catch is CancellationError {
            // Silent cancellation: keep minimal UI and no error banners.
            phase = .loading
        } catch {
            phase = .failure
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }
}

