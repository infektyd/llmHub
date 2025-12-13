//
//  ToolResultCard.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct ToolResultCard: View {
    let message: ChatMessageEntity
    let relatedToolCall: ToolCall?
    @Environment(\.theme) private var theme

    // In a real app, this should probably be persisted via SceneStorage or the Entity itself.
    // For now, we use @State as per instructions "collapsed state remembers per tool-call ID" generally implies runtime persistence.
    // If strict app-restart persistence is needed, we'd add `isCollapsed` to ChatMessageEntity.
    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false
    @State private var copiedJSON: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Status Icon
                    statusIcon
                        .font(.system(size: 14, weight: .semibold))

                    // Tool Name
                    Text(relatedToolCall?.name ?? "Tool Result")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(theme.textPrimary.opacity(0.035))

            // MARK: - Expanded Content
            if isExpanded {
                Divider().overlay(theme.textPrimary.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    // Actions Bar
                    HStack(spacing: 12) {
                        Spacer()

                        actionButton(
                            title: copied ? "Copied" : "Copy Output",
                            icon: copied ? "checkmark" : "doc.on.doc",
                            isActive: copied
                        ) {
                            copyToClipboard(message.content, isJSON: false)
                        }

                        if isJSON(message.content) {
                            actionButton(
                                title: copiedJSON ? "Copied JSON" : "Copy JSON",
                                icon: copiedJSON ? "checkmark" : "curlybraces",
                                isActive: copiedJSON
                            ) {
                                copyToClipboard(message.content, isJSON: true)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Output Body
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(message.content)
                            .font(theme.monoFont)
                            .foregroundColor(theme.textPrimary.opacity(0.82))
                            .padding(12)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(
            GlassEffect.regular.tint(Color.glassTool.opacity(0.2)),
            in: RoundedRectangle(
                cornerRadius: LiquidGlassTokens.Radius.toolCard, style: .continuous)
        )
        .shadow(
            color: LiquidGlassTokens.Shadow.toolCard.color,
            radius: LiquidGlassTokens.Shadow.toolCard.radius,
            x: LiquidGlassTokens.Shadow.toolCard.x,
            y: LiquidGlassTokens.Shadow.toolCard.y
        )
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private var isSuccess: Bool {
        // Simple heuristic as requested
        let lower = message.content.lowercased()
        return !lower.contains("error") && !lower.contains("invalid_request_error")
            && !lower.contains("failed")
    }

    private var statusIcon: some View {
        if isSuccess {
            return Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.success.opacity(0.85))
        } else {
            return Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(theme.error.opacity(0.85))
        }
    }

    private func isJSON(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
            || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
    }

    private func actionButton(
        title: String, icon: String, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(isActive ? theme.success : theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.textPrimary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func copyToClipboard(_ text: String, isJSON: Bool) {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif

        withAnimation {
            if isJSON { copiedJSON = true } else { copied = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if isJSON { copiedJSON = false } else { copied = false }
            }
        }
    }
}
