//
//  NeonMessageRow.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/12/25.
//

import SwiftUI

#if canImport(Textual)
    import Textual
#endif

/// Flattened tool invocation data for UI + copy.
struct ToolCallBlock: Identifiable, Equatable {
    let id: String
    let name: String
    let input: String
    let output: String?
}

struct NeonMessageRow: View {
    let message: ChatMessageEntity
    let relatedToolCall: ToolCall?
    let relatedToolBlocks: [ToolCallBlock]
    let toolCallStartedAt: Date?
    var interactionController: ChatInteractionController? = nil
    var isStreaming: Bool = false  // For typewriter animation during streaming

    init(
        message: ChatMessageEntity,
        relatedToolCall: ToolCall?,
        relatedToolBlocks: [ToolCallBlock] = [],
        toolCallStartedAt: Date? = nil,
        interactionController: ChatInteractionController? = nil,
        isStreaming: Bool = false
    ) {
        self.message = message
        self.relatedToolCall = relatedToolCall
        self.relatedToolBlocks = relatedToolBlocks
        self.toolCallStartedAt = toolCallStartedAt
        self.interactionController = interactionController
        self.isStreaming = isStreaming
    }

    @AppStorage("showTimestamps") private var showTimestamps: Bool = false

    @State private var hovered: Bool = false
    @State private var copied: Bool = false

    var role: MessageRole {
        MessageRole(rawValue: message.role) ?? .user
    }

    var isUser: Bool {
        role == .user
    }

    private var appThemeForMarkdown: AppTheme { CanvasDarkTheme() }

    var body: some View {
        HStack(alignment: .top, spacing: LiquidGlassTokens.Spacing.rowGutter) {
            roleMarker
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                if role != .tool {
                    headerLine
                }
                contentBody
            }
        }
        .padding(.vertical, LiquidGlassTokens.Spacing.rowVertical)
        .padding(.horizontal, LiquidGlassTokens.Spacing.rowHorizontal)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                hovered = isHovering
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var roleMarker: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(roleTint)
                .frame(width: 3, height: 18)
                .opacity(role == .assistant ? 0.35 : 0.65)

            Image(systemName: roleSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(roleTint.opacity(role == .assistant ? 0.6 : 0.85))
        }
        .frame(width: LiquidGlassTokens.Spacing.markerWidth, alignment: .top)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch role {
        case .tool:
            ToolResultCard(
                message: message,
                relatedToolCall: relatedToolCall,
                toolCallStartedAt: toolCallStartedAt
            )
            .textSelection(.enabled)

        default:
            toolRequestsRow

            let artifacts = message.artifactMetadatas

            if !message.content.isEmpty, !message.rendersContentAsArtifact {
                if role == .system {
                    Text(message.content)
                        .font(LiquidGlassTokens.messageFont(role: role, theme: appThemeForMarkdown))
                        .foregroundColor(AppColors.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    #if canImport(Textual)
                        StructuredText(markdown: message.content)
                            .textual.structuredTextStyle(.llmHubLiquid(theme: appThemeForMarkdown))
                            .textual.highlighterTheme(.llmHubLiquid(theme: appThemeForMarkdown))
                            .textual.listItemSpacing(.fontScaled(top: 0.22))
                            .font(LiquidGlassTokens.messageFont(role: role, theme: appThemeForMarkdown))
                            .foregroundStyle(AppColors.textPrimary)
                            .textual.textSelection(.enabled)
                    #else
                        // Fallback if Textual isn't available in this build.
                        Text(message.content)
                            .font(LiquidGlassTokens.messageFont(role: role, theme: appThemeForMarkdown))
                            .foregroundColor(
                                role == .assistant ? AppColors.textPrimary : AppColors.textSecondary
                            )
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    #endif
                }
            }

            // Artifacts (large pastes + non-image file attachments)
            if !artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(artifacts) { artifact in
                        ArtifactCard(artifact: artifact)
                    }
                }
            }

            // Keep lightweight display for image attachments.
            if let data = message.attachmentsData,
                let attachments = try? JSONDecoder().decode([Attachment].self, from: data),
                !attachments.isEmpty
            {
                let images = attachments.filter { $0.type == .image }
                if !images.isEmpty {
                    ForEach(images) { attachment in
                        HStack(spacing: 8) {
                            Image(systemName: attachment.type.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.textTertiary)
                                .frame(width: 14)

                            Text(attachment.filename)
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var headerLine: some View {
        HStack(spacing: 10) {
            Text(LiquidGlassTokens.roleLabel(role))
                .font(.caption2.weight(.semibold))
                .foregroundColor(role == .assistant ? AppColors.textTertiary : AppColors.textSecondary)

            if showTimestamps {
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            if hovered || copied {
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(copied ? AppColors.success : AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private var roleTint: Color {
        LiquidGlassTokens.roleTint(role, theme: appThemeForMarkdown)
    }

    private var roleSymbolName: String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "info.circle"
        case .tool: return "wrench.and.screwdriver.fill"
        }
    }

    @ViewBuilder
    private var toolRequestsRow: some View {
        if role == .assistant,
            let toolCallsData = message.toolCallsData,
            let toolCalls = try? JSONDecoder().decode([ToolCall].self, from: toolCallsData),
            !toolCalls.isEmpty
        {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)

                Text(toolCalls.map(\.name).joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 2)
        }
    }

    private func copyToClipboard() {
        let copyText = buildCopyText()

        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(copyText, forType: .string)
        #else
            UIPasteboard.general.string = copyText
        #endif

        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }

    private func buildCopyText() -> String {
        var fullText = message.content

        // For assistant messages, include tool calls + tool outputs in the copied text.
        if role == .assistant, !relatedToolBlocks.isEmpty {
            for block in relatedToolBlocks {
                fullText += "\n\n### [\(block.name)]"

                let args = prettyPrintedJSON(from: block.input) ?? block.input
                let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedArgs.isEmpty, trimmedArgs != "{}" {
                    fullText += "\n\n**Args**\n```json\n\(trimmedArgs)\n```"
                }

                let output = (block.output ?? "[No result]")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let safeOutput = output.isEmpty ? "[No result]" : output
                fullText += "\n\n**Output**\n```\n\(safeOutput)\n```"
            }
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prettyPrintedJSON(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard
            let prettyData = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted])
        else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }
}

// MARK: - Previews

#Preview("Message Rows") {
    ScrollView {
        VStack(spacing: 0) {
            NeonMessageRow(
                message: MockData.userMessage(
                    content: "Hello! How can I use the `http_request` tool?"),
                relatedToolCall: nil
            )

            NeonMessageRow(
                message: MockData.assistantMessage(
                    content: "You can use it by calling the function with a URL. For example:"),
                relatedToolCall: nil
            )

            NeonMessageRow(
                message: MockData.assistantMessage(content: ""),
                relatedToolCall: MockData.toolCall(
                    name: "http_request", input: "{\"url\": \"https://api.github.com\"}"),
                relatedToolBlocks: [
                    ToolCallBlock(
                        id: "call_123",
                        name: "http_request",
                        input: "{\"url\": \"https://api.github.com\"}",
                        output: "{\"status\": 200, \"body\": \"...\"}"
                    )
                ]
            )
        }
    }
    .previewEnvironment()
}
