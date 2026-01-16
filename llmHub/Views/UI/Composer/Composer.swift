//  ComposerBar.swift
//  llmHub
//
//  Bottom overlay composer bar (input + send + stop)
//  Flat design with shadow, no glass effects
//

import Foundation
import SwiftData
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

// swiftlint:disable file_length

/// Pure, preview-friendly composer UI (no SwiftData, no providers).
struct ComposerBarView: View {
    @Binding var leftSidebarVisible: Bool
    @Binding var rightSidebarVisible: Bool
    @Binding var showSettings: Bool
    @Binding var inputText: AttributedString

    let isStreaming: Bool
    let stagingArtifacts: [Artifact]
    let stagedAttachments: [Attachment]
    let recentlyImportedArtifacts: [SandboxedArtifact]
    let onSend: () -> Void
    let onStop: () -> Void
    let onRemoveArtifact: (UUID) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onAddAttachment: () -> Void
    let onFilesDropped: ([URL]) -> Void
    let onLargePaste: (String) -> Void
    let forceInlinePaste: Bool

    @FocusState private var isInputFocused: Bool
    @State private var selection = AttributedTextSelection()
    @State private var isNormalizingMarkdown = false
    @State private var markdownDebounceTask: Task<Void, Never>?
    @State private var isDropTargeted = false

    // MARK: - Paste Detection State
    /// Re-entrancy guard: true while programmatically editing text (e.g., inserting stub)
    @State private var isProgrammaticEdit = false
    /// Last known character count for delta detection
    @State private var lastCharCount = 0
    /// Last known line count for delta detection
    @State private var lastLineCount = 0
    /// ID of last handled paste to prevent double-handling
    @State private var lastHandledPasteID: UUID?

    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    private var plainText: String {
        String(inputText.characters)
    }

    private var trimmedPlainText: String {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedPlainText.isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: uiCompactMode ? 10 : 12) {
            attachmentButton
                .padding(.bottom, uiCompactMode ? 8 : 10)

            VStack(alignment: .leading, spacing: 0) {
                ComposerAttachmentTray(
                    attachments: stagedAttachments,
                    onRemove: onRemoveAttachment
                )
                inputBubble
            }

            rightSidebarButton
                .padding(.bottom, uiCompactMode ? 8 : 10)

            settingsButton
                .padding(.bottom, uiCompactMode ? 8 : 10)
        }
        .padding(uiCompactMode ? 10 : 12)
        .background {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(AppColors.surface)
                .shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: -4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(
                    isDropTargeted
                        ? AppColors.accent.opacity(0.5) : AppColors.textPrimary.opacity(0.1),
                    lineWidth: isDropTargeted ? 2 : 1)
        }
        .onDisappear {
            markdownDebounceTask?.cancel()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var attachmentButton: some View {
        Button {
            onAddAttachment()
        } label: {
            Image(systemName: "rectangle.and.paperclip")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.accent)
        }
        .buttonStyle(.plain)
    }

    private var inputBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            stagedArtifactsStrip
            inputRow
        }
        .padding(.horizontal, uiCompactMode ? 10 : 12)
        .padding(.vertical, uiCompactMode ? 8 : 10)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isDropTargeted ? AppColors.accent.opacity(0.1) : AppColors.backgroundSecondary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var stagedArtifactsStrip: some View {
        if !stagingArtifacts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(stagingArtifacts) { artifact in
                        ArtifactPreviewChip(artifact: artifact) {
                            onRemoveArtifact(artifact.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            inputEditor
            sendOrStopButton
        }
    }

    private var inputEditor: some View {
        ZStack(alignment: .topLeading) {
            if plainText.isEmpty {
                Text("Type a message…")
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $inputText, selection: $selection)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 20, maxHeight: 100)
                .llmHubPasteDestination { strings in
                    let pastedText = strings.joined(separator: "\n")
                    guard !pastedText.isEmpty else { return }
                    var updatedText = inputText
                    var updatedSelection = selection
                    updatedText.replaceSelection(
                        &updatedSelection, with: attributedPasteContent(from: pastedText))
                    inputText = updatedText
                    selection = updatedSelection
                }
                .onChange(of: plainText) { oldValue, newValue in
                    detectAndHandleLargePaste(oldText: oldValue, newText: newValue)
                    normalizeMarkdownIfAppropriate(sourceText: newValue)
                }
                .onAppear {
                    // Initialize paste detection baseline
                    lastCharCount = plainText.count
                    lastLineCount = plainText.components(separatedBy: .newlines).count
                }
                .onKeyPress(.return, phases: [.down]) { keyPress in
                    handleReturnKey(keyPress)
                }
        }
    }

    @ViewBuilder
    private var sendOrStopButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14 * uiScale, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20 * uiScale, weight: .semibold))
                    .foregroundStyle(canSend ? AppColors.accent : AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    private var rightSidebarButton: some View {
        Button {
            withAnimation {
                rightSidebarVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(rightSidebarVisible ? AppColors.accent : AppColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func handleReturnKey(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) {
            return .ignored
        }
        if canSend {
            onSend()
        }
        return .handled
    }

    private func attributedPasteContent(from pastedText: String) -> AttributedString {
        if let parsed = try? AttributedString(markdown: pastedText) {
            if String(parsed.characters) != pastedText {
                return parsed
            }
        }
        return AttributedString(pastedText)
    }

    /// Normalizes markdown formatting in the input text when typing special characters.
    ///
    /// Note: This function mutates `inputText` which can trigger "AnyTextLayoutCollection updated
    /// multiple times per frame" warning when called synchronously from onChange(of: plainText).
    /// The mutation is debounced to avoid layout feedback loops.
    private func normalizeMarkdownIfAppropriate(sourceText: String) {
        guard !isNormalizingMarkdown else { return }

        markdownDebounceTask?.cancel()
        guard
            sourceText.contains("*")
                || sourceText.contains("`")
                || sourceText.contains("[")
                || sourceText.contains("#")
                || sourceText.contains(">")
                || sourceText.contains("_")
        else { return }

        guard case .insertionPoint(let insertionPoint) = selection.indices(in: inputText),
            insertionPoint == inputText.endIndex
        else { return }

        guard let parsed = try? AttributedString(markdown: sourceText) else { return }
        let parsedPlainText = String(parsed.characters)
        guard parsedPlainText != sourceText else { return }

        markdownDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await Task.yield()
            guard inputText != parsed else { return }
            isNormalizingMarkdown = true
            defer { isNormalizingMarkdown = false }
            inputText = parsed
            selection = AttributedTextSelection(range: parsed.endIndex..<parsed.endIndex)
        }
    }

    // MARK: - Paste Detection

    /// Detects large paste events and routes them to attachment conversion.
    ///
    /// Uses delta detection with re-entrancy guards to avoid:
    /// - False positives from typing/autocomplete
    /// - Double-handling when stub is inserted
    /// - Layout storm issues
    private func detectAndHandleLargePaste(oldText: String, newText: String) {
        // Guard 1: Skip if programmatic edit (e.g., stub insertion)
        guard !isProgrammaticEdit else { return }

        // Guard 2: Skip if force inline is enabled
        guard !forceInlinePaste else {
            // Still update tracking
            lastCharCount = newText.count
            lastLineCount = newText.components(separatedBy: .newlines).count
            return
        }

        // Guard 3: Skip if markdown normalization in progress
        guard !isNormalizingMarkdown else { return }

        // Calculate deltas
        let newCharCount = newText.count
        let oldCharCount = oldText.count
        let deltaChars = newCharCount - oldCharCount

        let newLineCount = newText.components(separatedBy: .newlines).count
        let oldLineCount = oldText.components(separatedBy: .newlines).count
        let deltaLines = newLineCount - oldLineCount

        // Only consider positive deltas (insertions, not deletions)
        guard deltaChars > 0 else {
            lastCharCount = newCharCount
            lastLineCount = newLineCount
            return
        }

        // Check if this looks like a paste (large delta)
        guard
            PasteConversionEngine.looksLikePaste(
                deltaChars: deltaChars,
                deltaLines: deltaLines
            )
        else {
            lastCharCount = newCharCount
            lastLineCount = newLineCount
            return
        }

        // Evaluate the pasted content for conversion
        // Extract just the pasted portion (approximation: the new chars added)
        let pastedContent: String
        if deltaChars == newCharCount {
            // Entire text is new (paste into empty field)
            pastedContent = newText
        } else {
            // Try to extract added portion from the end
            // This is an approximation - paste could be anywhere
            pastedContent = newText
        }

        let result = PasteConversionEngine.evaluate(
            text: pastedContent,
            forceInline: forceInlinePaste
        )

        // Only handle if should attach
        guard result.action == .attach else {
            lastCharCount = newCharCount
            lastLineCount = newLineCount
            return
        }

        // Generate unique ID to prevent double-handling
        let pasteID = result.artifactID
        guard lastHandledPasteID != pasteID else { return }
        lastHandledPasteID = pasteID

        // Set re-entrancy guard before modifying text
        isProgrammaticEdit = true

        // Call the large paste handler (will import to sandbox and insert stub)
        onLargePaste(pastedContent)

        // Reset input to remove the pasted content (handler will insert stub)
        // We restore the old text; the callback is responsible for inserting stub
        inputText = AttributedString(oldText)

        // Schedule guard reset to avoid race conditions
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            isProgrammaticEdit = false
            lastCharCount = plainText.count
            lastLineCount = plainText.components(separatedBy: .newlines).count
        }
    }

    /// Handles files dropped onto the composer, importing them to the artifact sandbox.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var urls: [URL] = []

            // Process providers sequentially on main actor to avoid data races
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    let url = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            continuation.resume(returning: url)
                        }
                    }
                    if let url = url {
                        urls.append(url)
                    }
                }
            }

            if !urls.isEmpty {
                self.onFilesDropped(urls)
            }
        }

        return true
    }
}

extension View {
    @ViewBuilder
    fileprivate func llmHubPasteDestination(_ action: @escaping ([String]) -> Void) -> some View {
        #if os(macOS)
            self.pasteDestination(for: String.self, action: action)
        #else
            self
        #endif
    }
}

/// Bottom composer bar for input and controls
/// Flat matte surface with shadow (no glass blur)
struct ComposerBar: View {
    @Binding var leftSidebarVisible: Bool
    @Binding var rightSidebarVisible: Bool
    @Binding var showSettings: Bool

    let selectedSession: ChatSessionEntity?
    let modelRegistry: ModelRegistry
    let viewModel: WorkbenchViewModel

    @Environment(ChatViewModel.self) private var chatVM
    @State private var inputText: AttributedString = ""
    @State private var thinkingPreference: ThinkingPreference = .auto
    @State private var isFilePickerPresented = false

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ComposerBarView(
            leftSidebarVisible: $leftSidebarVisible,
            rightSidebarVisible: $rightSidebarVisible,
            showSettings: $showSettings,
            inputText: $inputText,
            isStreaming: chatVM.isGenerating,
            stagingArtifacts: chatVM.stagingArtifacts,
            stagedAttachments: chatVM.stagedAttachments,
            recentlyImportedArtifacts: chatVM.recentlyImportedArtifacts,
            onSend: sendMessage,
            onStop: {
                Task { await chatVM.stopGeneration() }
            },
            onRemoveArtifact: { id in
                chatVM.removeStagedArtifact(id: id)
            },
            onRemoveAttachment: { id in
                chatVM.removeStagedAttachment(id: id)
            },
            onAddAttachment: {
                isFilePickerPresented = true
            },
            onFilesDropped: { urls in
                Task {
                    for url in urls {
                        await chatVM.importFileToSandbox(url: url)
                    }
                }
            },
            onLargePaste: { pastedText in
                Task { @MainActor in
                    let result = await chatVM.handleLargePaste(text: pastedText)
                    if let stub = result {
                        // Insert stub at cursor position
                        inputText = AttributedString(String(inputText.characters) + stub)
                    }
                }
            },
            forceInlinePaste: chatVM.forceInlinePaste
        )
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.item],  // Accepts any file type
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Private Methods

    private func sendMessage() {
        let messageText = String(inputText.characters)
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let session = selectedSession
        else { return }

        inputText = AttributedString("")

        // Trigger generation using ChatViewModel
        chatVM.sendMessage(
            messageText: messageText,
            attachments: nil,
            session: session,
            modelContext: modelContext,
            selectedProvider: viewModel.selectedProvider,
            selectedModel: viewModel.selectedModel,
            thinkingPreference: thinkingPreference
        )
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                #if os(macOS)
                    // On macOS, files may be security-scoped resources
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                #endif

                // Create and add the attachment for the current message
                let attachment = createAttachment(from: url)
                chatVM.addAttachment(attachment)

                // Also import to artifact sandbox for persistent LLM access
                // This ensures the file is available across sessions and models
                Task {
                    await chatVM.importFileToSandbox(url: url)
                }
            }
        case .failure(let error):
            print("File selection error: \(error.localizedDescription)")
        }
    }

    private func createAttachment(from url: URL) -> Attachment {
        let filename = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()

        // Determine attachment type based on file extension
        let type: AttachmentType
        let previewText: String?

        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            type = .image
            previewText = nil
        case "txt", "md", "rtf":
            type = .text
            previewText = try? String(contentsOf: url, encoding: .utf8).prefix(200).description
        case "swift", "py", "js", "ts", "java", "cpp", "c", "h", "m", "go", "rs":
            type = .code
            previewText = try? String(contentsOf: url, encoding: .utf8).prefix(200).description
        case "pdf":
            type = .pdf
            previewText = nil
        default:
            type = .other
            previewText = nil
        }

        return Attachment(
            filename: filename,
            url: url,
            type: type,
            previewText: previewText
        )
    }
}

#if DEBUG
    #Preview("Composer - Idle") {
        @Previewable @State var left = true
        @Previewable @State var right = false
        @Previewable @State var showSettings = false
        @Previewable @State var input: AttributedString = ""

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: false,
            stagingArtifacts: [],
            stagedAttachments: [],
            recentlyImportedArtifacts: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in },
            onAddAttachment: {},
            onFilesDropped: { _ in },
            onLargePaste: { _ in },
            forceInlinePaste: false
        )
        .padding()
        .frame(width: 900)
    }

    #Preview("Composer - Input filled") {
        @Previewable @State var left = true
        @Previewable @State var right = false
        @Previewable @State var showSettings = false
        @Previewable @State var input: AttributedString = "Hello, world!"

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: false,
            stagingArtifacts: [],
            stagedAttachments: [],
            recentlyImportedArtifacts: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in },
            onAddAttachment: {},
            onFilesDropped: { _ in },
            onLargePaste: { _ in },
            forceInlinePaste: false
        )
        .padding()
        .frame(width: 900)
    }

    #Preview("Composer - Streaming") {
        @Previewable @State var left = true
        @Previewable @State var right = true
        @Previewable @State var showSettings = false
        @Previewable @State var input: AttributedString = "Stop me"

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: true,
            stagingArtifacts: [],
            stagedAttachments: [],
            recentlyImportedArtifacts: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in },
            onAddAttachment: {},
            onFilesDropped: { _ in },
            onLargePaste: { _ in },
            forceInlinePaste: false
        )
        .padding()
        .frame(width: 900)
    }

    #Preview("Composer - Multiline") {
        @Previewable @State var left = true
        @Previewable @State var right = false
        @Previewable @State var showSettings = false
        @Previewable @State var input: AttributedString = "Line 1\nLine 2\nLine 3"

        return ComposerBarView(
            leftSidebarVisible: $left,
            rightSidebarVisible: $right,
            showSettings: $showSettings,
            inputText: $input,
            isStreaming: false,
            stagingArtifacts: [],
            stagedAttachments: [],
            recentlyImportedArtifacts: [],
            onSend: {},
            onStop: {},
            onRemoveArtifact: { _ in },
            onRemoveAttachment: { _ in },
            onAddAttachment: {},
            onFilesDropped: { _ in },
            onLargePaste: { _ in },
            forceInlinePaste: false
        )
        .padding()
        .frame(width: 900)
    }
#endif
