//
//  TextualMessageView.swift
//  llmHub
//
//  Wrapper for Textual rendering.
//  Currently falls back to native Text() until Textual is fully integrated.
//

import SwiftUI
import Textual

struct TextualMessageView: View, Equatable {
    let content: String
    let isStreaming: Bool
    let role: MessageRole
    let generationID: UUID?
    let messageID: UUID?
    let onReply: (() -> Void)?
    @State private var didCopy: Bool = false

    @Environment(\.uiScale) private var uiScale

    static func == (lhs: TextualMessageView, rhs: TextualMessageView) -> Bool {
        lhs.content == rhs.content
            && lhs.isStreaming == rhs.isStreaming
            && lhs.role == rhs.role
            && lhs.generationID == rhs.generationID
            && lhs.messageID == rhs.messageID
    }

    var body: some View {
        Group {
            if shouldUseStructuredMarkdown(content) {
                StructuredText(markdown: content)
                    .textual.textSelection(.enabled)
                    .textual.imageAttachmentLoader(LLMHubImageAttachmentLoader(generationID: generationID))
            } else {
                InlineText(markdown: content)
                    .textual.textSelection(.enabled)
                    .textual.imageAttachmentLoader(LLMHubImageAttachmentLoader(generationID: generationID))
            }
        }
        .font(.system(size: 14 * uiScale))
        .foregroundStyle(AppColors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            if role == .assistant || role == .user {
                Button {
                    onReply?()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }
            if role == .assistant {
                Divider()
                Button(didCopy ? "Copied" : "Copy") {
                    copyToClipboard(content)
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopy = false
                    }
                }
            }
        }
    }

    private func shouldUseStructuredMarkdown(_ markdown: String) -> Bool {
        // Heuristic: block constructs that should render with StructuredText.
        // - Fenced code blocks
        // - ATX headings
        // - Lists (ordered/unordered)
        // - Blockquotes
        // - Tables (pipe syntax)
        let blockMarkers = [
            "\n```",
            "\n#",
            "\n> ",
            "\n- ",
            "\n* ",
            "\n1. ",
            "\n2. ",
            "\n|",
            "\n---"
        ]
        return blockMarkers.contains { markdown.contains($0) } || markdown.hasPrefix("#")
    }

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

#if DEBUG
#Preview("TextualMessageView - Inline") {
    TextualMessageView(
        content: Canvas2PreviewFixtures.markdownShort,
        isStreaming: false,
        role: .assistant,
        generationID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        messageID: nil,
        onReply: nil
    )
    .padding()
    .frame(width: 900)
}

#Preview("TextualMessageView - Structured") {
    TextualMessageView(
        content: Canvas2PreviewFixtures.markdownLongWithCode,
        isStreaming: false,
        role: .assistant,
        generationID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        messageID: nil,
        onReply: nil
    )
    .padding()
    .frame(width: 900)
}

#Preview("TextualMessageView - Streaming") {
    TextualMessageView(
        content: Canvas2PreviewFixtures.streamingRow().content,
        isStreaming: true,
        role: .assistant,
        generationID: Canvas2PreviewFixtures.IDs.streamingGeneration,
        messageID: nil,
        onReply: nil
    )
    .padding()
    .frame(width: 900)
}
#endif
