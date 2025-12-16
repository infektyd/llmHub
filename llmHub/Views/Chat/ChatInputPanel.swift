//
//  ChatInputPanel.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A multi-platform adaptive chat input panel.
/// Features a glass-morphism design, auto-expanding text field, file attachments, and categorized tool toggles.
struct ChatInputPanel: View {
    @Binding var text: String
    @Binding var thinkingPreference: ThinkingPreference
    let isSending: Bool
    let onSend: (String) -> Void
    let tools: [UIToolToggleItem]
    let onToggleTool: (String, Bool) -> Void
    let onToolsAppear: () -> Void

    // Attachment Management
    let stagedAttachments: [Attachment]
    let onAddAttachment: (Attachment) -> Void
    let onRemoveAttachment: (Int) -> Void

    // Reference Management
    let stagedReferences: [ChatReference]
    let onRemoveReference: (Int) -> Void

    @FocusState private var isInputFocused: Bool
    @AppStorage("pasteThreshold") private var pasteThreshold: Int = 4000
    @Environment(\.theme) private var theme

    private let minHeight: CGFloat = 44
    @State private var isShowingTools = false
    @State private var isImporting = false

    private var toolButtonSize: CGFloat { 36 }

    var body: some View {
        VStack(spacing: 0) {
            if !stagedAttachments.isEmpty || !stagedReferences.isEmpty {
                attachmentPreviewStrip
                    .padding(.bottom, 8)
                    .padding(.horizontal, LiquidGlassTokens.Spacing.sheetInset)
            }

            HStack(alignment: .bottom, spacing: LiquidGlassTokens.Spacing.rowGutter) {
                toolSelectorButton
                thinkingSelectorButton
                attachmentButton
                inputField
                sendButton
            }
            .padding(.horizontal, LiquidGlassTokens.Spacing.sheetInset)
            .padding(.vertical, 12)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: text) { _, newValue in
            checkPasteThreshold(newValue)
        }
    }

    // MARK: - Logic

    private func checkPasteThreshold(_ newValue: String) {
        guard newValue.count >= pasteThreshold else { return }

        // Auto-attach logic
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "Pasted-\(timestamp).txt"

        guard let url = createTempFile(content: newValue, filename: filename) else { return }

        let preview = String(newValue.prefix(200)).replacingOccurrences(of: "\n", with: " ")
        let attachment = Attachment(
            filename: filename,
            url: url,
            type: .text,
            previewText: preview
        )

        onAddAttachment(attachment)
        text = ""  // Clear input after attaching

        print("📎 Auto-attached paste (4000+ chars): \(filename)")
    }

    private func createTempFile(content: String, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to create temp file: \(error)")
            return nil
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !stagedAttachments.isEmpty || !stagedReferences.isEmpty else {
            return
        }

        onSend(trimmed)
        text = ""  // Clear input field after send
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                // Note: We need to copy or process immediately as security scope might close
                // But for simplicity in this context, we assume immediate processing or copy
                // Better: Copy to temp if needed.
                // For now, let's create attachment directly.
                processFileURL(url)
                // We keep it open? No, we should stop accessing.
                // If we don't copy, we lose access.
                // Let's copy to temp.
                url.stopAccessingSecurityScopedResource()
            }
        case .failure(let error):
            print("Import failed: \(error.localizedDescription)")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.processFileURL(url)
                        }
                    }
                }
            }
        }
        return true
    }

    private func processFileURL(_ url: URL) {
        // Determine type
        let ext = url.pathExtension.lowercased()
        let type: AttachmentType

        if ["jpg", "jpeg", "png", "webp", "heic", "gif"].contains(ext) {
            type = .image
        } else if [
            "swift", "py", "js", "ts", "c", "cpp", "h", "java", "go", "rs", "rb", "php", "html",
            "css", "json", "md", "sh", "yml", "yaml", "xml",
        ].contains(ext) {
            type = .code
        } else if ext == "pdf" {
            type = .pdf
        } else {
            type = .text  // Default fallback or .other
        }

        // Copy to temp to ensure access
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: destURL)  // Ignore error if exists

        let attachment = Attachment(
            filename: url.lastPathComponent,
            url: destURL,
            type: type,
            previewText: nil  // Chips don't show preview
        )
        onAddAttachment(attachment)
    }

    // MARK: - Subviews

    private var attachmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stagedAttachments.enumerated()), id: \.element.id) {
                    index, attachment in
                    AttachmentChip(attachment: attachment) {
                        onRemoveAttachment(index)
                    }
                }

                // Reference Chips
                ForEach(Array(stagedReferences.enumerated()), id: \.element.id) {
                    index, reference in
                    ReferenceChip(reference: reference) {
                        onRemoveReference(index)
                    }
                }
            }
            .padding(.horizontal, LiquidGlassTokens.Spacing.sheetInset)
            .padding(.vertical, 4)
        }
        .frame(height: 44)
    }

    private var inputField: some View {
        TextField("Message...", text: $text, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(theme.bodyFont)
            .foregroundColor(theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .focused($isInputFocused)
            .background(inputFieldBackground)
            #if os(macOS)
                .onKeyPress { press in
                    if press.key == .return && !press.modifiers.contains(.shift) {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !stagedAttachments.isEmpty
                            || !stagedReferences.isEmpty
                        {
                            send()
                            return .handled
                        }
                    }
                    return .ignored
                }
            #endif
    }

    private var sendButton: some View {
        let isDisabled =
            isSending
            || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && stagedAttachments.isEmpty
                && stagedReferences.isEmpty)

        return Button(action: { send() }) {
            ZStack {
                if isSending {
                    ProgressView()
                        .progressViewStyle(.circular)
                        #if os(macOS)
                            .controlSize(.small)
                        #endif
                        .tint(theme.textPrimary)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                }
            }
            .frame(width: 36, height: 36)
            .glassEffect(
                theme.usesGlassEffect
                    ? (isDisabled
                        ? GlassEffect.clear.interactive()
                        : GlassEffect.regular.tint(theme.accent.opacity(0.25)).interactive())
                    : GlassEffect.identity,
                in: .circle
            )
            .background {
                if !theme.usesGlassEffect {
                    Circle()
                        .fill(isDisabled ? theme.textSecondary.opacity(0.18) : theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var attachmentButton: some View {
        Button {
            isImporting = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: toolButtonSize, height: toolButtonSize)
                .foregroundColor(theme.textTertiary)
                .glassEffect(
                    theme.usesGlassEffect ? GlassEffect.clear.interactive() : GlassEffect.identity,
                    in: RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.control,
                        style: .continuous
                    )
                )
                .background {
                    if !theme.usesGlassEffect {
                        RoundedRectangle(
                            cornerRadius: LiquidGlassTokens.Radius.control, style: .continuous
                        )
                        .fill(theme.surface)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var toolSelectorButton: some View {
        let anyEnabled = tools.contains { $0.isEnabled }

        return Button {
            onToolsAppear()
            isShowingTools = true
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: toolButtonSize, height: toolButtonSize)
                .foregroundColor(theme.textSecondary)
                .glassEffect(
                    theme.usesGlassEffect
                        ? (anyEnabled
                            ? GlassEffect.regular.tint(theme.accent.opacity(0.20)).interactive()
                            : GlassEffect.clear.interactive())
                        : GlassEffect.identity,
                    in: RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.control, style: .continuous
                    )
                    .stroke(
                        anyEnabled ? theme.accent.opacity(0.30) : theme.textPrimary.opacity(0.10),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .popover(isPresented: $isShowingTools, arrowEdge: .top) {
                ToolsListView(tools: tools, onToggle: onToggleTool)
                .frame(width: 320, height: 400)
            }
        #else
            .sheet(isPresented: $isShowingTools) {
                NavigationStack {
                    ToolsListView(tools: tools, onToggle: onToggleTool)
                    .navigationTitle("Tools")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isShowingTools = false }
                            .foregroundColor(theme.accent)
                        }
                    }
                }
            }
        #endif
    }

    private var thinkingSelectorButton: some View {
        Menu {
            ForEach(ThinkingPreference.allCases, id: \.self) { pref in
                Button {
                    thinkingPreference = pref
                } label: {
                    if pref == thinkingPreference {
                        Label(pref.displayName, systemImage: "checkmark")
                    } else {
                        Text(pref.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: thinkingPreference.iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: toolButtonSize, height: toolButtonSize)
                .foregroundColor(theme.textSecondary)
                .glassEffect(
                    theme.usesGlassEffect
                        ? (thinkingPreference == .off
                            ? GlassEffect.clear.interactive()
                            : GlassEffect.regular.tint(theme.accent.opacity(0.20)).interactive())
                        : GlassEffect.identity,
                    in: RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.control, style: .continuous
                    )
                    .stroke(
                        thinkingPreference == .off
                            ? theme.textPrimary.opacity(0.10) : theme.accent.opacity(0.30),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .help("Thinking: \(thinkingPreference.displayName)")
    }

    // MARK: - Backgrounds

    private var inputFieldBackground: some View {
        Group {
            if theme.usesGlassEffect {
                RoundedRectangle(cornerRadius: 14)
                    .glassEffect(
                        isInputFocused
                            ? GlassEffect.regular.tint(theme.accent.opacity(0.25)).interactive()
                            : GlassEffect.regular.interactive(),
                        in: .rect(cornerRadius: 14)
                    )
            } else {
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .stroke(
                                isInputFocused
                                    ? theme.accent.opacity(0.3) : theme.textSecondary.opacity(0.15),
                                lineWidth: theme.borderWidth
                            )
                    )
            }
        }
    }
}

// MARK: - Attachment Chip (Glass Capsule)

struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.type.icon)
                .font(.system(size: 12))
                .foregroundColor(.white)

            Text(attachment.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(GlassEffect.regular, in: .capsule)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Reference Chip

struct ReferenceChip: View {
    let reference: ChatReference
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: reference.role == .tool ? "wrench.and.screwdriver" : "quote.bubble")
                .font(.system(size: 12))
                .foregroundColor(.white)

            Text(referenceLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(GlassEffect.regular, in: .capsule)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }

    private var referenceLabel: String {
        let oneLine = reference.text.replacingOccurrences(of: "\n", with: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Reference" }
        if trimmed.count <= 28 { return trimmed }
        return String(trimmed.prefix(28)) + "…"
    }
}

// MARK: - Tools List View

struct ToolsListView: View {
    let tools: [UIToolToggleItem]
    let onToggle: (String, Bool) -> Void

    // Categorized tools
    private var categorizedTools: [(category: String, items: [UIToolToggleItem])] {
        let groups = Dictionary(grouping: tools) { tool -> String in
            let lower = tool.name.lowercased()
            if lower.contains("web") || lower.contains("browser") || lower.contains("search") {
                return "Web Capabilities"
            } else if lower.contains("code") || lower.contains("terminal")
                || lower.contains("calculator")
            {
                return "System & Coding"
            } else if lower.contains("image") || lower.contains("vision") {
                return "Vision & Media"
            } else {
                return "General"
            }
        }
        return groups
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, items: $0.value) }
    }

    // Grid layout
    private let columns = [
        GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(categorizedTools, id: \.category) { category, items in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(items) { tool in
                                VStack(spacing: 8) {
                                    ToolIconToggle(
                                        toolName: tool.name,
                                        iconName: tool.icon,
                                        isEnabled: Binding(
                                            get: { tool.isEnabled },
                                            set: { onToggle(tool.id, $0) }
                                        )
                                    )

                                    Text(tool.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(height: 28, alignment: .top)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
        }
    }
}
