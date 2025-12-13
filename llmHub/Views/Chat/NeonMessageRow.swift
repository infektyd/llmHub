//
//  NeonMessageRow.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/12/25.
//

import MarkdownUI
import SwiftUI

struct NeonMessageRow: View {
    let message: ChatMessageEntity
    let relatedToolCall: ToolCall?
    var interactionController: ChatInteractionController? = nil

    @Environment(\.theme) private var theme
    @AppStorage("showTimestamps") private var showTimestamps: Bool = false

    @State private var hovered: Bool = false
    @State private var copied: Bool = false

    var role: MessageRole {
        MessageRole(rawValue: message.role) ?? .user
    }

    var isUser: Bool {
        role == .user
    }

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
            ToolResultCard(message: message, relatedToolCall: relatedToolCall)

        default:
            toolRequestsRow

            if !message.content.isEmpty {
                if role == .system {
                    Text(message.content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Markdown(message.content)
                        .markdownTheme(.llmHubLiquid(theme: theme))
                        .textSelection(.enabled)
                }
            }

            // Attachments if any
            if let data = message.attachmentsData,
                let attachments = try? JSONDecoder().decode([Attachment].self, from: data),
                !attachments.isEmpty
            {
                ForEach(attachments) { attachment in
                    HStack(spacing: 8) {
                        Image(systemName: attachment.type.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                            .frame(width: 14)

                        Text(attachment.filename)
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
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
                .foregroundColor(role == .assistant ? theme.textTertiary : theme.textSecondary)

            if showTimestamps {
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            if hovered || copied {
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(copied ? theme.success : theme.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private var roleTint: Color {
        LiquidGlassTokens.roleTint(role, theme: theme)
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
                    .foregroundColor(theme.textTertiary)

                Text(toolCalls.map(\.name).joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 2)
        }
    }

    private func copyToClipboard() {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(message.content, forType: .string)
        #else
            UIPasteboard.general.string = message.content
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
}
