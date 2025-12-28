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
    let toolCallStartedAt: Date?

    @Environment(\.theme) private var theme

    // Collapsed by default (as requested), expandable per tool message.
    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false
    @State private var copiedAll: Bool = false
    @State private var copiedJSON: Bool = false

    @State private var showingDetails: Bool = false

    private let previewLineLimit: Int = 6
    private let expandedMaxHeight: CGFloat = 260
    private let largeOutputThresholdBytes: Int = 8_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(theme.textPrimary.opacity(0.08))

            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                collapsedBody
                    .transition(.opacity)
            }
        }
        .glassEffect(
            GlassEffect.regular.tint(theme.accent.opacity(0.12)),
            in: RoundedRectangle(
                cornerRadius: LiquidGlassTokens.Radius.toolCard,
                style: .continuous
            )
        )
        .shadow(
            color: LiquidGlassTokens.Shadow.toolCard.color,
            radius: LiquidGlassTokens.Shadow.toolCard.radius,
            x: LiquidGlassTokens.Shadow.toolCard.x,
            y: LiquidGlassTokens.Shadow.toolCard.y
        )
        .padding(.vertical, 6)
        .sheet(isPresented: $showingDetails) {
            toolDetailsSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                statusIcon
                    .font(.system(size: 14, weight: .semibold))

                Text(toolDisplayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)

                if let duration = durationLabel {
                    Text(duration)
                        .font(.caption2)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.textPrimary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Spacer()

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
    }

    // MARK: - Bodies

    private var collapsedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inputPreview = collapsedInputPreview {
                Text(inputPreview)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if isLargeOutput {
                largeOutputRow
            } else {
                Text(collapsedOutputPreview)
                    .font(theme.monoFont)
                    .foregroundColor(theme.textPrimary.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(previewLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Open details") {
                    showingDetails = true
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundColor(theme.accent)

                Spacer()

                if isLargeOutput {
                    Button("Copy all") {
                        copyAllToClipboard()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .textSelection(.enabled)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let input = formattedToolInput {
                section(title: "Input") {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Text(input)
                            .font(theme.monoFont)
                            .foregroundColor(theme.textPrimary.opacity(0.78))
                            .padding(12)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 140)
                    .glassEffect(
                        GlassEffect.regular.tint(theme.textPrimary.opacity(0.03)),
                        in: .rect(cornerRadius: 10)
                    )
                }
            }

            section(title: "Output") {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(message.content)
                        .font(theme.monoFont)
                        .foregroundColor(theme.textPrimary.opacity(0.82))
                        .padding(12)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: expandedMaxHeight)
            }

            HStack(spacing: 12) {
                Spacer()

                actionButton(
                    title: copiedAll ? "Copied" : "Copy All",
                    icon: copiedAll ? "checkmark" : "doc.on.doc.fill",
                    isActive: copiedAll
                ) {
                    copyAllToClipboard()
                }

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
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var toolDetailsSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                statusIcon
                    .font(.system(size: 14, weight: .semibold))

                Text(toolDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Button("Copy all") {
                    copyAllToClipboard()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.accent)

                Button("Done") {
                    showingDetails = false
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(theme.textPrimary.opacity(0.08))

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if let input = formattedToolInput {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Input")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(theme.textSecondary)
                            Text(input)
                                .font(theme.monoFont)
                                .foregroundColor(theme.textPrimary.opacity(0.78))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(theme.textSecondary)
                        Text(message.content)
                            .font(theme.monoFont)
                            .foregroundColor(theme.textPrimary.opacity(0.82))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .textSelection(.enabled)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(theme.textSecondary)

            content()
        }
    }

    // MARK: - Helpers

    private var toolDisplayName: String {
        relatedToolCall?.name ?? "Tool Result"
    }

    private var isLargeOutput: Bool {
        message.content.utf8.count >= largeOutputThresholdBytes
    }

    private var durationLabel: String? {
        guard let startedAt = toolCallStartedAt else { return nil }
        let seconds = max(0, Int(message.createdAt.timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let rem = seconds % 60
        return String(format: "%dm %02ds", minutes, rem)
    }

    private var collapsedOutputPreview: String {
        let text = message.content
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "(No output)"
        }

        let lines = text.components(separatedBy: .newlines)
        if lines.count <= previewLineLimit {
            return text
        }

        let preview = lines.prefix(previewLineLimit).joined(separator: "\n")
        return preview + "\n…"
    }

    private var collapsedInputPreview: String? {
        guard let call = relatedToolCall else { return nil }
        let raw = call.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "{}" else { return nil }

        let pretty = prettyPrintedJSON(from: raw) ?? raw
        let singleLine = pretty
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)

        return "Args: \(singleLine)"
    }

    private var formattedToolInput: String? {
        guard let call = relatedToolCall else { return nil }
        let raw = call.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "{}" else { return nil }
        return prettyPrintedJSON(from: raw) ?? raw
    }

    private var largeOutputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            Text("Large output")
                .font(.caption)
                .foregroundColor(theme.textPrimary)

            Spacer()

            Text(formatByteCount(message.content.utf8.count))
                .font(.caption2)
                .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.textPrimary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatByteCount(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    private var isSuccess: Bool {
        let lower = message.content.lowercased()
        return !lower.contains("error")
            && !lower.contains("invalid_request_error")
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private func prettyPrintedJSON(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }

    private func actionButton(
        title: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
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

    private func copyAllToClipboard() {
        var text = "Tool: \(toolDisplayName)"

        if let input = formattedToolInput {
            text += "\n\nArgs:\n\(input)"
        }

        let output = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        text += "\n\nOutput:\n\(output.isEmpty ? "[No result]" : output)"

        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif

        withAnimation {
            copiedAll = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedAll = false
            }
        }
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
            if isJSON {
                copiedJSON = true
            } else {
                copied = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if isJSON {
                    copiedJSON = false
                } else {
                    copied = false
                }
            }
        }
    }
}
