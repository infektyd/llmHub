//
//  NeonChatView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftData
import SwiftUI

struct NeonChatView: View {
    let session: ChatSessionEntity
    @Environment(WorkbenchViewModel.self) private var workbenchVM
    @Environment(\.modelContext) private var modelContext
    @State private var chatVM = ChatViewModel()
    @State private var inputText: String = ""  // Lifted state for InputPanel
    @State private var showingToolsDebug = false  // Debug view for tools
    @State private var thinkingPreference: ThinkingPreference = .auto  // Thinking mode preference

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
                    showingSettings: $showingSettings,
                    showingToolsDebug: $showingToolsDebug
                )
            #endif

            // Main Content with Safe Area Inset for Input
            messageList
                .safeAreaInset(edge: .bottom) {
                    ChatInputPanel(
                        text: $inputText,
                        thinkingPreference: $thinkingPreference,
                        isSending: chatVM.isGenerating,
                        onSend: { messageText in
                            chatVM.sendMessage(
                                messageText: messageText,
                                attachments: nil, // Use staged attachments from VM
                                session: session,
                                modelContext: modelContext,
                                selectedProvider: workbenchVM.selectedProvider,
                                selectedModel: workbenchVM.selectedModel
                            )
                        },
                        onStop: {
                            // Stop generation logic
                            await chatVM.stopGeneration()
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        AdaptiveGlassBackground(target: .chatArea)
                    }
                }
                .overlay(alignment: .top) {
                    // Context Compaction Notification
                    if chatVM.showContextCompactionNotification,
                        let message = chatVM.contextCompactionMessage
                    {
                        contextCompactionNotification(message: message)
                            .transition(.move(edge: .top).combined(with: .opacity))
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
        }
        .onDisappear {
            #if os(iOS)
                print("🔴 LIFECYCLE: [iOS] NeonChatView.onDisappear - session: \(session.id)")
            #else
                print("🔴 LIFECYCLE: [macOS] NeonChatView.onDisappear - session: \(session.id)")
            #endif
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
                        .foregroundColor(.neonElectricBlue)
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
                            .foregroundColor(.neonElectricBlue)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        Color.neonElectricBlue.opacity(
                                            workbenchVM.toolInspectorVisible ? 0.18 : 0.08)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                Color.neonElectricBlue.opacity(
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
                            .foregroundColor(.neonElectricBlue)
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
    private var messageList: some View {
        AnyView(
            {
                let messages = Array(session.messages)

                return AnyView(
                    ScrollViewReader { proxy in
                        ScrollView {
                            messagesStack(messages)
                                .padding(20)
                                // Bottom padding handled by safeAreaInset
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
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(NeonScrollOffsetPreferenceKey.self) { value in
                            scrollOffset = value
                        }
                        #if os(iOS)
                            .scrollDismissesKeyboard(.interactively)
                        #endif
                        .background(AdaptiveGlassBackground(target: .chatArea))
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
                )
            }())
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
                .foregroundStyle(Color.neonElectricBlue)

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
            RoundedRectangle(cornerRadius: 06)
                .glassEffect(.regular.tint(.glassAccent), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 06)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .neonElectricBlue.opacity(0.5), .neonElectricBlue.opacity(0.2),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .neonElectricBlue.opacity(0.3), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func messagesStack(_ messages: [ChatMessageEntity]) -> some View {
        LazyVStack(spacing: 20) {
            // Regular messages - not streaming
            ForEach(messages, id: \.id) { message in
                NeonMessageBubble(message: message, isStreaming: false)
                    .equatable()
                    .id(message.id)
            }

            // Thinking indicator (before streaming starts)
            if chatVM.isThinking {
                HStack(spacing: 12) {
                    Circle()
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.tint(.glassAI), in: .circle)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        )

                    Text("Thinking...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Streaming message (actively streaming)
            if let streaming = chatVM.streamingDisplayMessage {
                NeonMessageBubble(
                    message: ChatMessageEntity(message: streaming),
                    isStreaming: true
                )
                .id(streaming.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

// MARK: - Preference Keys

struct NeonScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
