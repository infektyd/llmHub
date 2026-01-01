//
//  CanvasPreviewShell.swift
//  llmHub
//
//  Screenshot-style canvas UI building blocks used in SwiftUI previews.
//

import SwiftUI

#if canImport(Textual)
import Textual
#endif

struct CanvasPreviewTheme: AppTheme {
    var name: String

    var backgroundPrimary: Color
    var backgroundSecondary: Color
    var surface: Color

    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color

    var accent: Color
    var accentSecondary: Color
    var success: Color
    var warning: Color
    var error: Color

    var bodyFont: Font
    var responseFont: Font
    var monoFont: Font
    var headingFont: Font

    var usesGlassEffect: Bool
    var shadowStyle: ShadowStyle
    var cornerRadius: CGFloat
    var borderWidth: CGFloat

    var glassSmokiness: CGFloat
    var glassTintColor: Color
    var glassBlurRadius: CGFloat
}

extension CanvasPreviewTheme {
    static var screenshotDark: CanvasPreviewTheme {
        CanvasPreviewTheme(
            name: "Canvas (Dark)",
            backgroundPrimary: Color(red: 0.12, green: 0.12, blue: 0.12),
            backgroundSecondary: Color(red: 0.16, green: 0.16, blue: 0.16),
            surface: Color(red: 0.18, green: 0.18, blue: 0.18),
            textPrimary: Color.white.opacity(0.92),
            textSecondary: Color.white.opacity(0.72),
            textTertiary: Color.white.opacity(0.52),
            accent: Color(red: 0.86, green: 0.53, blue: 0.36),
            accentSecondary: Color(red: 0.26, green: 0.72, blue: 0.58),
            success: Color(red: 0.25, green: 0.80, blue: 0.36),
            warning: Color(red: 0.96, green: 0.77, blue: 0.32),
            error: Color(red: 0.93, green: 0.33, blue: 0.31),
            bodyFont: .system(size: 15),
            responseFont: .system(size: 15),
            monoFont: .system(.body, design: .monospaced),
            headingFont: .system(size: 14, weight: .semibold),
            usesGlassEffect: false,
            shadowStyle: .elevated,
            cornerRadius: 14,
            borderWidth: 1,
            glassSmokiness: 0,
            glassTintColor: .clear,
            glassBlurRadius: 0
        )
    }

    static var screenshotLight: CanvasPreviewTheme {
        CanvasPreviewTheme(
            name: "Canvas (Light)",
            backgroundPrimary: Color(red: 0.96, green: 0.96, blue: 0.97),
            backgroundSecondary: Color(red: 0.93, green: 0.93, blue: 0.95),
            surface: Color.white,
            textPrimary: Color.black.opacity(0.90),
            textSecondary: Color.black.opacity(0.70),
            textTertiary: Color.black.opacity(0.50),
            accent: Color(red: 0.77, green: 0.40, blue: 0.26),
            accentSecondary: Color(red: 0.20, green: 0.55, blue: 0.45),
            success: Color(red: 0.18, green: 0.62, blue: 0.28),
            warning: Color(red: 0.78, green: 0.52, blue: 0.10),
            error: Color(red: 0.79, green: 0.18, blue: 0.16),
            bodyFont: .system(size: 15),
            responseFont: .system(size: 15),
            monoFont: .system(.body, design: .monospaced),
            headingFont: .system(size: 14, weight: .semibold),
            usesGlassEffect: false,
            shadowStyle: .subtle,
            cornerRadius: 14,
            borderWidth: 1,
            glassSmokiness: 0,
            glassTintColor: .clear,
            glassBlurRadius: 0
        )
    }
}

struct CanvasThemeEditor: View {
    @Binding var theme: CanvasPreviewTheme

    var body: some View {
        Form {
            Section("Canvas") {
                ColorPicker("Background", selection: $theme.backgroundPrimary)
                ColorPicker("Panel", selection: $theme.backgroundSecondary)
                ColorPicker("Surface", selection: $theme.surface)
            }

            Section("Text") {
                ColorPicker("Primary", selection: $theme.textPrimary)
                ColorPicker("Secondary", selection: $theme.textSecondary)
                ColorPicker("Tertiary", selection: $theme.textTertiary)
            }

            Section("Accent") {
                ColorPicker("Accent", selection: $theme.accent)
                ColorPicker("Accent Secondary", selection: $theme.accentSecondary)
            }
        }
        .font(.system(size: 12))
    }
}

struct CanvasFloatingPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)

            content
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.backgroundSecondary.opacity(0.95))
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(theme.textPrimary.opacity(0.10), lineWidth: theme.borderWidth)
        }
        .shadow(
            color: theme.shadowStyle.color,
            radius: theme.shadowStyle.radius,
            x: theme.shadowStyle.x,
            y: theme.shadowStyle.y
        )
    }
}

struct CanvasTranscriptItem: Identifiable {
    enum Kind {
        case message(role: MessageRole, markdown: String)
        case toolSection(CanvasToolSection)
    }

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

struct CanvasToolSection: Identifiable {
    struct Step: Identifiable {
        enum Status { case pending, running, done }

        let id: UUID
        let title: String
        let status: Status

        init(id: UUID = UUID(), title: String, status: Status) {
            self.id = id
            self.title = title
            self.status = status
        }
    }

    let id: UUID
    let title: String
    let steps: [Step]

    init(id: UUID = UUID(), title: String, steps: [Step]) {
        self.id = id
        self.title = title
        self.steps = steps
    }
}

struct CanvasToolSectionView: View {
    @Environment(\.theme) private var theme
    let section: CanvasToolSection

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.steps) { step in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: step.status))
                            .foregroundStyle(color(for: step.status))
                            .font(.system(size: 12, weight: .semibold))
                        Text(step.title)
                            .foregroundStyle(theme.textPrimary.opacity(0.9))
                        Spacer()
                    }
                    .font(.system(size: 13))
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .disclosureGroupStyle(.automatic)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.surface.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(theme.textPrimary.opacity(0.10), lineWidth: theme.borderWidth)
        }
    }

    private func icon(for status: CanvasToolSection.Step.Status) -> String {
        switch status {
        case .pending: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        }
    }

    private func color(for status: CanvasToolSection.Step.Status) -> Color {
        switch status {
        case .pending: return theme.textTertiary
        case .running: return theme.warning
        case .done: return theme.success
        }
    }
}

struct CanvasMessageRow: View {
    @Environment(\.theme) private var theme
    let role: MessageRole
    let markdown: String

    @State private var hovered = false
    @State private var copied = false

    private var isUser: Bool { role == .user }
    private var hasCopyableText: Bool {
        !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 100) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                messageContent
                    .padding(.trailing, isUser ? 0 : 20)
                    .overlay(alignment: isUser ? .topLeading : .topTrailing) {
                        if shouldShowCopyButton {
                            copyButton
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 100) }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            if hasCopyableText && !isUser {
                Button("Copy") {
                    copyToClipboard()
                }
            }
        }
        #if os(macOS)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                hovered = isHovering
            }
        }
        #endif
    }

    @ViewBuilder
    private var messageContent: some View {
        #if canImport(Textual)
        StructuredText(markdown: markdown)
            .textual.structuredTextStyle(.llmHubLiquid(theme: theme))
            .textual.highlighterTheme(.llmHubLiquid(theme: theme))
            .textual.textSelection(.enabled)
        #else
        Text(markdown)
            .font(theme.responseFont)
            .foregroundStyle(theme.textPrimary)
            .textSelection(.enabled)
        #endif
    }

    private var shouldShowCopyButton: Bool {
        guard hasCopyableText && !isUser else { return false }
        #if os(macOS)
        return hovered || copied
        #else
        return true
        #endif
    }

    private var copyButton: some View {
        Button {
            copyToClipboard()
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundColor(copied ? theme.success : theme.textTertiary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .transition(.opacity)
        .accessibilityLabel("Copy response")
    }

    private func copyToClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        #else
        UIPasteboard.general.string = markdown
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

struct CanvasTranscriptView: View {
    let items: [CanvasTranscriptItem]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    switch item.kind {
                    case .message(let role, let markdown):
                        CanvasMessageRow(role: role, markdown: markdown)
                    case .toolSection(let section):
                        CanvasToolSectionView(section: section)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.vertical, 18)
        }
    }
}

struct CanvasComposerBar: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var onSend: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button {} label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)

            TextField("Reply…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .font(theme.bodyFont)

            Spacer(minLength: 0)

            Button {
                onSend?()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.accent.opacity(0.9))
                    }
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.surface.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(theme.textPrimary.opacity(0.10), lineWidth: theme.borderWidth)
        }
    }
}

struct CanvasWorkbenchShell: View {
    @Binding var theme: CanvasPreviewTheme

    @State private var showLeftPanel = true
    @State private var showRightPanel = true
    @State private var showThemeEditor = false
    @State private var composerText = ""

    private let items: [CanvasTranscriptItem] = [
        CanvasTranscriptItem(kind: .toolSection(
            CanvasToolSection(
                title: "1 step",
                steps: [
                    .init(title: "list_directory", status: .done),
                    .init(title: "read_text_file", status: .done),
                ]
            )
        )),
        CanvasTranscriptItem(kind: .message(role: .assistant, markdown: "Now let me check `ChatSessionEntity` for the lifecycle fields:")),
        CanvasTranscriptItem(kind: .toolSection(
            CanvasToolSection(
                title: "2 steps",
                steps: [
                    .init(title: "search_files", status: .done),
                    .init(title: "read_text_file", status: .done),
                ]
            )
        )),
        CanvasTranscriptItem(kind: .message(role: .assistant, markdown: "**Damn.** This is a complete, production-ready system.\n\nHere's the full inventory:")),
        CanvasTranscriptItem(kind: .message(role: .assistant, markdown: """
        ✅ Phase 1 / Phase 2 Infrastructure: COMPLETE

        | Component | Status | Notes |
        |---|---:|---|
        | ConversationClassificationService | ✅ | AFM integration + heuristic fallback |
        | ConversationLifecycleService | ✅ | Staleness rules, flag/archive/delete |
        | MemoryEntity | ✅ | SwiftData persistence |
        """)),
    ]

    var body: some View {
        ZStack {
            theme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            CanvasTranscriptView(items: items)
                                .frame(maxWidth: 860)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10)

                            CanvasComposerBar(text: $composerText)
                                .frame(maxWidth: 860)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 16)
                        }

                        if showLeftPanel {
                            CanvasFloatingPanel(title: "Conversations") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Nordic UI refinement and cleanup")
                                        .foregroundStyle(theme.textPrimary)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Pinned")
                                        .foregroundStyle(theme.textSecondary)
                                        .font(.system(size: 12))
                                }
                                .frame(width: 260, alignment: .leading)
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .padding(.leading, 12)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        if showRightPanel {
                            CanvasFloatingPanel(title: "Inspector") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Tools, model, settings…")
                                        .foregroundStyle(theme.textSecondary)
                                        .font(.system(size: 13))
                                }
                                .frame(width: 280, alignment: .leading)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .padding(.trailing, 12)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }

            if showThemeEditor {
                CanvasFloatingPanel(title: "Theme Editor") {
                    CanvasThemeEditor(theme: $theme)
                        .frame(width: 320, height: 360)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .environment(\.theme, theme)
        .animation(.easeInOut(duration: 0.20), value: showLeftPanel)
        .animation(.easeInOut(duration: 0.20), value: showRightPanel)
        .animation(.easeInOut(duration: 0.20), value: showThemeEditor)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showLeftPanel.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)

            Button {
                showRightPanel.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)

            Spacer()

            Button {
                showThemeEditor.toggle()
            } label: {
                Image(systemName: "paintpalette")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.backgroundSecondary.opacity(0.65))
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(theme.textPrimary.opacity(0.08), lineWidth: theme.borderWidth)
        }
    }
}
