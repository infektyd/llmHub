//
//  NeonMessageBubble.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import MarkdownUI
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct NeonMessageBubble: View {
    let message: ChatMessageEntity
    let relatedToolCall: ToolCall?
    var interactionController: ChatInteractionController? = nil

    @AppStorage("glassOpacity_messages") private var glassOpacity: Double = 0.8
    @Environment(\.theme) private var theme

    @State private var selectedAttachment: Attachment?

    var role: MessageRole {
        MessageRole(rawValue: message.role) ?? .user
    }

    var isUser: Bool {
        role == .user
    }

    var attachments: [Attachment] {
        guard let data = message.attachmentsData else { return [] }
        return (try? JSONDecoder().decode([Attachment].self, from: data)) ?? []
    }

    var body: some View {
        let _ = print(
            "🔄 [NeonMessageBubble] body evaluated for message: \(message.id.uuidString.prefix(8))")
        HStack(alignment: .top, spacing: 12) {
            // MARK: - Left Side (AI/System/Tool)
            if role != .user {
                avatarView(for: role)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // Attachments
                if !attachments.isEmpty {
                    attachmentsView
                }

                // Content
                messageContent
                    .contextMenu {
                        if let interactionController,
                            role == .assistant || role == .tool
                        {
                            Button {
                                interactionController.addMessageAsReference(
                                    text: message.content,
                                    messageID: message.id,
                                    role: role
                                )
                            } label: {
                                Label("Add as Reference", systemImage: "quote.bubble")
                            }
                        }
                    }
            }
            .frame(maxWidth: 600, alignment: isUser ? .trailing : .leading)

            // MARK: - Right Side (User)
            if role == .user {
                userAvatarView
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sheet(item: $selectedAttachment) { attachment in
            AttachmentPreviewSheet(attachment: attachment)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func avatarView(for role: MessageRole) -> some View {
        Group {
            if role == .system {
                // System Icon
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(theme.textSecondary.opacity(0.1))
                    .clipShape(Circle())
            } else if role == .tool {
                // Tool Icon
                Image(systemName: "wrench.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.neonElectricBlue)
                    .frame(width: 32, height: 32)
                    .background(Color.neonElectricBlue.opacity(0.1))
                    .clipShape(Circle())
            } else {
                // Assistant Icon
                if theme.usesGlassEffect {
                    Circle()
                        .frame(width: 32, height: 32)
                        .glassEffect(
                            GlassEffect.regular.tint(.glassAI.opacity(glassOpacity)),
                            in: .circle
                        )
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                        )
                } else {
                    Circle()
                        .fill(theme.accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(theme.accent)
                        )
                        .shadow(
                            color: theme.shadowStyle.color,
                            radius: theme.shadowStyle.radius / 2,
                            x: theme.shadowStyle.x,
                            y: theme.shadowStyle.y
                        )
                }
            }
        }
    }

    private var userAvatarView: some View {
        Circle()
            .fill(theme.textSecondary.opacity(0.2))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
            )
    }

    private var attachmentsView: some View {
        VStack(spacing: 8) {
            ForEach(attachments) { attachment in
                HStack(spacing: 12) {
                    Image(systemName: attachment.type.icon)
                        .font(.system(size: 20))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        if let preview = attachment.previewText {
                            Text(preview)
                                .font(.caption2)
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button("Expand") {
                        selectedAttachment = attachment
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .tint(Color.neonElectricBlue)
                }
                .padding(10)
                .glassEffect(
                    GlassEffect.regular.tint(.glassBackground).interactive(),
                    in: RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.control,
                        style: .continuous
                    )
                )
                .onTapGesture {
                    selectedAttachment = attachment
                }
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch role {
        case .user:
            // User messages: Keep bubble styling
            Text(message.content)
                .font(theme.bodyFont)
                .foregroundColor(theme.textPrimary)
                .textSelection(.enabled)
                .padding(16)
                .background {
                    AdaptiveGlassBackground(target: .messages)
                }

        case .tool:
            // Tool messages: Use new Card View
            ToolResultCard(message: message, relatedToolCall: relatedToolCall)

        case .system:
            // System messages: Minimalist
            Text(message.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .padding(12)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

        case .assistant:
            // Assistant messages: Use Markdown rendering with action toolbar
            VStack(alignment: .leading, spacing: 12) {
                // 1. Tool Requests (if any)
                if let toolCallsData = message.toolCallsData,
                    let toolCalls = try? JSONDecoder().decode([ToolCall].self, from: toolCallsData),
                    !toolCalls.isEmpty
                {

                    ForEach(toolCalls, id: \.id) { toolCall in
                        HStack(spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption)
                                .foregroundColor(.neonElectricBlue)
                            Text("Requesting: \(toolCall.name)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.neonElectricBlue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.neonElectricBlue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                // 2. Main Content
                if !message.content.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Markdown(message.content)
                            .markdownTheme(.gitHub)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        MessageActionsView(content: message.content, onRegenerate: nil)
                    }
                }
            }
        }
    }
}

struct MessageActionsView: View {
    let content: String
    let onRegenerate: (() -> Void)?

    @State private var copied = false
    @State private var isHovering = false
    @State private var showActions = false  // For iOS tap interaction

    var body: some View {
        HStack(spacing: 10) {
            // Copy button
            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption)
                    Text(copied ? "Copied!" : "Copy")
                        .font(.caption2)
                }
                .foregroundColor(copied ? .green : .primary)
            }
            .buttonStyle(.plain)
            .contentTransition(.symbolEffect(.replace))

            if let onRegenerate = onRegenerate {
                Divider()
                    .frame(height: 12)

                // Retry button
                Button {
                    onRegenerate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Retry")
                            .font(.caption2)
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .glassEffect(GlassEffect.regular, in: Capsule())
        }
        .opacity(isHovering || showActions ? 1.0 : 0.6)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: showActions)
        #if os(macOS)
            .onHover { hovering in
                isHovering = hovering
            }
        #else
            .onTapGesture {
                showActions.toggle()
                if showActions {
                    // Auto-hide after 3 seconds on iOS
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showActions = false
                    }
                }
            }
        #endif
    }

    private func copyToClipboard() {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
        #else
            UIPasteboard.general.string = content
        #endif

        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

struct AttachmentPreviewSheet: View {
    let attachment: Attachment
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if attachment.type == .image, let data = try? Data(contentsOf: attachment.url),
                    let image = PlatformImage(data: data)
                {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else if let content = try? String(contentsOf: attachment.url, encoding: .utf8) {
                    ScrollView {
                        Text(content)
                            .font(
                                attachment.type == .code
                                    ? .system(.body, design: .monospaced) : .body
                            )
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView("Preview Unavailable", systemImage: "eye.slash")
                }
            }
            .navigationTitle(attachment.filename)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 400)
        #endif
    }
}

// Cross-platform Image compat
#if os(macOS)
    import AppKit
    typealias PlatformImage = NSImage
    extension Image {
        init(platformImage: PlatformImage) {
            self.init(nsImage: platformImage)
        }
    }
#else
    import UIKit
    typealias PlatformImage = UIImage
    extension Image {
        init(platformImage: PlatformImage) {
            self.init(uiImage: platformImage)
        }
    }
#endif
