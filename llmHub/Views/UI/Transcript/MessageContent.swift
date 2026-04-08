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
    let onRegenerate: (() -> Void)?
    let onEdit: (() -> Void)?
    @State private var didCopy: Bool = false

    @Environment(\.uiScale) private var uiScale

    init(
        content: String,
        isStreaming: Bool,
        role: MessageRole,
        generationID: UUID?,
        messageID: UUID?,
        onReply: (() -> Void)?,
        onRegenerate: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.content = content
        self.isStreaming = isStreaming
        self.role = role
        self.generationID = generationID
        self.messageID = messageID
        self.onReply = onReply
        self.onRegenerate = onRegenerate
        self.onEdit = onEdit
    }

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
            // Reply — available for both user and assistant
            if role == .assistant || role == .user {
                Button {
                    onReply?()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }

            // Copy — available for all message roles
            Button(didCopy ? "Copied" : "Copy") {
                copyToClipboard(content)
                didCopy = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            }

            if role == .assistant {
                Divider()

                // Regenerate — re-send the request to get a new response
                Button {
                    onRegenerate?()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }

            if role == .user {
                Divider()

                // Edit — copies content to composer for re-send
                Button {
                    onEdit?()
                } label: {
                    Label("Edit & Resend", systemImage: "pencil")
                }
            }

            // View Raw — copies the raw markdown to clipboard
            Button {
                copyToClipboard(content)
            } label: {
                Label("Copy Raw Markdown", systemImage: "doc.text")
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
