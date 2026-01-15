//
//  ToolResultCardView.swift
//  llmHub
//
//  Flat tool result card for transcript rendering
//  Keeps output readable with collapse + copy affordances.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ToolResultCardView: View {
    let viewModel: TranscriptRowViewModel

    @State private var isExpanded: Bool
    @State private var didCopy: Bool = false
    @State private var showArguments: Bool = false

    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    private static let collapseThreshold = 2200
    private static let previewLimit = 1200
    private static let expandedLimit = 20000

    init(viewModel: TranscriptRowViewModel) {
        self.viewModel = viewModel
        let shouldCollapse = viewModel.content.count > Self.collapseThreshold
        _isExpanded = State(initialValue: !shouldCollapse)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 10 : 12) {
            header

            if let errorMessage = errorMessage {
                errorBanner(errorMessage)
            }

            outputSection

            if let footer = footerNote {
                Text(footer)
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            metadataSection

            argumentsSection

            developerSection
        }
        .padding(uiCompactMode ? 12 : 16)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppColors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon)
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(statusTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(toolDisplayName)
                    .font(.system(size: 14 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 6) {
                    statusBadge

                    if let elapsedText {
                        Text(elapsedText)
                            .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    if isTruncatedByTool {
                        Text("Truncated")
                            .font(.system(size: 11 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Spacer()

            if isCollapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12 * uiScale, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                copyToClipboard(outputText)
                didCopy = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(size: 11 * uiScale, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(statusTint.opacity(0.18))
            }
            .foregroundStyle(statusTint)
    }

    // MARK: - Output

    private var outputSection: some View {
        let displayText = isExpanded ? expandedOutput : previewOutput
        return VStack(alignment: .leading, spacing: 6) {
            if outputText.isEmpty {
                Text("No output returned.")
                    .font(.system(size: 12 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            } else if isExpanded {
                ScrollView(.vertical) {
                    Text(displayText)
                        .font(.system(size: 12.5 * uiScale, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(uiCompactMode ? 10 : 12)
                }
                .frame(maxHeight: uiCompactMode ? 240 : 280)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.backgroundPrimary.opacity(0.5))
                }
            } else {
                Text(displayText)
                    .font(.system(size: 12.5 * uiScale, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(uiCompactMode ? 10 : 12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.backgroundPrimary.opacity(0.5))
                    }
            }

            if isDisplayTruncated {
                Text("Output trimmed for display. Copy to view the full response.")
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        Group {
            if !filteredMetadata.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Metadata")
                        .font(.system(size: 12 * uiScale, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)

                    ForEach(filteredMetadata.keys.sorted(), id: \.self) { key in
                        if let value = filteredMetadata[key] {
                            Text("\(key): \(value)")
                                .font(.system(size: 11.5 * uiScale, design: .monospaced))
                                .foregroundStyle(AppColors.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Arguments

    private var argumentsSection: some View {
        Group {
            if let arguments = formattedArguments, !arguments.isEmpty {
                DisclosureGroup(isExpanded: $showArguments) {
                    ScrollView(.vertical) {
                        Text(arguments)
                            .font(.system(size: 12 * uiScale, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(uiCompactMode ? 8 : 10)
                    }
                    .frame(maxHeight: 200)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.backgroundPrimary.opacity(0.5))
                    }
                } label: {
                    Text("Arguments")
                        .font(.system(size: 12 * uiScale, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Developer

    private var developerSection: some View {
        Group {
            if settingsManager.settings.developerModeManualToolTriggering,
               let toolCallID = viewModel.toolCallID {
                Text("Tool Call ID: \(toolCallID)")
                    .font(.system(size: 11 * uiScale, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Helpers

    private var toolDisplayName: String {
        viewModel.toolResultMeta?.toolName.replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "Tool Output"
    }

    private var toolIcon: String {
        let key = viewModel.toolResultMeta?.toolName.lowercased() ?? ""
        let normalizedKey = key.replacingOccurrences(of: " ", with: "_")
        let iconMap: [String: String] = [
            "calculator": "function",
            "code_interpreter": "curlybraces",
            "data_visualization": "chart.xyaxis.line",
            "file_editor": "pencil.and.list.clipboard",
            "file_patch": "pencil.and.list.clipboard",
            "read_file": "doc.text.magnifyingglass",
            "http_request": "network",
            "shell": "terminal",
            "web_search": "globe",
            "workspace": "folder",
            "browser_preview": "safari"
        ]
        return iconMap[normalizedKey] ?? "wrench.and.screwdriver"
    }

    private var outputText: String { viewModel.content }

    private var previewOutput: String {
        guard outputText.count > Self.previewLimit else { return outputText }
        return String(outputText.prefix(Self.previewLimit))
    }

    private var expandedOutput: String {
        guard outputText.count > Self.expandedLimit else { return outputText }
        return String(outputText.prefix(Self.expandedLimit))
    }

    private var isCollapsible: Bool {
        outputText.count > Self.collapseThreshold
    }

    private var isDisplayTruncated: Bool {
        outputText.count > (isExpanded ? Self.expandedLimit : Self.previewLimit)
    }

    private var isTruncatedByTool: Bool {
        viewModel.toolResultMeta?.truncated ?? false
    }

    private var statusTint: Color {
        if viewModel.toolResultMeta?.success == false { return .red }
        return AppColors.success
    }

    private var borderTint: Color {
        if viewModel.toolResultMeta?.success == false { return Color.red.opacity(0.35) }
        return AppColors.textPrimary.opacity(0.1)
    }

    private var statusLabel: String {
        viewModel.toolResultMeta?.success == false ? "Failed" : "Succeeded"
    }

    private var elapsedText: String? {
        guard let metadata = viewModel.toolResultMeta?.metadata else { return nil }
        let durationKeys = ["duration_ms", "elapsed_ms", "durationMs"]
        for key in durationKeys {
            if let value = metadata[key], let ms = Int(value) {
                return formatDuration(ms: ms)
            }
        }
        return nil
    }

    private var errorMessage: String? {
        guard viewModel.toolResultMeta?.success == false else { return nil }
        let error = viewModel.toolResultMeta?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (error?.isEmpty == false) ? error : "Tool execution failed."
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12 * uiScale, weight: .medium))
            .foregroundStyle(Color.red)
            .padding(uiCompactMode ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            }
    }

    private var filteredMetadata: [String: String] {
        guard let metadata = viewModel.toolResultMeta?.metadata else { return [:] }
        let excluded = ["duration_ms", "elapsed_ms", "durationMs"]
        return metadata.filter { !excluded.contains($0.key) }
    }

    private var footerNote: String? {
        guard viewModel.toolResultMeta?.success == false else { return nil }
        return "Review the error details above before retrying."
    }

    private var formattedArguments: String? {
        guard let raw = viewModel.toolCallArguments?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return raw
        }
        return prettyString
    }

    private func formatDuration(ms: Int) -> String {
        if ms >= 1000 {
            let seconds = Double(ms) / 1000
            return String(format: "%.1fs", seconds)
        }
        return "\(ms)ms"
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
#Preview("Tool Result Card") {
    ToolResultCardView(
        viewModel: TranscriptRowViewModel(
            id: "tool-row",
            role: .tool,
            headerLabel: "Tool",
            headerMetaText: nil,
            content: "{\n  \"status\": 200,\n  \"body\": [1, 2, 3]\n}",
            isStreaming: false,
            generationID: nil,
            artifacts: [],
            toolCallID: "call-123",
            toolResultMeta: ToolResultMeta(
                toolName: "http_request",
                success: true,
                truncated: false,
                error: nil,
                metadata: ["duration_ms": "384", "status": "200"]
            ),
            toolCallArguments: "{\"url\":\"https://example.com\"}"
        )
    )
    .padding()
    .frame(width: 900)
}
#endif
