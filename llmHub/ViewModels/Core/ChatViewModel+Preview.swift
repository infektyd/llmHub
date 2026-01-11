//
//  ChatViewModel+Preview.swift
//  llmHub
//
//  Preview-only factory for deterministic Canvas rendering.
//

import Foundation

#if DEBUG
extension ChatViewModel {
    /// Creates a preview-configured ChatViewModel without initializing providers, tools, or network services.
    ///
    /// Rationale: Canvas previews should be deterministic and must not trigger runtime-only systems.
    static func preview(
        isGenerating: Bool = false,
        streamingText: String? = nil,
        generationID: UUID? = nil,
        streamingMessageID: UUID? = nil,
        streamingStartedAt: Date = Canvas2PreviewFixtures.baseDate,
        executingToolNames: Set<String> = []
    ) -> ChatViewModel {
        let viewModel = ChatViewModel()

        // Drive UI state directly (no provider/tool initialization).
        viewModel._applyPreviewStreamingState(
            isGenerating: isGenerating,
            streamingText: streamingText,
            generationID: generationID ?? Canvas2PreviewFixtures.IDs.streamingGeneration,
            streamingMessageID: (streamingText == nil)
                ? nil
                : (streamingMessageID ?? Canvas2PreviewFixtures.IDs.streamingMessage),
            streamingStartedAt: (streamingText == nil) ? nil : streamingStartedAt,
            executingToolNames: executingToolNames
        )

        return viewModel
    }
}
#endif
