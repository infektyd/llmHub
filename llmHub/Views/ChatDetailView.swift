//
//  ChatDetailView.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var attachedImages: [Data] = []
    @State private var attachedCodeFiles: [CodeFileAttachment] = []
    @State private var isDropTargeted = false
    @State private var pendingExecution: (code: String, language: SupportedLanguage)?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.selectedSession?.messages ?? []) { message in
                            ChatMessageBubble(
                                message: message,
                                modelName: viewModel.selectedSession?.model ?? "Assistant"
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .background(.thinMaterial)
                .onChange(of: viewModel.selectedSession?.messages.count ?? 0) { _, _ in
                    if let lastID = viewModel.selectedSession?.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input area with image and code attachments
            VStack(spacing: 8) {
                // Attachment preview thumbnails
                if !attachedImages.isEmpty || !attachedCodeFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Image thumbnails
                            ForEach(attachedImages.indices, id: \.self) { index in
                                ImageThumbnail(imageData: attachedImages[index]) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        _ = attachedImages.remove(at: index)
                                    }
                                }
                            }
                            
                            // Code file thumbnails
                            ForEach(attachedCodeFiles) { codeFile in
                                CodeFileThumbnail(codeFile: codeFile) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        attachedCodeFiles.removeAll { $0.id == codeFile.id }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 72)
                }
                
                HStack {
                    // Attach image button
                    Button {
                        openFilePicker()
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach image")
                    
                    // Attach code button
                    Button {
                        openCodeFilePicker()
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach code file (.swift, .py, .ts, .js, .dart)")
                    
                    // Paste button for images
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Paste image from clipboard")
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    
                    TextField("Message", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .onSubmit {
                            Task { await send() }
                        }

                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty && attachedCodeFiles.isEmpty)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                            .padding(4)
                    )
            )
            .onDrop(of: [.image, .fileURL, .sourceCode, .plainText], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
        }
        .onAppear {
            isInputFocused = true
        }
        .sheet(item: Binding(
            get: { pendingExecution.map { ExecutionApproval(code: $0.code, language: $0.language) } },
            set: { _ in pendingExecution = nil }
        )) { approval in
            CodeExecutionPreview(
                code: approval.code,
                language: approval.language,
                onExecute: {
                    Task {
                        pendingExecution = nil
                        await executeCode(code: approval.code, language: approval.language)
                    }
                },
                onCancel: {
                    pendingExecution = nil
                }
            )
            .frame(minWidth: 500, minHeight: 400)
        }
    }
    
    // Helper for sheet binding
    private struct ExecutionApproval: Identifiable {
        let id = UUID()
        let code: String
        let language: SupportedLanguage
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImages.isEmpty || !attachedCodeFiles.isEmpty else { return }
        
        let imagesToSend = attachedImages
        let codeFilesToSend = attachedCodeFiles
        
        // Build message text
        var messageText = text
        
        // Append code files to message
        if !codeFilesToSend.isEmpty {
            for codeFile in codeFilesToSend {
                if !messageText.isEmpty {
                    messageText += "\n\n"
                }
                messageText += "```\(codeFile.language.rawValue)\n\(codeFile.code)\n```"
            }
            
            if text.isEmpty {
                messageText = "Please analyze this code:\n\n" + messageText
            }
        } else if messageText.isEmpty && !imagesToSend.isEmpty {
            messageText = "What's in this image?"
        }
        
        // Clear inputs immediately
        inputText = ""
        attachedImages = []
        attachedCodeFiles = []
        
        await viewModel.send(userMessage: messageText, images: imagesToSend)
    }
    
    // MARK: - Code Execution
    
    private func executeCode(code: String, language: SupportedLanguage) async {
        let tool = CodeInterpreterTool()
        // TODO: Get security mode from settings
        tool.securityMode = .sandbox
        
        do {
            let result = try await tool.executeWithResult(code: code, language: language)
            
            // Format result as message
            let resultMessage = """
            **Execution Result** (\(language.displayName))
            Exit Code: \(result.exitCode) \(result.isSuccess ? "✓" : "✗")
            Time: \(result.executionTimeMs)ms
            
            ```
            \(result.combinedOutput)
            ```
            """
            
            await viewModel.send(userMessage: resultMessage, images: [])
        } catch {
            await viewModel.send(userMessage: "**Execution Failed**: \(error.localizedDescription)", images: [])
        }
    }
    
    // MARK: - Paste from Clipboard (Direct NSPasteboard Access)
    
    private func pasteFromClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        
        // Try PNG first (most common for screenshots)
        if let pngData = pasteboard.data(forType: .png) {
            withAnimation(.easeIn(duration: 0.2)) {
                attachedImages.append(pngData)
            }
            return
        }
        
        // Try TIFF (macOS screenshots are often TIFF internally)
        if let tiffData = pasteboard.data(forType: .tiff) {
            // Convert TIFF to PNG for consistent handling
            if let nsImage = NSImage(data: tiffData),
               let pngData = nsImage.pngData() {
                withAnimation(.easeIn(duration: 0.2)) {
                    attachedImages.append(pngData)
                }
                return
            }
            // If conversion fails, use TIFF directly
            withAnimation(.easeIn(duration: 0.2)) {
                attachedImages.append(tiffData)
            }
            return
        }
        
        // Try to get any image from pasteboard
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let pngData = image.pngData() {
            withAnimation(.easeIn(duration: 0.2)) {
                attachedImages.append(pngData)
            }
            return
        }
        
        // Try file URLs that might be images
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                   let type = UTType(uti),
                   type.conforms(to: .image),
                   let data = try? Data(contentsOf: url) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        attachedImages.append(data)
                    }
                }
            }
        }
        #endif
    }
    
    // MARK: - Drop Handler
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // Handle image files
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data = data {
                        DispatchQueue.main.async {
                            withAnimation(.easeIn(duration: 0.2)) {
                                attachedImages.append(data)
                            }
                        }
                    }
                }
            }
            // Handle file URLs (for dragged files)
            else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    
                    // Check if it's a code file
                    if let language = SupportedLanguage.from(filename: url.lastPathComponent),
                       let code = try? String(contentsOf: url, encoding: .utf8) {
                        let attachment = CodeFileAttachment(
                            filename: url.lastPathComponent,
                            language: language,
                            code: code
                        )
                        DispatchQueue.main.async {
                            withAnimation(.easeIn(duration: 0.2)) {
                                attachedCodeFiles.append(attachment)
                            }
                        }
                        return
                    }
                    
                    // Check if it's an image
                    if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                       let type = UTType(uti),
                       type.conforms(to: .image),
                       let imageData = try? Data(contentsOf: url) {
                        DispatchQueue.main.async {
                            withAnimation(.easeIn(duration: 0.2)) {
                                attachedImages.append(imageData)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - File Picker
    
    private func openFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .tiff]
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let data = try? Data(contentsOf: url) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        attachedImages.append(data)
                    }
                }
            }
        }
        #endif
    }
    
    // MARK: - Code File Picker
    
    private func openCodeFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .swiftSource,
            .pythonScript,
            UTType(filenameExtension: "ts") ?? .plainText,
            .javaScript,
            UTType(filenameExtension: "dart") ?? .plainText
        ]
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let code = try? String(contentsOf: url, encoding: .utf8),
                   let language = SupportedLanguage.from(filename: url.lastPathComponent) {
                    let attachment = CodeFileAttachment(
                        filename: url.lastPathComponent,
                        language: language,
                        code: code
                    )
                    withAnimation(.easeIn(duration: 0.2)) {
                        attachedCodeFiles.append(attachment)
                    }
                }
            }
        }
        #endif
    }
}

// MARK: - Code File Thumbnail View

struct CodeFileThumbnail: View {
    let codeFile: CodeFileAttachment
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(systemName: languageIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(languageColor)
                
                Text(codeFile.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(codeFile.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(languageColor.opacity(0.3), lineWidth: 1)
            )
            
            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
    
    private var languageIcon: String {
        switch codeFile.language {
        case .swift: return "swift"
        case .python: return "ladybug"
        case .typescript, .javascript: return "curlybraces"
        case .dart: return "arrow.trianglehead.branch"
        }
    }
    
    private var languageColor: Color {
        switch codeFile.language {
        case .swift: return .orange
        case .python: return .blue
        case .typescript: return .blue
        case .javascript: return .yellow
        case .dart: return .cyan
        }
    }
}

// MARK: - Image Thumbnail View

struct ImageThumbnail: View {
    let imageData: Data
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
            
            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage
    let modelName: String
    
    @State private var showCopied = false
    
    // Extract images from message parts
    private var imageDataItems: [Data] {
        message.parts.compactMap { part in
            if case .image(let data, _) = part {
                return data
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.role == .user ? "You" : modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Copy button for assistant messages
                if message.role != .user && !message.content.isEmpty {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            if showCopied {
                                Text("Copied")
                                    .font(.caption2)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // Display attached images
                if !imageDataItems.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(imageDataItems.indices, id: \.self) { index in
                            MessageImageView(imageData: imageDataItems[index])
                        }
                    }
                }
                
                // Display text content
                if !message.content.isEmpty {
                    Text(message.content)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .background(message.role == .user ? .blue.opacity(0.2) : .gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #else
        UIPasteboard.general.string = message.content
        #endif
        
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopied = false
        }
    }
}

// MARK: - Message Image View

struct MessageImageView: View {
    let imageData: Data
    @State private var isExpanded = false
    
    var body: some View {
        if let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: isExpanded ? 400 : 200, maxHeight: isExpanded ? 400 : 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
                .contextMenu {
                    Button {
                        copyImageToClipboard(nsImage)
                    } label: {
                        Label("Copy Image", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        saveImageToFile(nsImage)
                    } label: {
                        Label("Save Image...", systemImage: "square.and.arrow.down")
                    }
                }
        }
    }
    
    private func copyImageToClipboard(_ image: NSImage) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #endif
    }
    
    private func saveImageToFile(_ image: NSImage) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "image.png"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
        #endif
    }
}

// MARK: - NSImage Extension for PNG Conversion

#if os(macOS)
extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

// MARK: - Flow Layout for Images

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        
        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
            }
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }
        
        totalHeight = currentY + lineHeight
        
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
