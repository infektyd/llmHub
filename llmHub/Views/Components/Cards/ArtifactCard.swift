//
//  ArtifactCard.swift
//  llmHub
//
//  Collapsible artifact renderer for large pastes and attachments.
//

import SwiftUI

#if canImport(Splash)
    import Splash
#endif

struct ArtifactCard: View {
    let artifact: ArtifactMetadata

    @Environment(\.theme) private var theme

    @State private var isExpanded = false
    @State private var loadedContent: String? = nil
    @State private var highlightedContent: AttributedString? = nil

    @State private var copiedContent: Bool = false
    @State private var copiedAll: Bool = false
    @State private var copiedJSON: Bool = false

    private let maxRenderBytes: Int = 100 * 1024
    private let maxHeight: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider().overlay(Color.purple.opacity(0.18))

                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 07, style: .continuous)
                .fill(Color.purple.opacity(0.10))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 07, style: .continuous)
                .stroke(Color.purple.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: Color.purple.opacity(0.10), radius: 10, x: 0, y: 4)
        .padding(.vertical, 6)
        .task(id: isExpanded) {
            guard isExpanded else { return }
            await loadAndHighlightIfNeeded()
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.85))

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    Text("\(languageLabel) • \(formatFileSize(artifact.sizeBytes))")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let warning = truncationWarning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                Group {
                    if let highlightedContent {
                        Text(highlightedContent)
                    } else {
                        Text(displayContent)
                            .font(theme.monoFont)
                            .foregroundStyle(theme.textPrimary.opacity(0.82))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
            }
            .frame(maxHeight: maxHeight)
            .background {
                RoundedRectangle(cornerRadius: 05, style: .continuous)
                    .fill(Color.purple.opacity(0.08))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 05, style: .continuous)
                    .stroke(Color.purple.opacity(0.22), lineWidth: 1)
            )
            .padding(.horizontal, 12)

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
                    title: copiedContent ? "Copied" : "Copy Content",
                    icon: copiedContent ? "checkmark" : "doc.on.doc",
                    isActive: copiedContent
                ) {
                    copyContentToClipboard()
                }

                if isJSONLike {
                    actionButton(
                        title: copiedJSON ? "Copied" : "Copy JSON",
                        icon: copiedJSON ? "checkmark" : "curlybraces",
                        isActive: copiedJSON
                    ) {
                        copyJSONToClipboard()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var displayContent: String {
        // Prefer lazily loaded file content when available.
        if let loadedContent {
            return loadedContent
        }
        return artifact.content
    }

    private var truncationWarning: String? {
        guard artifact.sizeBytes > maxRenderBytes else { return nil }
        return
            "Large artifact (\(formatFileSize(artifact.sizeBytes))). Showing first \(formatFileSize(maxRenderBytes))."
    }

    private var languageLabel: String {
        artifact.language.rawValue.uppercased()
    }

    private var isJSONLike: Bool {
        artifact.language == .json
            || displayContent.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
            || displayContent.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
    }

    @MainActor
    private func loadAndHighlightIfNeeded() async {
        // Load full content lazily for file-backed artifacts.
        if loadedContent == nil, let url = artifact.fileURL {
            loadedContent = loadTextFile(url: url, maxBytes: maxRenderBytes) ?? artifact.content
        }

        let code = displayContent
        guard !code.isEmpty else {
            highlightedContent = nil
            return
        }

        #if canImport(Splash)
            // Splash only ships with Swift grammar; we still use it for everything.
            // It provides decent highlighting for JSON-like text (strings/numbers) too.
            let splashTheme = Theme.wwdc18(withFont: Font(size: 13))
            let highlighter = SyntaxHighlighter(
                format: AttributedStringOutputFormat(theme: splashTheme))
            let highlighted = highlighter.highlight(code)
            highlightedContent = AttributedString(highlighted)
        #else
            highlightedContent = nil
        #endif
    }

    private func loadTextFile(url: URL, maxBytes: Int) -> String? {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let truncated = data.prefix(maxBytes)
            return String(data: truncated, encoding: .utf8)
        } catch {
            return nil
        }
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
            .background(Color.purple.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 03, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func copyContentToClipboard() {
        copyToClipboard(text: displayContent)
        pulseCopyState(kind: .content)
    }

    private func copyAllToClipboard() {
        var text = "# \(artifact.filename)"
        text += "\n\nLanguage: \(languageLabel)"
        text += "\nSize: \(formatFileSize(artifact.sizeBytes))"

        if artifact.sizeBytes > maxRenderBytes {
            text += "\n\n[Truncated to \(formatFileSize(maxRenderBytes))]"
        }

        let fence = fenceLanguage
        text += "\n\n```\(fence.isEmpty ? "" : fence)\n\(displayContent)\n```"

        copyToClipboard(text: text)
        pulseCopyState(kind: .all)
    }

    private func copyJSONToClipboard() {
        let pretty = prettyPrintedJSON(from: displayContent) ?? displayContent
        copyToClipboard(text: pretty)
        pulseCopyState(kind: .json)
    }

    private enum CopyKind {
        case content
        case all
        case json
    }

    private func pulseCopyState(kind: CopyKind) {
        withAnimation {
            switch kind {
            case .content:
                copiedContent = true
            case .all:
                copiedAll = true
            case .json:
                copiedJSON = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                switch kind {
                case .content:
                    copiedContent = false
                case .all:
                    copiedAll = false
                case .json:
                    copiedJSON = false
                }
            }
        }
    }

    private func copyToClipboard(text: String) {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
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

    private var fenceLanguage: String {
        switch artifact.language {
        case .json: return "json"
        case .swift: return "swift"
        case .python: return "python"
        case .javascript: return "javascript"
        case .markdown: return "markdown"
        case .text: return ""
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Previews

#Preview("Artifact Card") {
    ArtifactCard(
        artifact: ArtifactMetadata(
            id: UUID(),
            filename: "example.json",
            content: "{\n  \"name\": \"llmHub\",\n  \"version\": \"1.0.0\"\n}",
            language: .json,
            sizeBytes: 42
        )
    )
    .padding()
    .previewEnvironment()
}
