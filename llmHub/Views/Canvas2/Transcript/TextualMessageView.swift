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
    @State private var didCopy: Bool = false

    static func == (lhs: TextualMessageView, rhs: TextualMessageView) -> Bool {
        lhs.content == rhs.content
            && lhs.isStreaming == rhs.isStreaming
            && lhs.role == rhs.role
            && lhs.generationID == rhs.generationID
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
        .font(.system(size: 14))
        .foregroundStyle(AppColors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            if role == .assistant {
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
            "\n---",
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
