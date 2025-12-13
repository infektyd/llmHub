//
//  NeonChatView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import MarkdownUI
import SwiftData
import SwiftUI

struct NeonChatView: View {
    let session: ChatSessionEntity
    @Environment(WorkbenchViewModel.self) private var workbenchVM
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @State private var chatVM = ChatViewModel()
    @StateObject private var interactionController = ChatInteractionController()
    @State private var inputText: String = ""  // Lifted state for InputPanel

    @AppStorage("windowBackgroundOpacity") private var windowBackgroundOpacity: Double = 1.0

    @State private var scrollOffset: CGFloat = 0
    // Removed messageBottomPadding as safeAreaInset handles it

    @State private var showingSettings = false
    @EnvironmentObject private var modelRegistry: ModelRegistry

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Dynamic Toolbar
            #if os(macOS)
                NeonToolbar(
                    session: session,
                    selectedProvider: Bindable(workbenchVM).selectedProvider,
                    selectedModel: Bindable(workbenchVM).selectedModel,
                    scrollOffset: scrollOffset,
                    toolInspectorVisible: Bindable(workbenchVM).toolInspectorVisible,
                    columnVisibility: Bindable(workbenchVM).columnVisibility,
                    showingSettings: $showingSettings
                )
            #endif

            transcriptSheet
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(alignment: .top) {
                    if chatVM.showContextCompactionNotification,
                        let message = chatVM.contextCompactionMessage
                    {
                        contextCompactionNotification(message: message)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let inputTokens = session.lastTokenUsageInputTokens,
                        let outputTokens = session.lastTokenUsageOutputTokens
                    {
                        TokenUsageCapsule(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            cachedTokens: session.lastTokenUsageCachedTokens ?? 0,
                            totalCost: session.totalCostUSD,
                            contextLimit: 128000
                        )
                        .padding(.trailing, 14)
                        .padding(.bottom, 120)  // Above the composer inside the sheet
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
        }
        #if os(macOS)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                .environmentObject(modelRegistry)
                .frame(width: 600, height: 500)
            }
        #endif
        .onAppear {
            #if os(iOS)
                print("🔴 LIFECYCLE: [iOS] NeonChatView.onAppear - session: \(session.id)")
            #else
                print("🔴 LIFECYCLE: [macOS] NeonChatView.onAppear - session: \(session.id)")
            #endif

            // Hydrate persistence state
            chatVM.hydrateState(
                from: session,
                workbenchVM: workbenchVM,
                modelRegistry: modelRegistry
            )
        }
        .onChange(of: workbenchVM.selectedModel) { _, newModel in
            chatVM.updateSessionModel(
                session: session,
                provider: workbenchVM.selectedProvider,
                model: newModel,
                modelContext: modelContext
            )
        }
        .onChange(of: workbenchVM.selectedProvider) { _, newProvider in
            chatVM.updateSessionModel(
                session: session,
                provider: newProvider,
                model: workbenchVM.selectedModel,
                modelContext: modelContext
            )
        }
        .onDisappear {
            #if os(iOS)
                print("🔴 LIFECYCLE: [iOS] NeonChatView.onDisappear - session: \(session.id)")
            #else
                print("🔴 LIFECYCLE: [macOS] NeonChatView.onDisappear - session: \(session.id)")
            #endif
        }
        .onAppear {
            // Wire up controller interactions
            interactionController.onAddReference = { reference in
                chatVM.addReference(reference)
            }
        }
        #if os(iOS)
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(theme.accent)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Tool Inspector Toggle
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                workbenchVM.toolInspectorVisible.toggle()
                            }
                        }) {
                            Image(systemName: "sidebar.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(theme.accent)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        theme.accent.opacity(
                                            workbenchVM.toolInspectorVisible ? 0.18 : 0.08)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                theme.accent.opacity(
                                                    workbenchVM.toolInspectorVisible ? 0.35 : 0.18),
                                                lineWidth: 1)
                                    )
                            )
                        }

                        // Model Picker Button
                        NeonModelPickerButton(
                            selectedProvider: Bindable(workbenchVM).selectedProvider,
                            selectedModel: Bindable(workbenchVM).selectedModel
                        )
                        .environmentObject(modelRegistry)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingSettings = false
                            }
                            .foregroundColor(theme.accent)
                        }
                    }
                    .environmentObject(modelRegistry)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        #endif
    }
}

// MARK: - Subviews

extension NeonChatView {
    private var transcriptSheet: some View {
        let messages = Array(session.messages)

        return GlassTranscriptSurface {
            ScrollViewReader { proxy in
                ScrollView {
                    messagesStack(messages)
                        .padding(LiquidGlassTokens.Spacing.transcriptPadding)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: NeonScrollOffsetPreferenceKey.self,
                                        value: geo.frame(in: .named("scroll")).minY
                                    )
                            }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(NeonScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                #if os(iOS)
                    .scrollDismissesKeyboard(.interactively)
                #endif
                .onChange(of: chatVM.lastVisibleMessageID) { _, newValue in
                    guard let id = newValue else { return }
                    scrollToLatest(id: id, proxy: proxy)
                }
                .onChange(of: session.messages.count) { _, _ in
                    if let lastID = messages.last?.id {
                        scrollToLatest(id: lastID, proxy: proxy, animated: false)
                    }
                }
                .onAppear {
                    if let lastID = messages.last?.id {
                        scrollToLatest(id: lastID, proxy: proxy, animated: false)
                    }
                }
            }
        } footer: {
            composerFooter
        }
    }

    private var composerFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.10),
                            .white.opacity(0.02),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
                .opacity(0.9)

            ChatInputPanel(
                text: $inputText,
                isSending: chatVM.isGenerating,
                onSend: { messageText in
                    chatVM.sendMessage(
                        messageText: messageText,
                        attachments: nil,
                        session: session,
                        modelContext: modelContext,
                        selectedProvider: workbenchVM.selectedProvider,
                        selectedModel: workbenchVM.selectedModel
                    )
                },
                tools: chatVM.toolToggles,
                onToggleTool: { id, enabled in
                    Task { await chatVM.setToolPermission(toolID: id, enabled: enabled) }
                },
                onToolsAppear: {
                    Task { await chatVM.refreshToolToggles(modelContext: modelContext) }
                },
                stagedAttachments: chatVM.stagedAttachments,
                onAddAttachment: { chatVM.addAttachment($0) },
                onRemoveAttachment: { chatVM.removeAttachment(at: $0) },
                stagedReferences: chatVM.stagedReferences,
                onRemoveReference: { chatVM.removeReference(at: $0) }
            )
            .padding(.horizontal, LiquidGlassTokens.Spacing.sheetInset)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private func scrollToLatest(id: UUID, proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    /// Creates a notification banner for context compaction.
    @ViewBuilder
    private func contextCompactionNotification(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    chatVM.showContextCompactionNotification = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .glassEffect(GlassEffect.regular.tint(.glassAccent), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    theme.accent.opacity(0.35), theme.accent.opacity(0.12),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: theme.accent.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func messagesStack(_ messages: [ChatMessageEntity]) -> some View {
        LazyVStack(spacing: 0) {  // 0 spacing, row has its own rhythm padding
            // Build map of tool calls for lookup
            let toolCallMap = buildToolCallMap(from: messages)

            // Regular messages - not streaming
            ForEach(messages, id: \.id) { message in
                let relatedTool = message.toolCallID.flatMap { toolCallMap[$0] }

                switch ThemeManager.shared.transcriptStyle {
                case .neonDark:
                    NeonMessageRow(
                        message: message,
                        relatedToolCall: relatedTool,
                        interactionController: interactionController
                    )
                    .id(message.id)
                case .liquidGlassLight:
                    NeonMessageBubble(
                        message: message,
                        relatedToolCall: relatedTool,
                        interactionController: interactionController
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .id(message.id)
                }
            }

            // Thinking indicator (before streaming starts)
            if chatVM.isThinking {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(theme.textTertiary)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.opacity)
            }

            // Streaming message (actively streaming)
            if let streaming = chatVM.streamingDisplayMessage {
                Group {
                    switch ThemeManager.shared.transcriptStyle {
                    case .neonDark:
                        NeonMessageRow(
                            message: ChatMessageEntity(message: streaming),
                            relatedToolCall: nil,
                            interactionController: interactionController
                        )
                        // Add "active streaming" affordance (cursor) overlay to the row
                        .overlay(alignment: .bottomTrailing) {
                            if chatVM.isActivelyStreaming {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 8, height: 8)
                                    .opacity(0.8)
                                    .padding(16)
                                    .offset(x: 4, y: -4)  // Approximate position near end of text
                            }
                        }
                    case .liquidGlassLight:
                        NeonMessageBubble(
                            message: ChatMessageEntity(message: streaming),
                            relatedToolCall: nil,
                            interactionController: interactionController
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .id(streaming.id)
            }

            // Continue Generating Button
            if chatVM.isTruncated && chatVM.truncatedSessionID == session.id && !chatVM.isGenerating
            {
                Button {
                    chatVM.continueGenerating(session: session, modelContext: modelContext)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .fontWeight(.semibold)
                        Text("Continue generating")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(theme.accent.opacity(0.10))
                            .glassEffect()
                            .overlay(
                                Capsule()
                                    .stroke(theme.accent.opacity(0.22), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func buildToolCallMap(from messages: [ChatMessageEntity]) -> [String: ToolCall] {
        var map: [String: ToolCall] = [:]
        for message in messages {
            guard message.role == MessageRole.assistant.rawValue,
                let data = message.toolCallsData,
                let calls = try? JSONDecoder().decode([ToolCall].self, from: data)
            else { continue }

            for call in calls {
                map[call.id] = call
            }
        }
        return map
    }
}

// MARK: - Preference Keys

struct NeonScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
